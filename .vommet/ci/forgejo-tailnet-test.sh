#!/usr/bin/env bash
# Offline test for forgejo-tailnet.sh: a local HTTP server stands in for Forgejo's tailnet
# address and records what git sends it.   bash .vommet/ci/forgejo-tailnet-test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); sut=$here/forgejo-tailnet.sh
w=$(mktemp -d); trap 'kill $srv 2>/dev/null; rm -rf "$w"' EXIT
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }

cat > "$w/srv.py" <<'EOF'
import http.server, sys
log = open(sys.argv[2], "a")
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        log.write("%s auth=%s\n" % (self.path, self.headers.get("Authorization", "-"))); log.flush()
        code = 200 if self.path == "/api/v1/version" else 404
        self.send_response(code); self.end_headers()
        if code == 200: self.wfile.write(b'{"version":"test"}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 "$w/srv.py" "$port" "$w/req.log" & srv=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$port/api/v1/version" && break; sleep 0.1; done
dead=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')

PUB=https://pub.invalid; HDR='AUTHORIZATION: basic dGVzdDp0ZXN0'
export GITHUB_SERVER_URL=$PUB GITHUB_REPOSITORY=nether/vommet
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # only the test repo's own config counts
checkout() { rm -rf "$w/r"; git init -q "$w/r"; [ "${1:-}" = nohdr ] || git -C "$w/r" config "http.$PUB/.extraheader" "$HDR"; }
run() { : > "$w/out"; (cd "$w/r" && GITHUB_OUTPUT=$w/out FORGEJO_TAILNET=$1 "$sut" ${2:-}) >/dev/null; }
outv() { sed -n "s/^$1=//p" "$w/out"; }
asked() { : > "$w/req.log"; git -C "$w/r" ls-remote "$PUB/nether/vommet.git" >/dev/null 2>&1; grep -m1 'info/refs' "$w/req.log"; }

# 1. Tailnet answers, --git: outputs point at it and git sends the checkout's header there.
checkout; run "http://127.0.0.1:$port" --git
[ "$(outv api)" = "http://127.0.0.1:$port/api/v1/repos/nether/vommet" ] && ok "api output is the tailnet" || bad "api output: $(outv api)"
[ "$(outv src)" = "http://127.0.0.1:$port/nether/vommet.git" ] && ok "src output is the tailnet" || bad "src output: $(outv src)"
r=$(asked)
[ -n "$r" ] && ok "git fetches over the tailnet" || bad "git did not reach the tailnet server"
[ "${r#* auth=}" = "${HDR#AUTHORIZATION: }" ] && ok "git sends the checkout credential to the tailnet" || bad "credential not sent: $r"

# 2. What a bare insteadOf (no header copy) would do: the request goes out without a credential.
checkout; git -C "$w/r" config "url.http://127.0.0.1:$port/.insteadOf" "$PUB/"; r=$(asked)
[ "${r#* auth=}" = - ] && ok "without the copy git sends no credential (why the copy is needed)" || bad "unexpected: $r"

# 3. Tailnet down: public URLs, git untouched.
checkout; run "http://127.0.0.1:$dead" --git
[ "$(outv api)" = "$PUB/api/v1/repos/nether/vommet" ] && ok "tailnet down: api stays public" || bad "tailnet down: api $(outv api)"
[ -z "$(git -C "$w/r" config --get-regexp '^url\.' )" ] && ok "tailnet down: no url rewrite" || bad "tailnet down: url rewrite set"

# 4. No checkout credential: git and outputs stay public (a push would otherwise 401).
checkout nohdr; run "http://127.0.0.1:$port" --git
[ "$(outv server)" = "$PUB" ] && ok "no credential: stays public" || bad "no credential: server $(outv server)"
[ -z "$(git -C "$w/r" config --get-regexp '^url\.')" ] && ok "no credential: no url rewrite" || bad "no credential: url rewrite set"

# 5. Without --git: outputs only, git config untouched.
checkout; run "http://127.0.0.1:$port"
[ "$(outv server)" = "http://127.0.0.1:$port" ] && [ -z "$(git -C "$w/r" config --get-regexp '^url\.')" ] \
  && ok "without --git: outputs only" || bad "without --git: server $(outv server)"

[ $fail = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
