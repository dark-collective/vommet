#!/bin/sh
# Vommet web: runtime config from the environment (nginx image runs
# /docker-entrypoint.d/*.sh before starting). Without a variable the
# baked-in default stays.
#   VOMMET_DEFAULT_HOMESERVER     homeserver pre-filled on the login page
#   VOMMET_CROSS_ORIGIN_ISOLATION "off" drops the COOP/COEP headers (the wasm
#                                 renderer then runs single-threaded); for
#                                 setups that embed cross-origin pages that
#                                 don't send COEP/CORP themselves
set -eu
cfg=/usr/share/nginx/html/assets/assets/config/global_config.json
if [ -n "${VOMMET_DEFAULT_HOMESERVER:-}" ]; then
  case "$VOMMET_DEFAULT_HOMESERVER" in
    *[!A-Za-z0-9.:-]*) echo "VOMMET_DEFAULT_HOMESERVER: only a server name, e.g. example.org" >&2; exit 1 ;;
  esac
  printf '{\n    "default_homeserver": "%s"\n}\n' "$VOMMET_DEFAULT_HOMESERVER" > "$cfg"
  echo "vommet: default homeserver $VOMMET_DEFAULT_HOMESERVER"
fi
hdr=/etc/nginx/conf.d/vommet-headers.inc
case "${VOMMET_CROSS_ORIGIN_ISOLATION:-on}" in
  on) ;;
  off)
    grep -v '^add_header Cross-Origin-' "$hdr" > "$hdr.new" && cat "$hdr.new" > "$hdr" && rm -f "$hdr.new"
    echo "vommet: cross-origin isolation off (COOP/COEP headers dropped)" ;;
  *) echo "VOMMET_CROSS_ORIGIN_ISOLATION: on or off" >&2; exit 1 ;;
esac
