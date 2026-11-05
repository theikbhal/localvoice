#!/bin/bash
# Builds build/LocalVoice.app from the Swift package.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/LocalVoice.app"

echo "==> Compiling LocalVoice"
swift build -c release --package-path "$ROOT"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/LocalVoice" "$APP/Contents/MacOS/LocalVoice"
cp "$ROOT/Resources/kokoro_worker.py" "$APP/Contents/Resources/kokoro_worker.py"
cp "$ROOT/scripts/setup_engine.sh" "$APP/Contents/Resources/setup_engine.sh"
chmod +x "$APP/Contents/Resources/setup_engine.sh"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LocalVoice</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.theikbhal.localvoice</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LocalVoice</string>
    <key>CFBundleDisplayName</key>
    <string>LocalVoice</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed · Kokoro-82M is Apache-2.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so the app launches locally without Gatekeeper complaints.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Built $APP"
