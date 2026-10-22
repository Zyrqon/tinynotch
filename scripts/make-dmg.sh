#!/bin/zsh
# Собирает build/Notchly-<версия>.dmg для раздела Releases на GitHub:
# внутри Notchly.app и ярлык «Программы», чтобы установить перетаскиванием.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Notchly.app/Contents/Info.plist)"
DMG="build/Notchly-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Notchly.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Notchly $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
