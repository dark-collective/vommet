#!/usr/bin/env bash
# Vommet: builds the two browser-only pieces the web app needs and copies them
# into commet/ (run from the repo root, before `flutter build web`):
#   - vodozemac (Olm/Megolm) compiled to wasm, at the version pubspec resolves
#   - LiveKit's E2EE web worker, from OUR livekit_client fork at the commit
#     pubspec pins (upstream's scripts/prepare-web.sh builds Commet's fork).
# Replaces scripts/prepare-web.sh, which also installs an unpinned codegen.
set -euo pipefail
root=$(pwd)
work=${RUNNER_TEMP:-$(mktemp -d)}/vommet-web-prep
rm -rf "$work"; mkdir -p "$work"

VODOZEMAC_REF=${VODOZEMAC_REF:-0.5.0}
FRB_CODEGEN=${FRB_CODEGEN:-2.11.1}

# Our livekit_client fork and pin, read from pubspec so they can't drift.
lk_url=$(awk '/^  livekit_client:$/{f=1} f&&/url:/{print $2; exit}' commet/pubspec.yaml)
lk_ref=$(awk '/^  livekit_client:$/{f=1} f&&/ref:/{print $2; exit}' commet/pubspec.yaml)
[ -n "$lk_url" ] && [ -n "$lk_ref" ] || { echo "livekit_client override not found in pubspec" >&2; exit 1; }

echo "== vodozemac $VODOZEMAC_REF -> wasm"
command -v flutter_rust_bridge_codegen >/dev/null \
  || cargo install --locked "flutter_rust_bridge_codegen@$FRB_CODEGEN"
git clone -q --depth 1 --branch "$VODOZEMAC_REF" https://github.com/famedly/dart-vodozemac.git "$work/vodozemac"
(cd "$work/vodozemac" && flutter_rust_bridge_codegen build-web --dart-root dart --rust-root "$(readlink -f rust)" --release)
rm -f commet/assets/vodozemac/vodozemac_bindings_dart*
cp "$work"/vodozemac/dart/web/pkg/vodozemac_bindings_dart* commet/assets/vodozemac/
# Vommet stopgap (2026-11-03): the glue never releases vodozemac objects. On the
# web, Dart's garbage collector released objects Rust had already freed (every
# type: keys, signatures, sessions), so later calls ran on reused memory: "memory
# access out of bounds" freezes after a reload, "signature was invalid" decrypt
# failures, tab crashes. With releases off: no failures in 144 test page loads.
# Cost: a small leak, and secret keys stay in the tab's memory until it closes.
# Remove once the root cause is fixed (Vommet issue 1088).
glue=commet/assets/vodozemac/vodozemac_bindings_dart.js
sed -i -E 's#^(\s*)(wasm\.rust_arc_decrement_strong_count_)#\1// Vommet: never released (see .vommet/web/prepare.sh): \2#' "$glue"
released=$(grep "wasm\.rust_arc_decrement_strong_count_" "$glue" | grep -vc "Vommet: never released" || true)
patched=$(grep -c "Vommet: never released" "$glue" || true)
[ "$released" = 0 ] && [ "$patched" -gt 0 ] \
  || { echo "vodozemac glue: release patch did not apply ($patched patched, $released left)" >&2; exit 1; }
echo "vodozemac glue: $patched release calls disabled"

echo "== livekit e2ee worker from $lk_url @ $lk_ref"
git init -q "$work/livekit"
git -C "$work/livekit" fetch -q --depth 1 "$lk_url" "$lk_ref"
git -C "$work/livekit" checkout -q FETCH_HEAD
(cd "$work/livekit" && flutter pub get >/dev/null && dart compile js web/e2ee.worker.dart -o "$root/commet/web/e2ee.worker.dart.js" -m)

rm -rf "$work"
ls -la commet/assets/vodozemac commet/web/e2ee.worker.dart.js
