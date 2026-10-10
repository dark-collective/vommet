#!/usr/bin/env bash
# Fail if the code names a Commet host (*.commet.chat) in a file not listed for
# that host in .vommet/commet-hosts.allow. See that file.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
allow=.vommet/commet-hosts.allow
declare -A ok=()
while read -r file host _; do
  [[ -z ${file:-} || $file == \#* ]] && continue
  ok["$file $host"]=1
done <"$allow"

bad=0
declare -A seen=()
while IFS=: read -r file line host; do
  seen["$file $host"]=1
  if [[ -z ${ok["$file $host"]+x} ]]; then
    echo "::error file=$file,line=$line::$host is Commet's infrastructure. Point it at our own service, or list it in $allow with the reason it's harmless."
    bad=1
  fi
done < <(git grep -n -o -I -E '([A-Za-z0-9-]+\.)*commet\.chat' -- . ':!*.md' ':!.github' ':!.vommet' | LC_ALL=C sort -u)

for k in "${!ok[@]}"; do
  [[ -n ${seen[$k]+x} ]] || echo "note: stale allow entry (no longer in the code): $k"
done
if (( bad )); then exit 1; fi
echo "no unlisted references to Commet's hosts"
