#!/bin/zsh
# Builds, signs, notarises and publishes a release with a Sparkle appcast.
#   ./release.sh 0.2
# One-time setup (needs your Apple credentials, so not scripted):
#   1. Install a "Developer ID Application" certificate (Xcode > Settings > Accounts > Manage Certificates).
#   2. xcrun notarytool store-credentials rumkapsel --apple-id <apple id> --team-id <team id> --password <app-specific password>
set -e
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
RELEASES_REPO="MadsBuus/rumkapsel-releases"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')

sed -i '' "s|<key>CFBundleShortVersionString</key><string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$VERSION</string>|" build.sh
sed -i '' "s|<key>CFBundleVersion</key><string>[^<]*</string>|<key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>|" build.sh
./build.sh
APP=build/rumkapsel.app

if [ -n "$IDENTITY" ]; then
  echo "signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "no Developer ID certificate found: building unsigned"
fi

mkdir -p build/release
ZIP="build/release/rumkapsel-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile rumkapsel >/dev/null 2>&1; then
  echo "notarising"
  xcrun notarytool submit "$ZIP" --keychain-profile rumkapsel --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
else
  echo "notarisation skipped (no credentials stored under profile rumkapsel)"
fi

# Release notes: the commit subjects since the previous tag, or a notes file given as the second argument.
NOTES_FILE="build/release/notes-$VERSION.md"
if [ -n "$2" ] && [ -f "$2" ]; then
  cp "$2" "$NOTES_FILE"
else
  PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
  { echo "## What's new"; echo
    git log ${PREV:+$PREV..}HEAD --no-merges --format='- %s' | grep -v '^- Release ' | grep -v '^- $'
    echo; echo "Unzip and move to Applications. Updates arrive in-app."; } > "$NOTES_FILE"
fi
# Sparkle shows the same notes in its update window: generate_appcast picks up an .html beside the zip.
{ echo "<ul>"; git log ${PREV:+$PREV..}HEAD --no-merges --format='%s' | grep -v '^Release ' | sed 's/&/\&amp;/g; s/</\&lt;/g; s/^/<li>/; s/$/<\/li>/'; echo "</ul>"; } > "build/release/rumkapsel-$VERSION.html"
# Appcast for Sparkle, hosted in the public releases repo.
WORK=build/releases-repo
rm -rf "$WORK"
gh repo clone "$RELEASES_REPO" "$WORK" -- -q
cp "$ZIP" "$WORK/"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --download-url-prefix "https://github.com/$RELEASES_REPO/releases/download/v$VERSION/" -o "$WORK/appcast.xml" build/release
(cd "$WORK" && git add appcast.xml && git -c user.name="Mads Buus" -c user.email="mads.buus@tattoodo.com" commit -q -m "rumkapsel $VERSION" && git push -q)
gh release create "v$VERSION" "$ZIP" --repo "$RELEASES_REPO" --title "rumkapsel $VERSION" --notes-file "$NOTES_FILE" --latest

git add build.sh && git -c user.name="Mads Buus" -c user.email="mads.buus@tattoodo.com" commit -q -m "Release $VERSION" || true
git tag -f "v$VERSION" && git push -q origin main --tags
echo "released v$VERSION"
