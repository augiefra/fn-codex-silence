# Distribution

Codex Dictate Companion is free to download from GitHub Releases once a release
artifact has been signed with Developer ID and notarized by Apple.

## Current target

- macOS 13 or later
- Apple Silicon only (`arm64`)
- Distribution channel: GitHub Releases
- Preferred artifact: notarized `.zip`
- Optional artifact: notarized `.dmg`

## Why notarization matters

For a public download, a local Apple Development signature is not enough.
Another Mac needs to trust the app through Apple's Developer ID and
notarization flow. Without that, users may see Gatekeeper warnings or need
manual bypass steps.

## Required Apple credentials

On a local Mac, install:

- a valid `Developer ID Application` certificate in Keychain
- a `notarytool` profile, for example:

```sh
xcrun notarytool store-credentials codex-dictate-companion \
  --apple-id "you@example.com" \
  --team-id "KX5QF45WFE" \
  --password "app-specific-password"
```

Then build the public artifacts:

```sh
NOTARY_PROFILE=codex-dictate-companion scripts/package-release.sh --version 1.0.0
```

Publish them to GitHub Releases:

```sh
scripts/publish-github-release.sh 1.0.0
```

If DMG notarization is unavailable or blocked, publish only the notarized ZIP:

```sh
NOTARY_PROFILE=codex-dictate-companion scripts/package-release.sh --version 1.0.0 --skip-dmg-notarize
scripts/publish-github-release.sh --zip-only 1.0.0
```

## GitHub Actions release

The repository also includes `.github/workflows/release.yml`.

Add these repository secrets before running it:

- `MACOS_CERTIFICATE_P12_BASE64`: base64-encoded Developer ID `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for the `.p12`
- `KEYCHAIN_PASSWORD`: temporary CI keychain password
- `APPLE_ID`: Apple Developer account email
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: Apple app-specific password for notarization

After that, run the `Release` workflow manually and enter the version.

## User install flow

1. Download `Codex-Dictate-Companion-<version>-arm64.zip` from GitHub Releases.
2. Unzip it.
3. Drag `Codex Dictate Companion.app` to Applications.
4. Launch the app from Applications.
5. Grant Input Monitoring in System Settings.
6. Keep Codex hold-to-dictate set to `Fn/Globe`.

Privacy permissions are always per Mac and per app signature. They cannot be
pre-granted inside the download.
