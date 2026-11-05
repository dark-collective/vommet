#!/usr/bin/env python3
"""Generate commet/lib/utils/translation/models.dart from Mozilla's Remote Settings
translations-models records (tm.json). Release-channel models only."""
import json, re, sys, collections
d = json.load(open(sys.argv[1]))['data']
DESKTOP = {'', None, "env.appinfo.OS != 'Android' || env.channel != 'release'"}
ANDROID = {'', None, "env.appinfo.OS == 'Android' "}
def vkey(v):
    m = re.match(r'^(\d+)\.(\d+)$', v)
    return (int(m.group(1)), int(m.group(2))) if m else None
def best(allowed):
    groups = collections.defaultdict(list)
    for r in d:
        if r.get('filter_expression') not in allowed or vkey(r['version']) is None: continue
        groups[(r['fromLang'], r['toLang'], r['version'])].append(r)
    out = {}
    for (f, t, v), rs in groups.items():
        types = sorted(r['fileType'] for r in rs)
        if types not in (['lex', 'model', 'vocab'], ['lex', 'model', 'srcvocab', 'trgvocab']): continue
        if (f, t) not in out or vkey(v) > vkey(out[(f, t)][0]): out[(f, t)] = (v, rs)
    return out
desk, andr = best(DESKTOP), best(ANDROID)
order = {'model': 0, 'lex': 1, 'vocab': 2, 'srcvocab': 3, 'trgvocab': 4}
def entry(f, t, v, rs, plat):
    files = []
    for r in sorted(rs, key=lambda r: order[r['fileType']]):
        a = r['attachment']
        files.append(f'      F.{r["fileType"]}("{r["name"]}", "{a["location"].split("/")[-1]}", {a["size"]},\n          "{a["hash"]}"),')
    return f'  TranslationModelSpec("{f}", "{t}", "{v}", ModelPlatforms.{plat}, [\n' + '\n'.join(files) + '\n  ]),'
lines = []
for k in sorted(set(desk) | set(andr)):
    dv, av = desk.get(k), andr.get(k)
    if dv and av and dv[0] == av[0]:
        lines.append(entry(*k, dv[0], dv[1], 'all'))
    else:
        if dv: lines.append(entry(*k, dv[0], dv[1], 'desktop'))
        if av: lines.append(entry(*k, av[0], av[1], 'android'))
print('''// GENERATED from Mozilla's Remote Settings collection "translations-models"
// (the Firefox Translations release-channel models), records fetched 2026-10-25.
// Regenerate: packages/bergamot_translator/tool/gen_catalog.py <records.json>; do not edit by hand.

import 'package:commet/utils/translation_model_spec.dart';

const translationModelSpecs = <TranslationModelSpec>[''')
print('\n'.join(lines))
print('];')
