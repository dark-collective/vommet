#!/usr/bin/env python3
# Trial only (issue 1088): find which Rust call releases a vodozemac object it doesn't own.
# Instruments vodozemac's JS glue:
#  - every Arc increment/decrement records the strong count (wasm memory, ptr-8) per object;
#  - every wire__* call is wrapped: afterwards each known object's count must have dropped by
#    at most the increments Dart made since the previous call (one per argument). A larger drop
#    is logged as "NVBARC EXTRA-drop in <fn>"; a release on a freed object is logged as
#    "NVBARC dec on freed", both with the object's last events.
import re, sys
p = sys.argv[1]
s = open(p).read()
probe = r'''
    const __nvbPage = Math.round(performance.timeOrigin) % 1000000;
    globalThis.__nvbGlueLoads = (globalThis.__nvbGlueLoads || 0) + 1; const __nvbGlue = globalThis.__nvbGlueLoads;
    console.error(`NVBARC glue loaded #${__nvbGlue} [page ${__nvbPage}] t=${Math.round(performance.now())}ms\n${new Error().stack}`);
    if (typeof addEventListener === 'function') addEventListener('pagehide', () => console.error(`NVBARC pagehide [page ${__nvbPage} glue ${__nvbGlue}] t=${Math.round(performance.now())}ms stats ${typeof __nvbStats === 'object' ? JSON.stringify(__nvbStats) : ''}`));
    const __nvb = new Map(); let __nvbLogs = 0; const __nvbPend = new Map();
    const __nvbStats = { extra: {}, freedDec: {}, calls: 0, created: 0, inc: 0, dec: 0, unseenDecOk: 0, unseenDecBad: 0, unseenInc: 0 };
    const __nvbRing = []; let __nvbSeq = 0;
    function __nvbJ(v) { try { return JSON.stringify(v, (k, x) => typeof x === 'bigint' ? `${x}n` : (x instanceof Uint8Array ? `u8[${x.length}]` : x)).slice(0, 300); } catch (e) { return `?${typeof v}`; } }
    function __nvbFind(ptr) {
        const re = new RegExp(`(^|[^0-9])${ptr}([^0-9]|$)`); const hits = [];
        for (let i = __nvbRing.length - 1; i >= 0 && hits.length < 4; i--) { const e = __nvbRing[i]; if (re.test(e.a) || re.test(e.r)) hits.push(`#${e.n}(${__nvbSeq - e.n} calls ago) ${e.f} args=${e.a} ret=${e.r}`); }
        return hits.length ? hits.join('\n    ') : 'not in last 400 wire calls';
    }
    function __nvbMem(ptr) {
        try { return new Uint32Array(wasm.memory.buffer)[((ptr >>> 0) - 8) >>> 2]; } catch (e) { return -1; }
    }
    function __nvbEv(o, ev) { o.h.push(ev); if (o.h.length > 14) o.h.shift(); }
    function __nvbLog(kind, ptr, o, extra) {
        if (__nvbLogs++ >= 60) return;
        console.error(`NVBARC ${kind} type=${o.t} ptr=${ptr} ${extra} [page ${__nvbPage} glue ${__nvbGlue}]\n  history: ${o.h.join(' | ')}`);
    }
    function __nvbOp(type, ptr, op) {
        const c = __nvbMem(ptr);
        let o = __nvb.get(ptr);
        __nvbStats[op]++;
        if (!o) {
            o = { t: type, last: c, h: ['first-seen'] }; __nvb.set(ptr, o);
            if (op === 'inc') __nvbStats.unseenInc++;
            else if (c === 0 || c > 10000000) { __nvbStats.unseenDecBad++; if (__nvbLogs < 60) console.error(`NVBARC unseen-dec type=${type} ptr=${ptr} strong=${c} [page ${__nvbPage}] stack: ${__nvbSrc()}\n    ring: ${__nvbFind(ptr)}`); }
            else __nvbStats.unseenDecOk++;
        }
        else if (o.t !== type) { if (o.t[0] === '?') o.t = type; else __nvbEv(o, `TYPE ${o.t}->${type}`); }
        if (op === 'dec' && (c === 0 || c > 10000000)) {
            __nvbStats.freedDec[type] = (__nvbStats.freedDec[type] || 0) + 1;
            __nvbEv(o, `dec@${c}`);
            __nvbLog('dec on freed', ptr, o, `strong=${c}`);
        } else __nvbEv(o, `${op}@${c}`);
        if (op === 'inc') { __nvbPend.set(ptr, (__nvbPend.get(ptr) || 0) + 1); o.last = c + 1; }
        else { o.last = c - 1; if (c === 1) { o.freed = true; __nvbEv(o, `FREED(${__nvbSrc()})`); } }
    }
    function __nvbPost(fn) {
        __nvbStats.calls++;
        const name = fn.replace('wire__crate__bindings__', '');
        for (const [ptr, o] of __nvb) {
            if (o.freed) continue;
            const c = __nvbMem(ptr);
            const pend = __nvbPend.get(ptr) || 0;
            if (c === o.last && !pend) continue;
            const extra = (o.last - c) - pend;
            __nvbEv(o, `${name}:${o.last}->${c}${pend ? `(args ${pend})` : ''}`);
            if (extra > 0) {
                __nvbStats.extra[`${o.t} in ${name}`] = (__nvbStats.extra[`${o.t} in ${name}`] || 0) + 1;
                __nvbLog(`EXTRA-drop in ${name}`, ptr, o, `count ${o.last}->${c}, args ${pend}`);
            }
            o.last = c;
            if (c === 0) { o.freed = true; __nvbEv(o, `FREED-in-${name}`); }
        }
        __nvbPend.clear();
    }
    function __nvbSrc() {
        const st = (new Error().stack || '').split('\n').slice(3, 9).map(l => l.trim().replace(/^at /, '').replace(/\(.*\//, '(').slice(0, 60));
        return st.length <= 1 ? 'gc' : st.join(' < ');
    }
    function __nvbScan(v, fn, depth) {
        if (!Array.isArray(v) || depth > 6) return;
        if (v.length === 2 && typeof v[0] === 'number' && typeof v[1] === 'number' && v[0] > 65536 && v[0] % 4 === 0 && v[1] > 0 && v[1] < 1000000) {
            const ptr = v[0]; const old = __nvb.get(ptr); __nvbStats.created++;
            const name = fn.replace('wire__crate__bindings__', '');
            // a moved-in object freed inside the call can share the address of the new one
            if (old && !old.freed) __nvbEv(old, `(live, address reused)`);
            const o = { t: old ? old.t : '?', last: __nvbMem(ptr), h: old ? old.h.concat([`REUSED-by-${name}`]) : [`new-by-${name}`] };
            if (o.h.length > 14) o.h = o.h.slice(-14);
            __nvb.set(ptr, o); return;
        }
        for (const x of v) __nvbScan(x, fn, depth + 1);
    }
    globalThis.__nvbArcStats = () => JSON.stringify(__nvbStats);
'''
s = s.replace("    let wasm = undefined;\n", "    let wasm = undefined;\n" + probe, 1)
n = 0
def sub(m):
    global n; n += 1
    kind, t = m.group(1), m.group(2)
    return m.group(0) + f"\n        __nvbOp('{t}', ptr, '{kind[:3]}');"
