#!/bin/zsh
# Builds rymdkapsel.app, zips it and publishes a GitHub release.
#   ./release.sh 0.2
set -e
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
sed -i '' "s|<key>CFBundleShortVersionString</key><string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$VERSION</string>|" build.sh
./build.sh
ZIP="build/rymdkapsel-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/rymdkapsel.app "$ZIP"
git add build.sh && git -c user.name="Mads Buus" -c user.email="mads.buus@tattoodo.com" commit -q -m "Release $VERSION" || true
git tag -f "v$VERSION" && git push -q origin main --tags
gh release create "v$VERSION" "$ZIP" --title "rymdkapsel $VERSION" --notes "Unzip, move to Applications. First launch: right-click → Open (unsigned build)." --latest
echo "released v$VERSION"
