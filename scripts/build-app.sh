#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/Struktur.app"

cd "$PROJECT_DIR"
swift build -c release
mkdir -p "$PROJECT_DIR/dist"
STRUKTUR_STAGE=$(mktemp -d "$PROJECT_DIR/dist/.struktur-build.XXXXXX")
STAGED_APP="$STRUKTUR_STAGE/Struktur.app"
CONTENTS_DIR="$STAGED_APP/Contents"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/release/Struktur" "$CONTENTS_DIR/MacOS/Struktur"
cp "$PROJECT_DIR/Distribution/Info.plist" "$CONTENTS_DIR/Info.plist"
swift "$PROJECT_DIR/scripts/generate-icon.swift" "$PROJECT_DIR/.build/Struktur.iconset"
iconutil -c icns "$PROJECT_DIR/.build/Struktur.iconset" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Sources/Struktur/Resources/PrivacyInfo.xcprivacy" "$CONTENTS_DIR/Resources/"
if [[ -d "$PROJECT_DIR/.build/release/Struktur_Struktur.bundle" ]]; then
    cp -R "$PROJECT_DIR/.build/release/Struktur_Struktur.bundle" "$CONTENTS_DIR/Resources/"
fi
codesign --force --deep --sign - --entitlements "$PROJECT_DIR/Distribution/Struktur.entitlements" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if [[ -e "$APP_DIR" ]]; then
    PREVIOUS_APP="$PROJECT_DIR/dist/Struktur.previous-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$APP_DIR" "$PREVIOUS_APP"
    printf 'Previous local build preserved at %s\n' "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$APP_DIR"
rmdir "$STRUKTUR_STAGE"
printf '%s\n' "$APP_DIR"
