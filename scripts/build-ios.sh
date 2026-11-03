#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/iOSModuleCache"
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
sdk_major="${sdk_version%%.*}"
if (( sdk_major < 27 )); then
  printf 'iOS SDK %s: building Bluetooth companion; wireless screen viewing needs Xcode 27.2+ and iOS 27+.\n' "$sdk_version"
fi
python3 scripts/generate-ios-project.py
xcodebuild -project iOS/TheCursorConnect.xcodeproj -scheme TheCursorConnect \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
