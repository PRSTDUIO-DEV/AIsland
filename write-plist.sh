#!/bin/bash
# write-plist.sh <output-path> <version> — single source of truth for Info.plist
cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>local.aisland</string>
	<key>CFBundleName</key><string>AIsland</string>
	<key>CFBundleExecutable</key><string>AIsland</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$2</string>
	<key>CFBundleVersion</key><string>$2</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
	<key>NSHumanReadableCopyright</key><string>© 2026 PRSTDUIO-DEV — MIT License</string>
</dict>
</plist>
EOF
