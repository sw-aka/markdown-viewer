#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
channel="${1:?usage: build-release.sh development|stable build-number}"
number="${2:?build number required}"
shift 2
repository="${GITHUB_REPOSITORY:-sw-aka/markdown-viewer}"
series="$(tr -d '\n' < RELEASE_SERIES)"
python3 scripts/release-metadata.py --series "$series" --number "$number" --channel "$channel" --repository "$repository" --output build/release
version="$(python3 -c 'import json; print(json.load(open("build/release/release.json"))["version"])')"
archive="$(python3 -c 'import json; print(json.load(open("build/release/release.json"))["archive"])')"
scripts/bootstrap-sparkle.sh
xcodebuild -project MarkdownViewer.xcodeproj -scheme MarkdownViewer \
  -configuration Release -derivedDataPath build/ReleaseData \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$version" \
  UPDATE_REPOSITORY="$repository" UPDATE_CHANNEL="$channel" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build "$@"
app='build/ReleaseData/Build/Products/Release/Markdown Viewer.app'
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
actual_short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ "$actual_version" != "$version" || "$actual_short" != "$version" ]]; then
  echo 'Built application version does not match the release metadata.' >&2
  exit 1
fi
# Framework helpers must retain their own entitlements; Xcode signs embedded
# code in dependency order. Verify the completed app before archiving it.
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "build/release/$archive"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | build/dependencies/Sparkle-2.10.0/bin/sign_update --ed-key-file - -p "build/release/$archive" > build/release/signature.txt
  python3 scripts/release-metadata.py --series "$series" --number "$number" --channel "$channel" --repository "$repository" \
    --signature-file build/release/signature.txt --archive "build/release/$archive" --output build/release
  # Verify against the PUBLIC key embedded in the built application. A wrong
  # GitHub secret must fail this workflow rather than publish a broken update.
  public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")"
  signature="$(cat build/release/signature.txt)"
  swift scripts/verify-update.swift "$public_key" "$signature" "build/release/$archive"
else
  echo 'No SPARKLE_PRIVATE_KEY supplied: local build only, no publishable update feed.'
fi
