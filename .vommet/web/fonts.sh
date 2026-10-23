#!/usr/bin/env bash
# Vommet: bundles the web engine's fallback fonts (Roboto, Noto Color Emoji,
# Noto Sans CJK and the other Noto scripts) into commet/web/fonts/fallback/ so
# the app never fetches fonts.gstatic.com at runtime. web/flutter_bootstrap.js
# points the engine's fontFallbackBaseUrl there. The list comes from the
# Flutter SDK in use (its web engine sources), so it follows Flutter upgrades.
# Run from the repo root, after Flutter is set up, before `flutter build web`.
# ~725 files, ~22 MB; the engine loads only what a page's text needs.
# Licences: Noto fonts SIL OFL 1.1, Roboto Apache 2.0 (see LICENSES.txt there).
set -euo pipefail
flutter_root=$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")
engine="$flutter_root/bin/cache/flutter_web_sdk/lib/_engine/engine"
data="$engine/font_fallback_data.dart"
[ -f "$data" ] || { echo "font_fallback_data.dart not found under $engine (run 'flutter precache --web')" >&2; exit 1; }

list=$( {
  grep -oE "'[a-z0-9]+/v[0-9]+/[^']+\.(woff2|ttf|otf)'" "$data"
  # Roboto, the default font, loaded unless the app bundles a "Roboto" family.
  grep -rhoE "roboto/v[0-9]+/[A-Za-z0-9_-]+\.(woff2|ttf)" "$engine"
} | tr -d "'" | sort -u)
n=$(wc -l <<<"$list")
[ "$n" -gt 100 ] || { echo "only $n fallback fonts found; engine layout changed?" >&2; exit 1; }

out=commet/web/fonts/fallback
rm -rf "$out"; mkdir -p "$out"
echo "== $n fallback fonts -> $out"
cd "$out"
xargs -P 16 -I{} sh -c 'mkdir -p "$(dirname "{}")" && curl -sSfL --retry 3 -o "{}" "https://fonts.gstatic.com/s/{}"' <<<"$list"
got=$(find . -type f | wc -l)
[ "$got" -eq "$n" ] || { echo "downloaded $got of $n fonts" >&2; exit 1; }
cat > LICENSES.txt <<'TXT'
Fallback fonts for the Vommet web app, downloaded at build time from Google
Fonts so browsers load them from this site instead.
Noto fonts (noto*/): SIL Open Font License 1.1, https://openfontlicense.org
Roboto (roboto/): Apache License 2.0, https://www.apache.org/licenses/LICENSE-2.0
TXT
du -sh .
