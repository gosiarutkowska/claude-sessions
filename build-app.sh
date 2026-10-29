#!/bin/bash
# Builds "Sesje Claude.app" and installs it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# one binary for both Apple silicon and Intel Macs
swift build -c release --arch arm64 --arch x86_64
APP="build/Sesje Claude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeSessions" "$APP/Contents/MacOS/ClaudeSessions"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sesje Claude</string>
  <key>CFBundleDisplayName</key><string>Sesje Claude</string>
  <key>CFBundleIdentifier</key><string>com.gosiarutkowska.claude-sessions</string>
  <key>CFBundleExecutable</key><string>ClaudeSessions</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Otwiera sesje Claude Code w terminalu (iTerm, Terminal) i przełącza na już otwarte okna. / Opens Claude Code sessions in your terminal and switches to open ones.</string>
</dict></plist>
EOF
codesign --force --sign - "$APP"
rm -rf "/Applications/Sesje Claude.app"
ditto "$APP" "/Applications/Sesje Claude.app"
echo "installed: /Applications/Sesje Claude.app"
