#!/usr/bin/env bash
# Pick how a CI job on our own runners talks to Forgejo: over the tailnet when Forgejo answers
# there, else through the public server URL (Cloudflare) as before.
#
#   .vommet/ci/forgejo-tailnet.sh          writes server=, src=, api= to $GITHUB_OUTPUT
#   .vommet/ci/forgejo-tailnet.sh --git    also points this checkout's git at the chosen server
#
# Why (2026-11-05): Cloudflare cuts every request at 100 s, so the promote's ~1000-ref push
# returned 524 while Forgejo was still applying it (cut 05b), and API calls cost 0.1-0.4 s
# there against ~2 ms on the tailnet. The ci-sandbox firewall lets jobs reach only
# 100.64.0.13:3000 on the tailnet. Anything else (GitHub, another runner, the tailnet down)
# gets the public URL, so this step never fails a job.
#
# --git: actions/checkout keeps its token as http.<server>/.extraheader, which git matches
# against the URL it actually requests. After url.<tailnet>.insteadOf the requested URL is the
# tailnet one, so the header is copied to that key too; without it every push gets 401.
set -uo pipefail
PUB=${GITHUB_SERVER_URL:?}; PUB=${PUB%/}
REPO=${GITHUB_REPOSITORY:?}
T=${FORGEJO_TAILNET:-http://100.64.0.13:3000}; T=${T%/}
out=${GITHUB_OUTPUT:-/dev/null}

base=$PUB
if [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$T/api/v1/version" 2>/dev/null)" = 200 ]; then
  base=$T
fi

if [ "$base" = "$T" ] && [ "${1:-}" = --git ]; then
  h=$(git config --get "http.$PUB/.extraheader" 2>/dev/null || true)
  if [ -n "$h" ]; then
    git config --local "http.$T/.extraheader" "$h" &&
      git config --local "url.$T/.insteadOf" "$PUB/" || base=$PUB
  else
    echo "no checkout credential under http.$PUB/.extraheader; git stays on $PUB"
    base=$PUB
  fi
fi

{
  echo "server=$base"
  echo "src=$base/$REPO.git"
  echo "api=$base/api/v1/repos/$REPO"
} >> "$out"
if [ "$base" = "$T" ]; then echo "Forgejo over the tailnet: $T"; else echo "Forgejo through $PUB"; fi
exit 0
