#!/usr/bin/env bash
# Vommet: a throwaway Matrix homeserver + Watch Together backend on 127.0.0.1,
# so the nightly widget check (run.sh, host.mjs) signs in to Watch Together
# for real: Synapse (plain http on 127.0.0.1:8008, server name "localhost")
# with a made-up viewer and bot account and one room, and Watch Together's
# backend built from a nether/widgets checkout, checking OpenID tokens at that
# Synapse (its openid_server_urls) and serving only that room.
#
#   WT_SRC=<nether/widgets checkout>/watch-together .vommet/widgets/wt-local.sh <work dir>
#
# Env: SYNAPSE_VERSION (pinned PyPI release), SYNAPSE_VENV (reused when it has
# that version; CI caches it). Needs python3-venv, go, curl, node.
# Leaves them running (pids in <work dir>/pids) and writes <work dir>/env
# (NIGHTLY_* for host.mjs).
# Nothing here is a secret: made-up accounts on a server that only listens on
# loopback and is gone when the job ends.
set -euo pipefail
WORK=${1:?work dir}
: "${WT_SRC:?WT_SRC: the watch-together folder of a nether/widgets checkout}"
SYNAPSE_VERSION=${SYNAPSE_VERSION:-1.162.0}
venv=${SYNAPSE_VENV:-$HOME/synapse-venv-$SYNAPSE_VERSION}
HS=http://127.0.0.1:8008
WT=http://127.0.0.1:8099
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)

echo "== Synapse $SYNAPSE_VERSION"
if [[ $("$venv/bin/python" -c 'import synapse; print(synapse.__version__)' 2>/dev/null) != "$SYNAPSE_VERSION" ]]; then
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check "matrix-synapse==$SYNAPSE_VERSION"
fi
data=$WORK/synapse
mkdir -p "$data"
(cd "$data" && "$venv/bin/python" -m synapse.app.homeserver --server-name localhost --report-stats=no \
  --config-path homeserver.yaml --data-directory "$data" --generate-config >/dev/null)
"$venv/bin/python" - "$data/homeserver.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"listeners:\n(  - .*\n(    .*\n)*)", "", s)
lim = "{per_second: 1000, burst_count: 1000}"
s += f"""
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: false
    bind_addresses: ['127.0.0.1']
    resources: [{{names: [client, federation], compress: false}}]
public_baseurl: http://127.0.0.1:8008/
trusted_key_servers: []
suppress_key_server_warning: true
enable_registration: true
enable_registration_without_verification: true
rc_message: {lim}
rc_registration: {lim}
rc_joins: {{local: {lim}, remote: {lim}}}
rc_login: {{address: {lim}, account: {lim}, failed_attempts: {lim}}}
rc_invites: {{per_room: {lim}, per_user: {lim}}}
"""
open(p, "w").write(s)
PY
nohup "$venv/bin/python" -m synapse.app.homeserver --config-path "$data/homeserver.yaml" >"$WORK/synapse.log" 2>&1 &
echo $! >> "$WORK/pids"
for _ in $(seq 120); do curl -fs "$HS/_matrix/client/versions" >/dev/null && break; sleep 0.5; done
curl -fs "$HS/_matrix/client/versions" >/dev/null || { echo "Synapse didn't start"; tail -n 30 "$WORK/synapse.log"; exit 1; }

# Accounts, room and invite, in node (fetch + JSON without jq).
node --input-type=module - "$HS" "$WORK/accounts.json" <<'JS'
import fs from "node:fs";
const [hs, out] = process.argv.slice(2);
const call = async (method, path, token, body) => {
  const r = await fetch(hs + path, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`${method} ${path}: HTTP ${r.status} ${JSON.stringify(j)}`);
  return j;
};
const register = (username) =>
  call("POST", "/_matrix/client/v3/register", null, {
    username, password: `nightly-${Math.random().toString(36).slice(2)}`, auth: { type: "m.login.dummy" }, inhibit_login: false,
  });
const viewer = await register("nightly");
const bot = await register("watchtogether");
const room = await call("POST", "/_matrix/client/v3/createRoom", viewer.access_token, {
  preset: "private_chat", name: "Watch Together nightly", invite: [bot.user_id],
});
fs.writeFileSync(out, JSON.stringify({ viewer, bot, room: room.room_id }));
console.log(`viewer ${viewer.user_id}, bot ${bot.user_id} invited to ${room.room_id}`);
JS
acct() { node -e 'const a = require(process.argv[1]); console.log(process.argv[2].split(".").reduce((o, k) => o[k], a))' "$WORK/accounts.json" "$1"; }
viewer=$(acct viewer.user_id) viewer_token=$(acct viewer.access_token)
bot=$(acct bot.user_id) bot_token=$(acct bot.access_token) room=$(acct room)

echo "== Watch Together ($(git -C "$WT_SRC" rev-parse --short HEAD 2>/dev/null || echo '?'))"
(cd "$WT_SRC" && go build -o "$WORK/watch-together" ./cmd/watch-together)
# A one-stream test addon: Watch Together needs an account or an addon, and
# sign-in needs neither to work.
SAMPLE_URL=http://127.0.0.1:9/none nohup python3 "$WT_SRC/deploy/test/addon.py" 8098 >"$WORK/addon.log" 2>&1 &
echo $! >> "$WORK/pids"
cat > "$WORK/wt.toml" <<EOF
listen = "127.0.0.1:8099"
data_dir = "$WORK/wt-data"

[stremio]
addons = ["http://127.0.0.1:8098/manifest.json"]

[matrix]
homeserver_url = "$HS"
user_id = "$bot"
allowed_servers = ["localhost"]
allowed_inviters = ["$viewer"]
allowed_rooms = ["$room"]
openid_server_urls = { "localhost" = "$HS" }
EOF
WT_MATRIX_ACCESS_TOKEN=$bot_token nohup "$WORK/watch-together" -config "$WORK/wt.toml" >"$WORK/watch-together.log" 2>&1 &
echo $! >> "$WORK/pids"
# Ready once the bot has accepted the invite.
joined=
for _ in $(seq 60); do
  if curl -fs -H "Authorization: Bearer $viewer_token" "$HS/_matrix/client/v3/rooms/$room/joined_members" 2>/dev/null | grep -qF "\"$bot\""; then
    joined=1 && break
  fi
  sleep 0.5
done
[ -n "$joined" ] || { echo "Watch Together's bot didn't join the room"; tail -n 30 "$WORK/watch-together.log"; exit 1; }
curl -fs "$WT/api/time" >/dev/null || { echo "Watch Together isn't answering"; tail -n 30 "$WORK/watch-together.log"; exit 1; }

cat > "$WORK/env" <<EOF
NIGHTLY_MATRIX_HOMESERVER=$HS
NIGHTLY_MATRIX_USER=$viewer
NIGHTLY_MATRIX_TOKEN=$viewer_token
NIGHTLY_WT_ROOM=$room
NIGHTLY_WT_URL=$WT
NIGHTLY_WT_LOG=$WORK/watch-together.log
EOF
echo "ready: $viewer in $room, Watch Together at $WT"
