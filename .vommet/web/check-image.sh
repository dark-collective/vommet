#!/usr/bin/env bash
# Vommet web: runs an image and checks it with check-site.sh (gzip, runtime
# homeserver, content types, COOP/COEP, wasm bytes), then once more with
# VOMMET_CROSS_ORIGIN_ISOLATION=off, which must drop the two Cross-Origin headers.
#   check-image.sh <image> <local build/web dir>
set -uo pipefail
img=$1; dir=$2; here=$(dirname "$0")
up() { # name port env...
  local n=$1 p=$2; shift 2
  docker run -d --name "$n" -p "$p:8080" "$@" "$img" >/dev/null || return 1
  for i in $(seq 1 20); do curl -fsS -o /dev/null "http://127.0.0.1:$p/" && return 0; sleep 1; done
  docker logs "$n" 2>&1 | tail -n 20; return 1
}
fail=0
up vw 18080 -e VOMMET_DEFAULT_HOMESERVER=example.org || { echo "::error::image did not start"; exit 1; }
docker logs vw 2>&1 | tail -n 5
"$here/check-site.sh" http://127.0.0.1:18080 "$dir" example.org image || fail=1
docker rm -f vw >/dev/null
up vwoff 18081 -e VOMMET_CROSS_ORIGIN_ISOLATION=off || { echo "::error::image did not start with isolation off"; exit 1; }
if curl -fsS -o /dev/null -D - http://127.0.0.1:18081/ | grep -qi '^cross-origin-'; then
  echo "::error::VOMMET_CROSS_ORIGIN_ISOLATION=off still sends Cross-Origin headers"; fail=1
fi
curl -fsS -o /dev/null -D - http://127.0.0.1:18081/ | grep -qi '^x-content-type-options: nosniff' || { echo "::error::isolation off lost the other headers"; fail=1; }
docker rm -f vwoff >/dev/null
[ "$fail" = 0 ] && echo "image check ok: $img"
exit "$fail"
