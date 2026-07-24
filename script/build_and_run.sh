#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="CodexDictateCompanion"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${TMPDIR:-/private/tmp}/codex-dictate-companion-xcode"
STAGED_SOURCE_DIR="$DERIVED_DATA_PATH/Source"
PROJECT_PATH="$STAGED_SOURCE_DIR/CodexDictateCompanion.xcodeproj"
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

stage_source() {
  rm -rf "$STAGED_SOURCE_DIR"
  mkdir -p "$STAGED_SOURCE_DIR"
  cp -R \
    "$ROOT_DIR/CodexDictateCompanion.xcodeproj" \
    "$ROOT_DIR/CodexDictateCompanion" \
    "$ROOT_DIR/Sources" \
    "$ROOT_DIR/Resources" \
    "$STAGED_SOURCE_DIR/"
  xattr -cr "$STAGED_SOURCE_DIR" >/dev/null 2>&1 || true
}

build_app() {
  select_xcode
  stage_source

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

if [[ "$MODE" != "build" ]]; then
  stop_existing
fi
build_app

case "$MODE" in
  build)
    ;;
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
    echo "usage: $0 [build|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
