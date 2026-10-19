#!/bin/sh
# Vommet web: runtime config from the environment (nginx image runs
# /docker-entrypoint.d/*.sh before starting). Without the variable the
# baked-in default stays.
#   VOMMET_DEFAULT_HOMESERVER  homeserver pre-filled on the login page
set -eu
cfg=/usr/share/nginx/html/assets/assets/config/global_config.json
if [ -n "${VOMMET_DEFAULT_HOMESERVER:-}" ]; then
  case "$VOMMET_DEFAULT_HOMESERVER" in
    *[!A-Za-z0-9.:-]*) echo "VOMMET_DEFAULT_HOMESERVER: only a server name, e.g. example.org" >&2; exit 1 ;;
  esac
  printf '{\n    "default_homeserver": "%s"\n}\n' "$VOMMET_DEFAULT_HOMESERVER" > "$cfg"
  echo "vommet: default homeserver $VOMMET_DEFAULT_HOMESERVER"
fi
