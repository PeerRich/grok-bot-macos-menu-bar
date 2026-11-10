#!/bin/bash
# Builds "Grok Menu.app" into ./build. Pass --run to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/Grok Menu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GrokMenu "$APP/Contents/MacOS/GrokMenu"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Grok Menu</string>
    <key>CFBundleDisplayName</key><string>Grok Menu</string>
    <key>CFBundleIdentifier</key><string>dev.peer.grok-menu</string>
    <key>CFBundleExecutable</key><string>GrokMenu</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.4</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    # Wait for the old copy to exit, otherwise `open` just re-activates the dying process.
    pkill -x GrokMenu 2>/dev/null || true
    while pgrep -x GrokMenu >/dev/null; do sleep 0.1; done
    open -n "$APP"
fi
