#!/usr/bin/env python3
"""Regenerate every app icon from the Vommet logo.

Source: assets/images/app_icon/source/vommet.svg, adapted from Twemoji 17.0.3
1f92e + 1f929, (c) Twitter, Inc. and other contributors, CC-BY 4.0
(https://github.com/jdecked/twemoji). vommet-mono.svg is the same geometry in
black and white, used for the single-colour Android icons.

Needs Python 3 + Pillow + rsvg-convert. No Flutter required. Easiest:

  docker run --rm -v "$PWD":/w -w /w/commet alpine:3.22 sh -c \
    'apk add -q python3 py3-pillow rsvg-convert && python3 scripts/generate_vommet_icons.py'

Run from the commet/ package directory.
"""
import io
import os
import subprocess
from PIL import Image, ImageDraw

SRC = "assets/images/app_icon/source/vommet.svg"
# Single-colour version (white = shape, black = hole) for Android's
# monochrome launcher, notification and background-service icons. Colour
# matching can't separate the gold stars from the yellow face.
SRC_MONO = "assets/images/app_icon/source/vommet-mono.svg"
BG = (0x2B, 0x1B, 0x6B, 255)  # deep indigo, also used for Android adaptive bg + splash
BG_HEX = "#2B1B6B"


def render(px, src=SRC):
    out = subprocess.run(
        ["rsvg-convert", "-w", str(px), "-h", str(px), src], check=True, capture_output=True
    ).stdout
    return Image.open(io.BytesIO(out)).convert("RGBA")


def emoji_on(size, scale, bg=None, radius=0.0):
    """Emoji centred at `scale` of a `size` square, optionally on a (rounded) bg."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if bg is not None:
        d = ImageDraw.Draw(canvas)
        if radius > 0:
            d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius), fill=bg)
        else:
            d.rectangle([0, 0, size - 1, size - 1], fill=bg)
    e = render(max(1, round(size * scale)))
    off = ((size - e.width) // 2, (size - e.height) // 2)
    canvas.alpha_composite(e, off)
    return canvas


def silhouette(size, scale):
    """White mask from SRC_MONO: white areas stay, black areas become holes."""
    m = render(max(1, round(size * scale)), SRC_MONO)
    lum = m.convert("L")
    alpha = Image.composite(lum, Image.new("L", m.size, 0), m.getchannel("A"))
    white = Image.new("RGBA", m.size, (255, 255, 255, 0))
    white.putalpha(alpha)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(white, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


def save(img, path, flatten=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if flatten:  # iOS/App Store icons must not have alpha
        base = Image.new("RGB", img.size, BG[:3])
        base.paste(img, mask=img.split()[3])
        img = base
    img.save(path, optimize=True)
    print("wrote", path, img.size)


def main():
    ai = "assets/images/app_icon"
    # Flutter-side assets (in-app logo, Windows toast icon, widget runner window).
    save(emoji_on(2646, 0.80), f"{ai}/app_icon_transparent.png")
    save(emoji_on(2646, 0.70, BG), f"{ai}/app_icon_filled.png")
    save(emoji_on(2646, 0.70, BG, radius=0.22), f"{ai}/app_icon_rounded.png")
    save(emoji_on(512, 1.0), f"{ai}/app_icon_transparent_cropped.png")
    with open(SRC) as f, open(f"{ai}/icon.svg", "w") as g:
        g.write(f.read())
    print("wrote", f"{ai}/icon.svg")
    save(emoji_on(64, 0.70, BG, radius=0.22), "../rust/rust/assets/app_icon_rounded.png")

    # Android: legacy launcher, adaptive foreground (108dp canvas, 66dp safe zone),
    # monochrome + notification + background-service masks.
    res = "android/app/src/main/res"
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in dens.items():
        save(emoji_on(round(48 * k), 0.70, BG, radius=0.22), f"{res}/mipmap-{name}/ic_launcher.png")
        save(emoji_on(round(108 * k), 0.55), f"{res}/drawable-{name}/ic_launcher_foreground.png")
        save(silhouette(round(108 * k), 0.55), f"{res}/drawable-{name}/ic_launcher_monochrome.png")
        save(silhouette(round(48 * k), 0.90), f"{res}/drawable-{name}/notification_icon.png")
    # Upstream ships this one oddly large and at odd paths; keep their sizes/paths.
    for path, px in [
        (f"{res}/drawable-mdpi/ic_bg_service_small.png", 498),
        (f"{res}/drawable-hdpi/drawable-hdpi/ic_bg_service_small.png", 747),
        (f"{res}/drawable-xhdpi/ic_bg_service_small.png", 996),
        (f"{res}/drawable-xxhdpi/ic_bg_service_small.png", 1494),
        (f"{res}/drawable-xxxhdpi/ic_bg_service_small.png", 1993),
    ]:
        save(silhouette(px, 0.90), path)

    # Linux: deb hicolor set + flatpak.
    for px in (16, 32, 64, 128, 256, 512):
        save(emoji_on(px, 0.80, BG, radius=0.22) if px >= 64 else emoji_on(px, 1.0),
             f"linux/debian/usr/share/icons/hicolor/{px}x{px}/apps/commet-desktop.png")
    save(emoji_on(512, 0.70, BG, radius=0.22), "linux/flatpak/icon.png")

    # Windows .ico (multi-resolution).
    big = emoji_on(256, 0.80, BG, radius=0.22)
    os.makedirs("windows/runner/resources", exist_ok=True)
    big.save("windows/runner/resources/app_icon.ico",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote windows/runner/resources/app_icon.ico")

    # Web (unshipped, kept consistent).
    for px in (16, 32, 96):
        save(emoji_on(px, 1.0), f"web/favicon-{px}x{px}.png")
    for px in (192, 512):
        save(emoji_on(px, 0.70, BG, radius=0.22), f"web/icons/Icon-{px}.png")
        save(emoji_on(px, 0.60, BG), f"web/icons/Icon-maskable-{px}.png")

    # iOS / macOS (unshipped, kept consistent).
    ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for f in sorted(os.listdir(ios)):
        if f.endswith(".png"):
            px = Image.open(f"{ios}/{f}").size[0]
            save(emoji_on(px, 0.70, BG), f"{ios}/{f}", flatten=True)
    mac = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(emoji_on(px, 0.70, BG, radius=0.22), f"{mac}/app_icon_{px}.png")

    print("background colour for Android/pubspec:", BG_HEX)


if __name__ == "__main__":
    main()
