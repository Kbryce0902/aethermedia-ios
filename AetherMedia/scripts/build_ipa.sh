#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null; then
  echo "A Mac with full Xcode is required. On Windows, use the included GitHub Actions workflow." >&2
  exit 1
fi
xcodebuild -version
python3 scripts/verify_package.py
mkdir -p build
xcodebuild -project AetherMedia.xcodeproj -scheme AetherMedia \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/AetherMedia.xcarchive -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY=' \
  archive
python3 scripts/package_ipa.py build/AetherMedia.xcarchive/Products/Applications/AetherMedia.app \
  --output build/AetherMedia-unsigned.ipa
