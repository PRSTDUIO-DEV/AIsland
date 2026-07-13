#!/bin/bash
# Release build: universal binary + DMG. Usage: ./release.sh [version]
set -e
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP=AIsland.app
DIST=dist
BUILD=.build

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST" "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>local.aisland</string>
	<key>CFBundleName</key><string>AIsland</string>
	<key>CFBundleExecutable</key><string>AIsland</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
EOF

echo "building arm64…"
swiftc -O -target arm64-apple-macos14 main.swift providers.swift -o "$BUILD/AIsland-arm64"
echo "building x86_64…"
swiftc -O -target x86_64-apple-macos14 main.swift providers.swift -o "$BUILD/AIsland-x86_64"
lipo -create "$BUILD/AIsland-arm64" "$BUILD/AIsland-x86_64" -o "$APP/Contents/MacOS/AIsland"
lipo -info "$APP/Contents/MacOS/AIsland"

cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force -s - "$APP"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AIsland" -srcfolder "$STAGE" -ov -format UDZO "$DIST/AIsland-$VERSION.dmg" >/dev/null
(cd "$DIST" && shasum -a 256 "AIsland-$VERSION.dmg" | tee "AIsland-$VERSION.dmg.sha256")
echo "release $VERSION done → $DIST/AIsland-$VERSION.dmg"
