#!/bin/zsh
# Собирает Notchly.app в ./build. Нужны только Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Notchly.app
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Notchly" "$APP/Contents/MacOS/Notchly"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp MediaAdapter/run.pl "$APP/Contents/Resources/run.pl"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj "$APP/Contents/Resources/"

clang -fobjc-arc -dynamiclib -O2 -arch arm64 -arch arm64e -arch x86_64 \
    -mmacosx-version-min=14.0 -framework Foundation \
    MediaAdapter/MediaAdapter.m -o "$APP/Contents/Resources/libIslandMedia.dylib"

# Постоянный сертификат (scripts/setup-signing.sh) сохраняет выданные доступы между сборками.
# Без него — ad-hoc подпись, и macOS заново спрашивает доступы после каждой сборки.
SIGN="-"
IDENTITIES="$(security find-identity -v -p codesigning)"
if echo "$IDENTITIES" | grep -q "Notchly Dev"; then
    SIGN="Notchly Dev"
elif echo "$IDENTITIES" | grep -q "DynamicIsland Dev"; then
    SIGN="DynamicIsland Dev"   # сертификат, созданный до переименования проекта
else
    echo "Подсказка: запустите scripts/setup-signing.sh, чтобы доступы не сбрасывались после сборки."
fi
codesign --force --sign "$SIGN" "$APP/Contents/Resources/libIslandMedia.dylib"
codesign --force --sign "$SIGN" "$APP"
echo "Готово: $APP"
