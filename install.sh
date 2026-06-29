#!/usr/bin/env sh
set -eu

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_BUNDLE="$HOME/Applications/Codex Dictate Companion.app"
PROJECT_PATH="$SOURCE_DIR/CodexDictateCompanion.xcodeproj"
SCHEME="CodexDictateCompanion"
DERIVED_DATA_PATH="${TMPDIR:-/private/tmp}/codex-dictate-companion-xcode"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/Codex Dictate Companion.app"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.augiefra.codex-dictate-companion.plist"
LOG_DIR="$HOME/Library/Logs/codex-dictate-companion"
SHORTCUT="fn"
DEVELOPMENT_TEAM="KX5QF45WFE"

OLD_PLIST_TARGET="$HOME/Library/LaunchAgents/com.augiefra.fn-codex-silence.plist"
OLD_APP_BUNDLE="$HOME/Applications/Fn Codex Silence.app"
OLD_APP_SUPPORT_DIR="$HOME/Library/Application Support/fn-codex-silence"

usage() {
  cat <<'EOF'
Usage: sh install.sh [--shortcut fn|ctrl+space|cmd+shift+x|keycode:49]

Installs Codex Dictate Companion as a menu bar app launched at login.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shortcut)
      if [ "$#" -lt 2 ]; then
        echo "--shortcut requires a value." >&2
        exit 1
      fi
      SHORTCUT="$2"
      shift
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

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer only supports macOS." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode is required to build Codex Dictate Companion." >&2
  exit 1
fi

if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  elif [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$LOG_DIR"

echo "Using Xcode toolchain:"
xcodebuild -version

# macOS can attach Finder metadata to copied .icns files. codesign rejects
# that metadata inside app bundles, so keep the source tree clean before build.
xattr -cr "$SOURCE_DIR/Resources" "$SOURCE_DIR/CodexDictateCompanion" "$SOURCE_DIR/CodexDictateCompanion.xcodeproj" >/dev/null 2>&1 || true

echo "Building Codex Dictate Companion with Xcode..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  build

if [ ! -d "$BUILT_APP" ]; then
  echo "Build succeeded but $BUILT_APP was not found." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
cp -R "$BUILT_APP" "$APP_BUNDLE"

touch "$APP_BUNDLE"

cat > "$PLIST_TARGET" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.augiefra.codex-dictate-companion</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-gj</string>
    <string>$APP_BUNDLE</string>
    <string>--args</string>
    <string>--shortcut</string>
    <string>$SHORTCUT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchd-out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchd-error.log</string>
</dict>
</plist>
EOF

if launchctl print "gui/$(id -u)/com.augiefra.fn-codex-silence" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "$OLD_PLIST_TARGET" >/dev/null 2>&1 || true
fi

if launchctl print "gui/$(id -u)/com.augiefra.codex-dictate-companion" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
fi

pkill -x fn-codex-silence >/dev/null 2>&1 || true
pkill -x codex-dictate-companion >/dev/null 2>&1 || true
pkill -x "Codex Dictate Companion" >/dev/null 2>&1 || true

rm -f "$OLD_PLIST_TARGET"
rm -rf "$OLD_APP_BUNDLE"
rm -rf "$OLD_APP_SUPPORT_DIR"

launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"
launchctl kickstart -k "gui/$(id -u)/com.augiefra.codex-dictate-companion"

echo "Installed $APP_BUNDLE"
echo "Loaded LaunchAgent $PLIST_TARGET"
echo "Launch method: /usr/bin/open -gj"
echo "Shortcut: $SHORTCUT"
echo
echo "Use the menu bar icon to check permissions, test mute, and choose one of three icons."
echo "If macOS asks for Input Monitoring or Accessibility permission, grant it to Codex Dictate Companion."
echo "Logs: $LOG_DIR"
