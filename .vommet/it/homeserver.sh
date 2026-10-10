#!/usr/bin/env bash
# Start a throwaway Tuwunel homeserver at https://localhost for the
# integration tests, with a self-signed CA installed system-wide (Commet's login
# page only speaks https). Then create the test users and a DM, mirroring
# upstream's scripts/integration-prepare-homeserver.sh.
#
# Env: TUWUNEL (path to the binary), USER1_NAME/PW, USER2_NAME/PW.
# Leaves the server running; logs in $WORK/tuwunel.log.
set -euo pipefail
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

TUWUNEL_CONFIG="$WORK/tuwunel.toml" nohup "$TUWUNEL" >"$WORK/tuwunel.log" 2>&1 &
echo $! > "$WORK/tuwunel.pid"

HS=https://localhost
for _ in $(seq 60); do
  curl -fsS "$HS/_matrix/client/versions" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "$HS/_matrix/client/versions" >/dev/null || { cat "$WORK/tuwunel.log"; echo "homeserver did not come up" >&2; exit 1; }
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
