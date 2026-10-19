# Android release guide

## Current version

Hon 1.1.1, Android version code 3, application ID `com.hon.reader.hon`.
Increase the code after `+` in `pubspec.yaml` for each new distributed version.

## Two signing options

Both APKs are optimized Flutter **release** builds.

| File | Signing | Installation |
| --- | --- | --- |
| `build/releases/Hon-1.1.1-complete.apk` | Existing local Android certificate | Intended for this user's existing Hon installation; install over it. |
| `build/releases/Hon-1.1.1-production.apk` | Dedicated private Hon release certificate | For a fresh installation or a planned signing migration. Android cannot install it over the local-certificate build. |

Use the **complete** APK for the next phone test. Do not uninstall the current app to install the production APK; uninstalling removes app data. A later signing migration should start with a saved portable backup and a verified restore.

## Build commands

Run from the Hon project folder, with Flutter available on PATH:

```sh
# Dedicated release certificate, configured below.
flutter build apk --release --no-pub

# Update-compatible release for the existing local installation.
ORG_GRADLE_PROJECT_honLocalSigning=true flutter build apk --release --no-pub
```

Each command writes `build/app/outputs/flutter-apk/app-release.apk`; copy it to its named release file before running the other command. Do not distribute an older output when a build fails.

## Private signing material

The dedicated release configuration is in `android/key.properties`. Its template is `android/key.properties.example`.
The private key is `android/keystore/hon-release.jks`; its locally generated password is kept in `android/keystore/signing-password.txt`. These files are ignored by Git and readable only by the local user. No signing material is included in app backups or APK assets.

Keep a private, encrypted backup of this directory and configuration before publishing under this certificate. Losing the key prevents signing future updates with that identity. Preserve the existing local Android debug keystore separately while update-compatible local APKs are still needed. Do not paste either password or keystore into review exports.

The default release task requires the dedicated signing configuration. An explicit `honLocalSigning=true` is required to use the local certificate. Debug tasks remain available without the dedicated key.

## Package checks

Before distributing a newly built APK:

1. Verify its APK signature and compare the certificate with the intended installation.
2. Check the version name/code and application ID.
3. Check all 172 source asset hashes against packaged `assets/sources/bundled/catalog.json`, plus the eight bundled text fonts.
4. Write a SHA-256 sidecar for the exact distributed file.
5. Confirm `ContinuousEpubView.Metrics.resized` survives release shrinking; the JavaScript interface annotation is retained by Android's default ProGuard configuration.

Publication to a store, store-account setup and public hosting are separate distribution actions.
