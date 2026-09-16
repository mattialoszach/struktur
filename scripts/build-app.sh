#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/Struktur.app"
STRUKTUR_CONFIGURATION="${STRUKTUR_BUILD_CONFIGURATION:-release}"
STRUKTUR_IDENTITY="${STRUKTUR_SIGN_IDENTITY:--}"
if [[ "$STRUKTUR_CONFIGURATION" != "debug" && "$STRUKTUR_CONFIGURATION" != "release" ]]; then
    print -u2 "STRUKTUR_BUILD_CONFIGURATION must be debug or release."
    exit 1
fi
if [[ "${STRUKTUR_QA:-0}" == "1" ]]; then
    APP_DIR="$PROJECT_DIR/dist/Struktur-QA.app"
fi

cd "$PROJECT_DIR"
STRUKTUR_BUILD_ARGS=(-c "$STRUKTUR_CONFIGURATION")
if [[ "${STRUKTUR_UNIVERSAL:-0}" == "1" ]]; then
    STRUKTUR_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${STRUKTUR_BUILD_ARGS[@]}"
STRUKTUR_BIN_DIR=$(swift build "${STRUKTUR_BUILD_ARGS[@]}" --show-bin-path)
mkdir -p "$PROJECT_DIR/dist"
STRUKTUR_STAGE=$(mktemp -d "$PROJECT_DIR/dist/.struktur-build.XXXXXX")
STAGED_APP="$STRUKTUR_STAGE/Struktur.app"
CONTENTS_DIR="$STAGED_APP/Contents"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$STRUKTUR_BIN_DIR/Struktur" "$CONTENTS_DIR/MacOS/Struktur"
cp "$PROJECT_DIR/Distribution/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ "${STRUKTUR_QA:-0}" == "1" ]]; then
    plutil -replace CFBundleIdentifier -string app.struktur.qa "$CONTENTS_DIR/Info.plist"
    plutil -replace CFBundleDisplayName -string "Struktur QA" "$CONTENTS_DIR/Info.plist"
    plutil -remove CFBundleURLTypes "$CONTENTS_DIR/Info.plist"
fi
swift "$PROJECT_DIR/scripts/generate-icon.swift" "$PROJECT_DIR/.build/Struktur.iconset"
iconutil -c icns "$PROJECT_DIR/.build/Struktur.iconset" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Sources/Struktur/Resources/PrivacyInfo.xcprivacy" "$CONTENTS_DIR/Resources/"
if [[ -d "$STRUKTUR_BIN_DIR/Struktur_Struktur.bundle" ]]; then
    cp -R "$STRUKTUR_BIN_DIR/Struktur_Struktur.bundle" "$CONTENTS_DIR/Resources/"
fi
if [[ -n "${STRUKTUR_PROVISIONING_PROFILE:-}" ]]; then
    [[ -f "$STRUKTUR_PROVISIONING_PROFILE" ]] || { print -u2 "Provisioning profile not found."; exit 1; }
    cp "$STRUKTUR_PROVISIONING_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"
fi
if [[ "$STRUKTUR_IDENTITY" == "-" ]]; then
    codesign --force --sign - --entitlements "$PROJECT_DIR/Distribution/Struktur.entitlements" "$STAGED_APP"
else
    codesign --force --options runtime --timestamp --sign "$STRUKTUR_IDENTITY" --entitlements "$PROJECT_DIR/Distribution/Struktur.entitlements" "$STAGED_APP"
fi
codesign --verify --deep --strict "$STAGED_APP"

if [[ -e "$APP_DIR" ]]; then
    PREVIOUS_APP="${APP_DIR%.app}.previous-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$APP_DIR" "$PREVIOUS_APP"
    printf 'Previous local build preserved at %s\n' "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$APP_DIR"
rmdir "$STRUKTUR_STAGE"
printf '%s\n' "$APP_DIR"
