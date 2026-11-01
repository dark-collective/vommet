#!/usr/bin/env bash
# Vommet web: checks a served copy of the web build against the local files.
#   check-site.sh <base url> <local build/web dir> <expected default homeserver> [image]
# Every .wasm, .mjs and the entry points are fetched and must carry the right
# content type (application/wasm, JavaScript, text/html, JSON) and the COOP/COEP
# headers that let the wasm renderer use threads; every .wasm must be byte-for-byte
# the local file (so a wrong rewrite or an HTML fallback page can't pass). The SPA
# fallback must answer an unknown client route with index.html. With "image": also
# gzip from the pre-compressed copies. Prints one error per failure, exits 1 on any.
set -uo pipefail
base=${1%/}; dir=$2; hs=$3; mode=${4:-}
fail=0; err() { echo "::error title=web check ($base)::$*"; fail=1; }
hdrs() { curl -fsS -o /dev/null -D - "${@:2}" "$base/$1" | tr -d '\r'; }
hval() { awk -F': ' -v k="$1" 'tolower($1)==tolower(k){v=$2} END{print v}'; }
expect_type() { # path want
  local got; got=$(curl -fsS -o /dev/null -w '%{content_type}' "$base/$1") || { err "$1: request failed"; return; }
  case "$got" in *"$2"*) ;; *) err "$1 served as '$got', want $2" ;; esac
}
h=$(hdrs "") || { err "/ unreachable"; exit 1; }
[ "$(hval cross-origin-opener-policy <<<"$h")" = same-origin ] || err "/: no 'Cross-Origin-Opener-Policy: same-origin'"
[ "$(hval cross-origin-embedder-policy <<<"$h")" = credentialless ] || err "/: no 'Cross-Origin-Embedder-Policy: credentialless'"
[ "$(hval x-content-type-options <<<"$h")" = nosniff ] || err "/: no 'X-Content-Type-Options: nosniff'"
expect_type "" text/html
expect_type some/client/route text/html
expect_type main.dart.js javascript
expect_type manifest.json json
curl -fsS "$base/assets/assets/config/global_config.json" | grep -q "\"$hs\"" || err "global_config.json: default homeserver is not $hs"
n=0
while IFS= read -r f; do
  p=${f#"$dir"/}; n=$((n + 1))
  expect_type "$p" application/wasm
  [ "$(curl -fsS "$base/$p" | sha256sum | cut -d' ' -f1)" = "$(sha256sum < "$f" | cut -d' ' -f1)" ] || err "$p: served bytes differ from the build"
  # The worker-side headers matter too: skwasm loads these from a worker.
  [ "$(hdrs "$p" | hval cross-origin-embedder-policy)" = credentialless ] || err "$p: no COEP header"
done < <(find "$dir" -name '*.wasm' | sort)
[ "$n" -gt 0 ] || err "no .wasm files in $dir"
while IFS= read -r f; do expect_type "${f#"$dir"/}" javascript; done < <(find "$dir" -name '*.mjs' | sort)
if [ "$mode" = image ]; then
  for p in main.dart.js $( [ -f "$dir/main.dart.wasm" ] && echo main.dart.wasm ); do
    [ "$(hdrs "$p" -H 'Accept-Encoding: gzip' | hval content-encoding)" = gzip ] || err "$p not served gzipped"
  done
fi
[ "$fail" = 0 ] && echo "web check ok ($base): $n wasm file(s) byte-identical as application/wasm, COOP/COEP, SPA fallback, content types, homeserver $hs${mode:+, gzip}"
exit "$fail"
