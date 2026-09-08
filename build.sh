#!/bin/zsh
# Builds rymdkapsel.app into ./build. Add "run" to launch it afterwards.
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E 'error|Compiling|Build' || true
BIN=.build/release/Rymdkapsel
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
APP=build/rymdkapsel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/rymdkapsel"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>rymdkapsel</string>
  <key>CFBundleDisplayName</key><string>rymdkapsel</string>
  <key>CFBundleIdentifier</key><string>dev.madsbuus.rymdkapsel</string>
  <key>CFBundleExecutable</key><string>rymdkapsel</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "built $APP"
[ "$1" = "run" ] && open "$APP"
exit 0
