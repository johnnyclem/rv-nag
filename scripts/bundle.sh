#!/bin/bash
# Builds ReviewNagger.app. Running from an app bundle is required for system notifications
# and "Launch at Login" (a bare `swift run` binary has no bundle identifier).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ReviewNagger"
APP="build/ReviewNagger.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ReviewNagger"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.johnnyclem.ReviewNagger</string>
    <key>CFBundleName</key><string>ReviewNagger</string>
    <key>CFBundleExecutable</key><string>ReviewNagger</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so notifications / login items work locally.
codesign --force --sign - "$APP"
echo "Built $APP"
