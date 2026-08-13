#!/bin/zsh
set -euo pipefail

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer team identifier}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

signing_identity=${SIGNING_IDENTITY:-Developer ID Application}
archive_path=${ARCHIVE_PATH:-build/release/Margin.xcarchive}
output_directory=${OUTPUT_DIRECTORY:-build/release}
app_path="$archive_path/Products/Applications/Margin.app"
submission_zip="$output_directory/Margin-notarization.zip"
release_zip="$output_directory/Margin.zip"
notarization_log="$output_directory/notarization.log"

mkdir -p "$output_directory"

xcodebuild \
  -project Margin.xcodeproj \
  -scheme Margin \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  archive

codesign --verify --deep --strict --verbose=2 "$app_path"
cli_path="$app_path/Contents/SharedSupport/bin/margin"
quicklook_path="$app_path/Contents/PlugIns/MarginQuickLook.appex"
codesign --verify --strict --verbose=2 "$cli_path"
codesign --verify --strict --verbose=2 "$quicklook_path"

require_universal() {
  local binary=$1
  local architectures
  architectures=$(lipo -archs "$binary")
  if [[ " $architectures " != *" arm64 "* || " $architectures " != *" x86_64 "* ]]; then
    echo "Expected a universal binary at $binary, found: $architectures" >&2
    exit 1
  fi
}

require_universal "$app_path/Contents/MacOS/Margin"
require_universal "$cli_path"
require_universal "$quicklook_path/Contents/MacOS/MarginQuickLook"

if codesign -d --entitlements - "$app_path" 2>/dev/null | grep -q get-task-allow; then
  echo "Release app contains get-task-allow" >&2
  exit 1
fi
if codesign -d --entitlements - "$quicklook_path" 2>/dev/null | grep -q get-task-allow; then
  echo "Release Quick Look extension contains get-task-allow" >&2
  exit 1
fi

ditto -c -k --keepParent "$app_path" "$submission_zip"
xcrun notarytool submit "$submission_zip" --keychain-profile "$NOTARY_PROFILE" --wait \
  | tee "$notarization_log"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"

ditto -c -k --keepParent "$app_path" "$release_zip"
shasum -a 256 "$release_zip" > "$release_zip.sha256"
echo "$release_zip"
