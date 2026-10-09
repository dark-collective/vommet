#!/usr/bin/env bash
# Wrap a Flatpak-flavoured Linux bundle (BUILD_DETAIL=flatpak, from the
# flatpak-bundle workflow) into a single-file .flatpak.
#
#   build_flatpak.sh <vommet-linux-flatpak-bundle.tar.gz> <out.flatpak> [version]
#
# Needs: flatpak, flatpak-builder, elfutils (eu-strip), the flathub remote
# with org.gnome.Platform//51 + org.gnome.Sdk//51 installed, and a working
# bubblewrap sandbox. Inside containers without FUSE this passes
# --disable-rofiles-fuse. Module builds (mpv, ffmpeg, libplacebo, keybinder…)
# are cached in $FLATPAK_STATE_DIR between runs.
#
# Unprivileged incus/LXC containers without security.nesting can't mount a
# fresh /proc inside the nested user namespace Flatpak always requests
# ("bwrap: Can't mount proc on /proc"). There, as root, set
#   FLATPAK_BWRAP=$(dirname "$0")/bwrap_nouserns.py
# which drops the user-namespace flags so the build sandbox runs as the
# container's root. Enabling security.nesting on the container is the cleaner
# fix and makes the wrapper unnecessary.
#
# The bundle references Flathub as its runtime repo, so
#   flatpak install --user ./vommet.flatpak
# fetches the GNOME runtime automatically.
set -euo pipefail

bundle_tar=$(realpath "$1")
out=$(realpath -m "$2")
version=${3:-0.5.0}
state_dir=${FLATPAK_STATE_DIR:-/var/cache/vommet-flatpak-state}

src=$(cd "$(dirname "$0")/../linux/flatpak" && pwd)
# flatpak-builder needs its build dir on the same filesystem as the state dir,
# and a fixed path keeps its module cache usable between runs.
mkdir -p "$state_dir"
work="${state_dir%/}-work"
rm -rf "$work"
mkdir -p "$work"

cp -r "$src"/. "$work"/
mkdir -p "$work/vommet"
tar -xzf "$bundle_tar" -C "$work/vommet"
[ -x "$work/vommet/bundle/vommet" ] || { echo "bundle has no 'vommet' executable (old 'commet' build?)" >&2; exit 1; }

sed -i "s/{{VERSION_TAG}}/$version/g" "$work/im.nether.chat.desktop" "$work/im.nether.chat.metainfo.xml"

mkdir -p "$state_dir"
cd "$work"
flatpak-builder --force-clean --disable-rofiles-fuse --state-dir="$state_dir" \
  build-dir im.nether.chat.yaml --repo=repo
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  repo "$out" im.nether.chat
ls -la "$out"
