#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/iOSModuleCache"
python3 scripts/generate-ios-project.py
xcodebuild -project iOS/TheCursorConnect.xcodeproj -scheme TheCursorConnect \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
