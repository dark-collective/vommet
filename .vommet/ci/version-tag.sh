#!/usr/bin/env bash
# Prints the app's version label (VERSION_TAG).
#   version-tag.sh <ref name> <run number> [tags json file, for tests]
# Tester-release candidates (testing, sync/testing, ci/windows-testing) are
# labelled with the release they would be published as: the first one of the
# UTC day is testing-YYYY-MM-DD, later ones testing-YYYY-MM-DDb, c, ... (the
# next letter free among the published releases (not tags: every
# promote adds dozens of pre-sync/* tags, which push the release tags out of a
# 50-item page)), followed by the run number. The
# sync session publishes a release under exactly that name; a candidate that
# is never published leaves the name to the next one. Other branches, or no
# answer from the tag list, keep <ref>.<run>.
set -u
ref=$1 run=$2 src=${3:-}
fallback="$ref.$run"
case "$ref" in
  testing|sync/testing|ci/windows-testing) ;;
  *) echo "$fallback"; exit 0 ;;
esac
day=${VOMMET_DAY:-$(date -u +%Y-%m-%d)}
if [ -n "$src" ]; then json=$(cat "$src")
else json=$(curl -fsS --max-time 20 "https://nether.codes/api/v1/repos/nether/vommet/releases?limit=50") ||
  { echo "$fallback"; exit 0; }
fi
# Suffix letters already used today; the bare name counts as "a".
used=$(printf '%s' "$json" | grep -o "\"tag_name\":\"testing-$day[a-z]\{0,1\}\"" |
  sed "s/\"tag_name\":\"testing-$day\([a-z]\{0,1\}\)\"/\1/; s/^$/a/" | sort -u)
if [ -z "$used" ]; then suffix=""
else suffix=$(printf '%s\n' "$used" | tail -1 | tr 'a-y' 'b-z')
fi
echo "testing-$day$suffix ($run)"
