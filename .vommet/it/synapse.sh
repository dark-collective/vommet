#!/usr/bin/env bash
# Synapse as the integration tests' https://localhost homeserver, instead of
# Tuwunel (homeserver.sh with IT_HS=synapse calls this once the certificates
# exist). Runs in the test's own container, in a Python venv: the CI job runs
# inside a container, so a Synapse container beside it would not share its
# localhost (the tests and IT_FEDERATION's second server at 127.0.0.1:8449
# reach Synapse there, and Synapse reaches them).
#
# Env: WORK (with tls.crt/tls.key), SYNAPSE_VERSION (pinned PyPI release),
# SYNAPSE_VENV (reused when it already has that version; CI caches it).
# Leaves Synapse running; pid in $WORK/synapse.pid, log in $WORK/synapse.log.
set -euo pipefail
WORK=${WORK:-/tmp/vommet-it}
SYNAPSE_VERSION=${SYNAPSE_VERSION:-1.162.0}
venv=${SYNAPSE_VENV:-$HOME/synapse-venv-$SYNAPSE_VERSION}

if [[ $("$venv/bin/python" -c 'import synapse; print(synapse.__version__)' 2>/dev/null) != "$SYNAPSE_VERSION" ]]; then
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check "matrix-synapse==$SYNAPSE_VERSION"
fi

data=$WORK/synapse
mkdir -p "$data"
cd "$data"
"$venv/bin/python" -m synapse.app.homeserver --server-name localhost --report-stats=no \
  --config-path homeserver.yaml --data-directory "$data" --generate-config >/dev/null
# The generated listener (plain http on 8008) goes; ours serves client and
# federation API on 443 with homeserver.sh's certificate. No rate limits, and
# federation over loopback with self-signed certificates is allowed.
"$venv/bin/python" - homeserver.yaml "$WORK" <<'PY'
import re, sys
p, work = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(r"listeners:\n(  - .*\n(    .*\n)*)", "", s)
lim = "{per_second: 1000, burst_count: 1000}"
s += f"""
listeners:
  - port: 443
    tls: true
    type: http
    x_forwarded: false
    bind_addresses: ['127.0.0.1']
    resources: [{{names: [client, federation], compress: false}}]
public_baseurl: https://localhost/
serve_server_wellknown: true
tls_certificate_path: {work}/tls.crt
tls_private_key_path: {work}/tls.key
federation_verify_certificates: false
ip_range_blacklist: []
federation_ip_range_blacklist: []
trusted_key_servers: []
suppress_key_server_warning: true
enable_registration: true
enable_registration_without_verification: true
rc_message: {lim}
rc_registration: {lim}
rc_joins: {{local: {lim}, remote: {lim}}}
rc_login: {{address: {lim}, account: {lim}, failed_attempts: {lim}}}
rc_key_requests: {lim}
rc_invites: {{per_room: {lim}, per_user: {lim}}}
"""
open(p, "w").write(s)
PY
nohup "$venv/bin/python" -m synapse.app.homeserver --config-path homeserver.yaml >"$WORK/synapse.log" 2>&1 &
echo $! > "$WORK/synapse.pid"
echo "synapse $SYNAPSE_VERSION starting (pid $(cat "$WORK/synapse.pid"))"
