#!/usr/bin/env bash
# Check out the guest apps next to this folder, at the release tags that tools/guests.txt pins (see docs/guests.md).
#
#   tools/fetch_guests.sh
#
# A guest whose folder already exists is left as it is: only the pinned tag is fetched if it is missing, so a checkout you
# develop in is never touched. The repositories are the public ones in https://github.com/kosuke-apps (set KITBAG_GUEST_BASE
# to take them from somewhere else, for example a local folder). The guests' own data (Headway's map, timetable and
# punctuality files) is not in their repositories: build it with the guest's own tools afterwards, see its README.
set -euo pipefail
cd "$(dirname "$0")/.."

base="${KITBAG_GUEST_BASE:-https://github.com/kosuke-apps}"
while read -r name repo tag _; do
  case "${name:-}" in "" | \#*) continue ;; esac
  if [ -d "$repo/.git" ]; then
    if ! git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      git -C "$repo" fetch --quiet --depth 1 origin "refs/tags/$tag:refs/tags/$tag"
    fi
    echo "$name: $repo already exists, tag $tag is there"
  else
    if [ -e "$repo" ]; then
      echo "error: $repo exists and is not a git checkout"
      exit 1
    fi
    git clone --quiet --depth 1 --branch "$tag" "$base/$name" "$repo"
    echo "$name: cloned $tag into $repo"
  fi
done < tools/guests.txt
