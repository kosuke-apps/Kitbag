#!/usr/bin/env bash
# Copy a pinned snapshot of every guest app into Guests/ (see tools/guests.txt and docs/guests.md).
#
#   tools/sync_guests.sh
#
# The snapshot is `git archive <tag>` of the guest's repository, so it holds exactly the released files, never the
# guest's work in progress, and nothing is written to the guest's repository. Files the guest does not commit (its
# downloaded data) are copied from its working tree. The icon of each guest goes to Guests/GuestIcons/<name>.png.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Guests/GuestIcons
count=0
while read -r name repo tag icon extras; do
  case "${name:-}" in "" | \#*) continue ;; esac

  source_repo="$(cd "$repo" 2>/dev/null && pwd)" || { echo "error: $name: no repository at $repo"; exit 1; }
  git -C "$source_repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
    { echo "error: $name: tag $tag does not exist in $source_repo"; exit 1; }

  staging="$(mktemp -d)"
  git -C "$source_repo" archive --format=tar "$tag" | tar -x -C "$staging"
  for file in $extras; do
    [ -f "$source_repo/$file" ] ||
      { echo "error: $name: $file is missing in $source_repo (build it with the guest's own tools, see its README)"; rm -rf "$staging"; exit 1; }
    mkdir -p "$staging/$(dirname "$file")"
    cp "$source_repo/$file" "$staging/$file"
  done
  [ -f "$staging/$icon" ] || { echo "error: $name: icon $icon is not in the snapshot"; rm -rf "$staging"; exit 1; }
  echo "$tag $(git -C "$source_repo" rev-parse --short "$tag^{commit}")" > "$staging/.kitbag-snapshot"

  # Kitbag does not carry a guest's asset catalog (it would bring a second AppIcon). An accent colour is mirrored in the
  # adapter by hand; anything else in the catalog is worth a look.
  catalog="$staging/App/Resources/Assets.xcassets"
  if [ -d "$catalog" ]; then
    [ -d "$catalog/AccentColor.colorset" ] && echo "note: $name has an AccentColor; its adapter sets the same tint (docs/guests.md)"
    if [ -n "$(ls "$catalog" | grep -v -e '^AppIcon.appiconset$' -e '^AccentColor.colorset$' -e '^Contents.json$' || true)" ]; then
      echo "warning: $name has assets besides its app icon and accent colour; Kitbag skips its Assets.xcassets (docs/guests.md)"
    fi
  fi

  rm -rf "Guests/$name"
  mv "$staging" "Guests/$name"
  cp "Guests/$name/$icon" "Guests/GuestIcons/$name.png"
  echo "$name $tag -> Guests/$name"
  count=$((count + 1))
done < tools/guests.txt
python3 tools/merge_guest_strings.py
python3 tools/guest_versions.py
echo "synced $count guest(s)"
