#!/usr/bin/env sh
set -eu

APP_NAME="Codex Dictate Companion"
SCHEME="CodexDictateCompanion"
TEAM_ID="${DEVELOPMENT_TEAM:-KX5QF45WFE}"
CONFIGURATION="Release"
REQUIRE_NOTARIZATION=true
VERSION=""
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/package-release.sh [--version 1.0.0] [--identity "Developer ID Application: ..."] [--notary-profile profile] [--notary-keychain path] [--skip-notarize]

Builds an Apple Silicon-only public release artifact:
  dist/release-<version>/Codex-Dictate-Companion-<version>-arm64.dmg
  dist/release-<version>/Codex-Dictate-Companion-<version>-arm64.zip

For public GitHub distribution, use a Developer ID Application certificate and notarization.
Set NOTARY_PROFILE to an xcrun notarytool keychain profile, or pass --notary-profile.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ]; then
        echo "--version requires a value." >&2
        exit 1
      fi
      VERSION="$2"
      shift
      ;;
    --identity)
      if [ "$#" -lt 2 ]; then
        echo "--identity requires a value." >&2
        exit 1
      fi
      CODESIGN_IDENTITY="$2"
      shift
      ;;
    --notary-profile)
      if [ "$#" -lt 2 ]; then
        echo "--notary-profile requires a value." >&2
        exit 1
      fi
      NOTARY_PROFILE="$2"
      shift
      ;;
    --notary-keychain)
      if [ "$#" -lt 2 ]; then
        echo "--notary-keychain requires a value." >&2
        exit 1
      fi
      NOTARY_KEYCHAIN="$2"
      shift
      ;;
    --skip-notarize)
      REQUIRE_NOTARIZATION=false
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT_PATH="$SOURCE_DIR/CodexDictateCompanion.xcodeproj"
INFO_PLIST="$SOURCE_DIR/CodexDictateCompanion/Info.plist"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Release packaging only supports macOS." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode is required." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required." >&2
  exit 1
fi

if [ -z "$VERSION" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
fi

if [ -z "$CODESIGN_IDENTITY" ]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi

if [ -z "$CODESIGN_IDENTITY" ]; then
  cat >&2 <<'EOF'
No Developer ID Application certificate was found in this Mac keychain.

Public GitHub downloads need:
  1. Apple Developer Program membership
  2. A "Developer ID Application" certificate installed in Keychain
  3. A notarytool profile, created with:
     xcrun notarytool store-credentials codex-dictate-companion \
       --apple-id "you@example.com" \
       --team-id "TEAMID" \
       --password "app-specific-password"

For a local unsigned/not-public test only, pass:
  --identity "Apple Development: ..." --skip-notarize
EOF
  exit 1
fi

if [ "$REQUIRE_NOTARIZATION" = true ] && [ -z "$NOTARY_PROFILE" ]; then
  cat >&2 <<'EOF'
NOTARY_PROFILE is required for a public release.

Create it once with:
  xcrun notarytool store-credentials codex-dictate-companion \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"

Then run:
  NOTARY_PROFILE=codex-dictate-companion scripts/package-release.sh

For a local packaging test only, pass --skip-notarize.
EOF
  exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi

notarytool_submit() {
  artifact_path="$1"
  if [ -n "$NOTARY_KEYCHAIN" ]; then
    xcrun notarytool submit "$artifact_path" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" --wait
  else
    xcrun notarytool submit "$artifact_path" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
}

SLUG_VERSION="$(printf '%s' "$VERSION" | tr -c '[:alnum:]._-' '-')"
DERIVED_DATA_PATH="${TMPDIR:-/private/tmp}/codex-dictate-companion-release"
RELEASE_DIR="$SOURCE_DIR/dist/release-$SLUG_VERSION"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
SIGNED_APP="$RELEASE_DIR/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/Codex-Dictate-Companion-$SLUG_VERSION-arm64.zip"
DMG_PATH="$RELEASE_DIR/Codex-Dictate-Companion-$SLUG_VERSION-arm64.dmg"
NOTES_PATH="$RELEASE_DIR/RELEASE_NOTES.md"

rm -rf "$DERIVED_DATA_PATH" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "Building $APP_NAME $VERSION for Apple Silicon..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Build succeeded but app bundle was not found: $APP_BUNDLE" >&2
  exit 1
fi

ditto --noextattr --noqtn "$APP_BUNDLE" "$SIGNED_APP"
xattr -cr "$SIGNED_APP" >/dev/null 2>&1 || true
find "$SIGNED_APP" -depth -exec xattr -d com.apple.FinderInfo {} \; >/dev/null 2>&1 || true
find "$SIGNED_APP" -depth -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; >/dev/null 2>&1 || true

ARCHS_FOUND="$(lipo -archs "$SIGNED_APP/Contents/MacOS/$APP_NAME")"
if [ "$ARCHS_FOUND" != "arm64" ]; then
  echo "Expected arm64-only binary, found: $ARCHS_FOUND" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"

if [ "$REQUIRE_NOTARIZATION" = true ]; then
  echo "Submitting app for notarization..."
  ditto -c -k --keepParent "$SIGNED_APP" "$ZIP_PATH"
  notarytool_submit "$ZIP_PATH"
  xcrun stapler staple "$SIGNED_APP"
  rm -f "$ZIP_PATH"
fi

echo "Creating ZIP..."
ditto -c -k --keepParent "$SIGNED_APP" "$ZIP_PATH"

echo "Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$SIGNED_APP" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ "$REQUIRE_NOTARIZATION" = true ]; then
  echo "Submitting DMG for notarization..."
  notarytool_submit "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
fi

cat > "$NOTES_PATH" <<EOF
# Codex Dictate Companion $VERSION

Apple Silicon-only macOS menu bar app for Codex hold-to-dictate.

## Install

1. Download \`Codex-Dictate-Companion-$SLUG_VERSION-arm64.dmg\`.
2. Open the DMG and drag \`Codex Dictate Companion.app\` to Applications.
3. Launch the app.
4. Grant Input Monitoring when macOS asks.
5. In Codex, keep Hold-to-dictate set to \`Fn/Globe\`.

## Notes

- Requires macOS 13 or later.
- Built for Apple Silicon only.
- AirPods Stereo Guard is enabled by default.
EOF

echo
echo "Release artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $NOTES_PATH"
