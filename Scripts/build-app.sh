#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "=== Building VoiceCloneMemo ==="

# 1. Build release binary
swift build -c release 2>&1

BINARY=".build/release/VoiceCloneMemo"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# 2. Create .app bundle
APP_DIR=".build/release/VoiceCloneMemo.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/VoiceCloneMemo"

# Copy icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VoiceCloneMemo</string>
    <key>CFBundleDisplayName</key>
    <string>Voice Clone Memo</string>
    <key>CFBundleIdentifier</key>
    <string>com.pixeldrop.voiceclonememo</string>
    <key>CFBundleVersion</key>
    <string>6.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>6.0.0</string>
    <key>CFBundleExecutable</key>
    <string>VoiceCloneMemo</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice Clone Memo a besoin du micro pour enregistrer ta voix et la cloner.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

echo "=== App bundle created: $APP_DIR ==="

# 3. Zip for distribution
ZIP_PATH=".build/release/VoiceCloneMemo.zip"
rm -f "$ZIP_PATH"
cd .build/release
ditto -c -k --keepParent VoiceCloneMemo.app VoiceCloneMemo.zip
cd ../..

echo "=== ZIP created: .build/release/VoiceCloneMemo.zip ==="
echo "=== Done! ==="
