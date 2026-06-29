#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CodexDictateCompanion.xcodeproj"
SCHEME="CodexDictateCompanion"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${TMPDIR:-/private/tmp}/codex-dictate-companion-xcode"
APP_NAME="Codex Dictate Companion"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TEAM_ID="${DEVELOPMENT_TEAM:-KX5QF45WFE}"

select_xcode() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
}

stop_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x codex-dictate-companion >/dev/null 2>&1 || true
}

clean_xattrs() {
  xattr -cr "$ROOT_DIR/Resources" "$ROOT_DIR/CodexDictateCompanion" "$ROOT_DIR/CodexDictateCompanion.xcodeproj" >/dev/null 2>&1 || true
}

build_app() {
  select_xcode
  clean_xattrs

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_existing
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs|--telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -f "/Contents/MacOS/$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
