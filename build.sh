#!/bin/bash
# Build AIsland.app — usage: ./build.sh [run]
set -e
cd "$(dirname "$0")"

APP=AIsland.app
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>local.aisland</string>
	<key>CFBundleName</key><string>AIsland</string>
	<key>CFBundleExecutable</key><string>AIsland</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.2</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
EOF

swiftc -O main.swift providers.swift -o "$APP/Contents/MacOS/AIsland"
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
