#!/usr/bin/env bash
# Build the release file: an iPhone app with no signature at all, as a zip called Kitbag-<version>-unsigned.ipa, and its SHA-256.
#
#   tools/make_unsigned_ipa.sh        # writes build/release/
#
# Apple only runs signed apps, so this file does not run as it is: a sideloading tool (AltStore, Sideloadly) signs it with
# the Apple ID of whoever installs it. Nothing of the author's is in it. The guests must be in place first
# (tools/fetch_guests.sh and tools/sync_guests.sh) and `xcodegen generate` must have been run.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)"
out="build/release"
rm -rf "$out"
mkdir -p "$out/Payload"

# -file-prefix-map keeps the paths of this machine out of the binary.
xcodebuild -project Kitbag.xcodeproj -scheme Kitbag -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$out/Kitbag.xcarchive" -derivedDataPath build/DerivedRelease archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  OTHER_SWIFT_FLAGS="-file-prefix-map $PWD=. -file-prefix-map $HOME=~" \
  OTHER_CFLAGS="-ffile-prefix-map=$PWD=. -ffile-prefix-map=$HOME=~" >"$out/build.log" 2>&1 ||
  { echo "the build failed; see $out/build.log"; exit 1; }

cp -R "$out/Kitbag.xcarchive/Products/Applications/Kitbag.app" "$out/Payload/"
(cd "$out" && zip -qry "Kitbag-$version-unsigned.ipa" Payload &&
  shasum -a 256 "Kitbag-$version-unsigned.ipa" >"Kitbag-$version-unsigned.ipa.sha256")
rm -rf "$out/Payload"
echo "$out/Kitbag-$version-unsigned.ipa"
cat "$out/Kitbag-$version-unsigned.ipa.sha256"
