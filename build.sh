#!/bin/zsh
# Builds rymdkapsel.app into ./build. Add "run" to launch it afterwards.
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E 'error|Compiling|Build' || true
BIN=.build/release/Rymdkapsel
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
APP=build/rymdkapsel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/rymdkapsel"
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/"
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
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/MadsBuus/rymdkapsel-releases/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>YQUtcIJONdnRjC7xjWWsGroOVAj+wmZlLxTOcXpYjlA=</string>
  <key>SUEnableInstallerLauncherService</key><true/>
</dict></plist>
PLIST
echo "built $APP"
[ "$1" = "run" ] && open -g "$APP"
exit 0
