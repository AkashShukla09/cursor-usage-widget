#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release

app="$root/CursorUsageWidget.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/CursorUsageWidget" "$app/Contents/MacOS/CursorUsageWidget"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CursorUsageWidget</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.CursorUsageWidget</string>
  <key>CFBundleName</key>
  <string>Cursor Usage</string>
  <key>CFBundleDisplayName</key>
  <string>Cursor Usage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.6</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "Built $app"
echo "Menu bar: open \"$app\""
echo "Snapshot: \"$app/Contents/MacOS/CursorUsageWidget\" --status"
