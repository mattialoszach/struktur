# Distribution

The local app is ad-hoc signed. Public release requires your Apple Developer identity and an explicit distribution choice. No credentials belong in this repository.

## Notarized download

Install a Developer ID Application certificate with its private key in Keychain. Create a notarytool Keychain profile using Apple's credential flow, then run:

~~~sh
export STRUKTUR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export STRUKTUR_NOTARY_PROFILE="your-keychain-profile"
./scripts/distribute.sh developer-id
~~~

This explicitly uploads the signed archive to Apple's notarization service, staples the result, assesses the app, and produces a timestamped notarized ZIP. It does not publish a website or release.

## Mac App Store

Configure an App ID for the app.struktur.mac identifier, an appropriate distribution provisioning profile, and Apple Distribution/Mac App Distribution plus Mac Installer Distribution signing identities. Set STRUKTUR_SIGN_IDENTITY, STRUKTUR_INSTALLER_IDENTITY, and STRUKTUR_PROVISIONING_PROFILE, then run:

~~~sh
./scripts/distribute.sh app-store
~~~

This creates a signed installer package, but does not upload or submit it. Before submission, the owner must approve the app record, seller identity, price/availability, support and privacy-policy URLs, screenshots, age rating, export-compliance answers, and review notes in App Store Connect. Upload with Transporter and submit only after final approval.

## Local verification

~~~sh
swift test
./scripts/build-app.sh
codesign --verify --deep --strict dist/Struktur.app
~~~

Keep previous bundles and workspace backups until the release has been validated. A previous binary may not understand a newer workspace schema; restore a matching backup rather than forcing a downgrade.

Reference: Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
