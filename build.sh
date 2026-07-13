#!/bin/bash
# Build AIsland.app — usage: ./build.sh [run]
set -e
cd "$(dirname "$0")"

APP=AIsland.app
VERSION="${VERSION:-dev}"
mkdir -p "$APP/Contents/MacOS"

./write-plist.sh "$APP/Contents/Info.plist" "$VERSION"

swiftc -O -wmo main.swift providers.swift -o "$APP/Contents/MacOS/AIsland"
if [ -f AppIcon.icns ]; then
  mkdir -p "$APP/Contents/Resources"
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force -s - "$APP"
echo "built $APP"

if [ "$1" = "run" ]; then
  pkill -x AIsland 2>/dev/null || true
  pkill -x Island 2>/dev/null || true
  open "$APP"
fi
