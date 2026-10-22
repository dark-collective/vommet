#!/usr/bin/env python3
# Vommet: trims the web build's FontManifest.json after `flutter build web`.
# Flutter web downloads EVERY font in the manifest before the first frame, so
# anything listed there is first-load weight. Web only (desktop and Android
# bundles are untouched): a package's font family that the app also declares
# under the same name is never used. Package code names fonts without
# `package:` (tiamat's theme says "EmojiFont", "RobotoCustom"), which resolves
# to the APP's family, so "packages/<pkg>/<Name>" is dead weight. That drops
# tiamat's 24 MB NotoColorEmoji.ttf (the app draws emoji with its own
# EmojiFont, Twemoji; what Twemoji lacks comes from the engine's Noto fallback
# fonts, in small pieces, on demand) and its second Roboto copy; the files go
# too. The engine's own "Roboto" (Flutter 3.47 bundles
# fonts/fallback/Roboto-Regular.ttf with --no-web-resources-cdn) stays:
# pointing it at RobotoCustom's file (two families, one URL) froze the
# WebAssembly build at startup in a 2026-10-19 trial.
#   trim-fonts.py <build/web dir>
import json, os, sys

web = sys.argv[1]
path = os.path.join(web, "assets", "FontManifest.json")
manifest = json.load(open(path))
names = {f["family"] for f in manifest}
kept, dropped = [], []
for fam in manifest:
    parts = fam["family"].split("/")
    if len(parts) == 3 and parts[0] == "packages" and parts[2] in names:
        dropped.append(fam)
    else:
        kept.append(fam)

used = {a["asset"] for f in kept for a in f["fonts"]}
freed = 0
for fam in dropped:
    for a in fam["fonts"]:
        file = os.path.join(web, "assets", a["asset"])
        if a["asset"] not in used and os.path.exists(file):
            freed += os.path.getsize(file)
            os.remove(file)
    print(f"dropped {fam['family']}: {', '.join(a['asset'] for a in fam['fonts'])}")

json.dump(kept, open(path, "w"), separators=(",", ":"))
print(f"freed {freed / 1e6:.2f} MB; first-load fonts now:")
sizes = {}
for fam in kept:
    for a in fam["fonts"]:
        size = sizes[a["asset"]] = os.path.getsize(os.path.join(web, "assets", a["asset"]))
        print(f"  {fam['family']:24} {size / 1e6:6.2f} MB  {a['asset']}")
print(f"  total {sum(sizes.values()) / 1e6:.2f} MB in {len(sizes)} files")

# A service worker that still lists a removed file would 404 on install.
sw = os.path.join(web, "flutter_service_worker.js")
if os.path.exists(sw):
    text = open(sw).read()
    gone = [a["asset"] for f in dropped for a in f["fonts"] if a["asset"] not in used and a["asset"] in text]
    if gone:
        sys.exit(f"flutter_service_worker.js still lists removed fonts: {gone}")
# Guard: no single eagerly loaded font this big again.
big = [a["asset"] for f in kept for a in f["fonts"]
       if os.path.getsize(os.path.join(web, "assets", a["asset"])) > 5_000_000]
if big:
    sys.exit(f"fonts over 5 MB still load up front on web: {big}")