s = re.sub(r"__exports\.rust_arc_(increment|decrement)_strong_count_RustOpaque_(\w+) = function\(ptr\) \{", sub, s)
wrap = r'''
    { const __i = __wbg_init; __wbg_init = async function (...a) { console.error(`NVBARC wasm init called [page ${__nvbPage} glue ${__nvbGlue}] wasm=${wasm !== undefined ? 'already' : 'new'} t=${Math.round(performance.now())}ms\n${new Error().stack}`); return __i.apply(this, a); }; }
    for (const k of Object.keys(__exports)) {
        if (!k.startsWith('wire__')) continue;
        const f = __exports[k];
        __exports[k] = function (...a) { let r; try { r = f.apply(this, a); return r; } finally { __nvbPost(k); try { __nvbScan(r, k, 0); } catch (e) {}
            __nvbRing.push({ n: ++__nvbSeq, f: k.replace('wire__crate__bindings__', ''), a: __nvbJ(a), r: __nvbJ(r) }); if (__nvbRing.length > 400) __nvbRing.shift();
            if (__nvbSeq % 500 === 0) console.error(`NVBARC stats [page ${__nvbPage}] ${JSON.stringify(__nvbStats)}`); } };
    }
'''
anchor = "    wasm_bindgen = Object.assign(__wbg_init, { initSync }, __exports);"
assert anchor in s, 'glue anchor missing'
s = s.replace(anchor, wrap + anchor, 1)
open(p, 'w').write(s)
print(f"arc probe v5: {n} inc/dec functions + wire calls instrumented")
