#!/bin/zsh
# Builds rumkapsel.app into ./build. Add "run" to launch it afterwards.
#   ./build.sh          the release build: optimised, universal (Apple silicon and Intel), a couple of minutes
#   ./build.sh fast     a local build to try things: debug, this machine's architecture only, a few seconds
set -e
cd "$(dirname "$0")"
MODE=release
for a in "$@"; do [ "$a" = fast ] && MODE=fast; done
if [ "$MODE" = fast ]; then
  BIN=.build/debug/Rumkapsel
  FLAGS=()
else
  BIN=.build/out/Products/Release/Rumkapsel
  FLAGS=(-c release --arch arm64 --arch x86_64)
fi
# A stale binary from the last build must not pass as this one, so it goes before the compiler runs.
rm -f "$BIN"
swift build --build-system native "${FLAGS[@]}" 2>&1 | grep -E 'error|Build complete' || true
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
APP=build/rumkapsel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/rumkapsel"
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[ -f Resources/WhatsNew.md ] && cp Resources/WhatsNew.md "$APP/Contents/Resources/"
# Kenney's models for the Space Center theme (CC0).
[ -d Resources/Kenney ] && cp -R Resources/Kenney "$APP/Contents/Resources/"
[ -d Resources/Planets ] && cp -R Resources/Planets "$APP/Contents/Resources/"
[ -d Resources/Plating ] && cp -R Resources/Plating "$APP/Contents/Resources/"
[ -d Resources/Walls ] && cp -R Resources/Walls "$APP/Contents/Resources/"
[ -d Resources/Detail ] && cp -R Resources/Detail "$APP/Contents/Resources/"
[ -d Resources/Suits ] && cp -R Resources/Suits "$APP/Contents/Resources/"
# The commit this build came from, so the running app can say which one it is.
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo dev)
[ -n "$(git status --porcelain 2>/dev/null)" ] && SHA="$SHA+"
[ "$MODE" = fast ] && SHA="$SHA fast"
SUBJ=$(git log -1 --pretty=%s 2>/dev/null | cut -c1-70 | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>rumkapsel</string>
  <key>CFBundleDisplayName</key><string>rumkapsel</string>
  <key>CFBundleIdentifier</key><string>dev.madsbuus.rumkapsel</string>
  <key>CFBundleExecutable</key><string>rumkapsel</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.61</string>
  <key>CFBundleVersion</key><string>202610090827</string>
  <key>RKBuild</key><string>$SHA · $SUBJ</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/MadsBuus/rumkapsel-releases/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>YQUtcIJONdnRjC7xjWWsGroOVAj+wmZlLxTOcXpYjlA=</string>
  <key>SUEnableInstallerLauncherService</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>rumkapsel finds other rumkapsel stations on your local network so you can see each other's work.</string>
  <key>NSBonjourServices</key><array><string>_rumkapsel._tcp</string></array>
</dict></plist>
PLIST
# Signed with the same certificate every time, so macOS knows each build as the same app and the Local
# Network allowance holds. Without a certificate, every build is a stranger that starts out blocked.
SIGNER=$(security find-identity -v -p codesigning | grep -E '"(Developer ID Application|Apple Development):' | head -1 | sed 's/.*"\(.*\)"/\1/')
codesign --force --deep --timestamp=none --sign "${SIGNER:--}" "$APP" 2>/dev/null || echo "signing failed: macOS may keep this build off the local network"
echo "built $APP"
# Asked for by hand, so it comes to the front: a build you waited for is one you want to look at. Any
# rumkapsel already running goes first, whichever checkout it came from: `open` would only bring that one
# forward.
for a in "$@"; do
  [ "$a" = run ] || continue
  if pgrep -xq rumkapsel; then
    osascript -e 'quit app "rumkapsel"' >/dev/null 2>&1
    for _ in {1..20}; do pgrep -xq rumkapsel || break; sleep 0.25; done
    pkill -x rumkapsel 2>/dev/null || true   # already gone is fine: `set -e` would stop here
    for _ in {1..20}; do pgrep -xq rumkapsel || break; sleep 0.25; done
    sleep 0.5   # Launch Services forgets the old one a beat after it is gone
  fi
  # A fresh instance of this bundle, not whichever copy Launch Services last knew as rumkapsel.
  open -n "$APP"
done
exit 0
