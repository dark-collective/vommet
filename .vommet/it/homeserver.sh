#!/usr/bin/env bash
# Start a throwaway Tuwunel homeserver at https://localhost for the
# integration tests, with a self-signed CA installed system-wide (Commet's login
# page only speaks https). Then create the test users and a DM, mirroring
# upstream's scripts/integration-prepare-homeserver.sh.
#
# Env: TUWUNEL (path to the binary), USER1_NAME/PW, USER2_NAME/PW;
# IT_FEDERATION, IT_HS, IT_HS_EXTERNAL (below).
# Leaves the server running; logs in $WORK/tuwunel.log (synapse.log).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/tmp/vommet-it}
TUWUNEL=${TUWUNEL:?path to the tuwunel binary}
mkdir -p "$WORK/db"
cd "$WORK"

# CA + localhost certificate, trusted system-wide (Dart reads /etc/ssl/certs).
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=Vommet IT CA' \
  -keyout ca.key -out ca.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj '/CN=localhost' -keyout tls.key -out tls.csr 2>/dev/null
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\n' > ext.cnf
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 2 -extfile ext.cnf -out tls.crt 2>/dev/null
cp ca.crt /usr/local/share/ca-certificates/vommet-it-ca.crt
update-ca-certificates >/dev/null

cat > tuwunel.toml <<TOML
[global]
server_name = "localhost"
database_path = "$WORK/db"
address = ["127.0.0.1"]
port = 443
allow_registration = true
yes_i_am_very_very_sure_i_want_an_open_registration_server_prone_to_abuse = true
allow_federation = false
log = "warn"

[global.tls]
certs = "$WORK/tls.crt"
key = "$WORK/tls.key"

[global.well_known]
client = "https://localhost"
TOML

# IT_FEDERATION=1: federation on, and a second homeserver ("127.0.0.1:8449",
# user USER1_NAME) for tests whose users are on different servers. Loopback
# addresses and the self-signed certificates have to be allowed for that.
fed_settings() {
  cat <<FED
allow_federation = true
allow_invalid_tls_certificates = true
ip_range_denylist = []
trusted_servers = []
FED
}
if [[ ${IT_FEDERATION:-} == 1 ]]; then
  sed -i 's/^allow_federation = false$//; s/^port = 443$/port = [443, 8448]/' tuwunel.toml
  sed -i "/^log = /r /dev/stdin" tuwunel.toml < <(fed_settings)
  sed -i 's#^client = "https://localhost"#client = "https://localhost"\nserver = "localhost:443"#' tuwunel.toml
  mkdir -p "$WORK/db2"
  cat > tuwunel2.toml <<TOML
[global]
server_name = "127.0.0.1:8449"
database_path = "$WORK/db2"
address = ["127.0.0.1"]
port = 8449
allow_registration = true
yes_i_am_very_very_sure_i_want_an_open_registration_server_prone_to_abuse = true
log = "warn"
$(fed_settings)

[global.tls]
certs = "$WORK/tls.crt"
key = "$WORK/tls.key"
TOML
  TUWUNEL_CONFIG="$WORK/tuwunel2.toml" nohup "$TUWUNEL" >"$WORK/tuwunel2.log" 2>&1 &
  echo $! > "$WORK/tuwunel2.pid"
fi

# IT_HS=synapse: Synapse instead of Tuwunel at https://localhost
# (.vommet/it/synapse.sh). IT_HS_EXTERNAL=1: the caller starts the homeserver
# at https://localhost in this network namespace, using $WORK/tls.{crt,key}
# (for example a container sharing it); only wait for it.
hs_log=$WORK/tuwunel.log
if [[ ${IT_HS:-} == synapse ]]; then
  "$here/synapse.sh"
  hs_log=$WORK/synapse.log
  wait_s=300
elif [[ ${IT_HS_EXTERNAL:-} == 1 ]]; then
  touch "$WORK/certs-ready"
  wait_s=300
else
  TUWUNEL_CONFIG="$WORK/tuwunel.toml" nohup "$TUWUNEL" >"$WORK/tuwunel.log" 2>&1 &
  echo $! > "$WORK/tuwunel.pid"
  wait_s=60
fi

HS=https://localhost
for _ in $(seq $wait_s); do
  curl -fsS "$HS/_matrix/client/versions" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "$HS/_matrix/client/versions" >/dev/null || { cat "$hs_log"; echo "homeserver did not come up" >&2; exit 1; }
echo "homeserver up at $HS"

register() {  # name password -> access token
  curl -fsS -X POST "$HS/_matrix/client/v3/register" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$2\",\"auth\":{\"type\":\"m.login.dummy\"},\"inhibit_login\":false}" \
    | jq -r .access_token
}
t1=$(register "$USER1_NAME" "$USER1_PW")
t2=$(register "$USER2_NAME" "$USER2_PW")
[[ $t1 != null && $t2 != null ]] || { echo "registration failed" >&2; exit 1; }
for pair in "$t1:$USER1_NAME" "$t2:$USER2_NAME"; do
  tok=${pair%%:*}; name=${pair#*:}
  curl -fsS -X PUT "$HS/_matrix/client/v3/profile/@$name:localhost/displayname" \
    -H "Authorization: Bearer $tok" -d "{\"displayname\":\"$name\"}" >/dev/null
done
# What upstream's prepare script sets up: a DM from user 2 inviting user 1.
room=$(curl -fsS -X POST "$HS/_matrix/client/v3/createRoom" -H "Authorization: Bearer $t2" \
  -d "{\"name\":\"$USER2_NAME\",\"is_direct\":true,\"invite\":[\"@$USER1_NAME:localhost\"]}" | jq -r .room_id)
curl -fsS -X PUT "$HS/_matrix/client/v3/rooms/$room/send/m.room.message/it1" -H "Authorization: Bearer $t2" \
  -d '{"msgtype":"m.text","body":"joined room successfully"}' >/dev/null
echo "users $USER1_NAME, $USER2_NAME ready; DM $room"

if [[ ${IT_FEDERATION:-} == 1 ]]; then
  HS2=https://127.0.0.1:8449
  for _ in $(seq 60); do
    curl -fsS "$HS2/_matrix/client/versions" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS -X POST "$HS2/_matrix/client/v3/register" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$USER1_NAME\",\"password\":\"$USER1_PW\",\"auth\":{\"type\":\"m.login.dummy\"},\"inhibit_login\":true}" >/dev/null \
    || { cat "$WORK/tuwunel2.log"; echo "second homeserver registration failed" >&2; exit 1; }
  echo "second homeserver up at $HS2 (user $USER1_NAME)"
fi
