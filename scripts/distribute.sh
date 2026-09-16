#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
cd "$PROJECT_DIR"

STRUKTUR_ROUTE="${1:-}"
if [[ "$STRUKTUR_ROUTE" != "developer-id" && "$STRUKTUR_ROUTE" != "app-store" ]]; then
    print -u2 "Usage: scripts/distribute.sh developer-id|app-store"
    exit 1
fi
[[ -n "${STRUKTUR_SIGN_IDENTITY:-}" && "$STRUKTUR_SIGN_IDENTITY" != "-" ]] || {
    print -u2 "Set STRUKTUR_SIGN_IDENTITY to the appropriate Apple signing identity. No upload performed."
    exit 2
}
if [[ "$STRUKTUR_ROUTE" == "developer-id" ]]; then
    [[ -n "${STRUKTUR_NOTARY_PROFILE:-}" ]] || {
        print -u2 "Set STRUKTUR_NOTARY_PROFILE to an existing notarytool Keychain profile."
        exit 2
    }
else
    [[ -n "${STRUKTUR_INSTALLER_IDENTITY:-}" && -f "${STRUKTUR_PROVISIONING_PROFILE:-}" ]] || {
        print -u2 "App Store packaging requires STRUKTUR_INSTALLER_IDENTITY and STRUKTUR_PROVISIONING_PROFILE."
        exit 2
    }
fi

swift test
STRUKTUR_BUILD_CONFIGURATION=release STRUKTUR_QA=0 STRUKTUR_UNIVERSAL=1 ./scripts/build-app.sh
STRUKTUR_ARTIFACT="$PROJECT_DIR/dist/Struktur-$(date +%Y%m%d-%H%M%S)"
if [[ "$STRUKTUR_ROUTE" == "developer-id" ]]; then
    ditto -c -k --keepParent dist/Struktur.app "$STRUKTUR_ARTIFACT.zip"
    xcrun notarytool submit "$STRUKTUR_ARTIFACT.zip" --keychain-profile "$STRUKTUR_NOTARY_PROFILE" --wait
    xcrun stapler staple dist/Struktur.app
    xcrun stapler validate dist/Struktur.app
    spctl --assess --type execute --verbose=2 dist/Struktur.app
    ditto -c -k --keepParent dist/Struktur.app "$STRUKTUR_ARTIFACT-notarized.zip"
    print "Notarized download: $STRUKTUR_ARTIFACT-notarized.zip"
else
    productbuild --component dist/Struktur.app /Applications --sign "$STRUKTUR_INSTALLER_IDENTITY" "$STRUKTUR_ARTIFACT.pkg"
    pkgutil --check-signature "$STRUKTUR_ARTIFACT.pkg"
    print "Signed package: $STRUKTUR_ARTIFACT.pkg"
    print "Not submitted. Upload with Transporter after reviewing App Store Connect metadata."
fi
