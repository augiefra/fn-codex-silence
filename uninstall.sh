#!/usr/bin/env sh
set -eu

APP_BUNDLE="$HOME/Applications/Codex Dictate Companion.app"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.augiefra.codex-dictate-companion.plist"
LOG_DIR="$HOME/Library/Logs/codex-dictate-companion"

OLD_PLIST_TARGET="$HOME/Library/LaunchAgents/com.augiefra.fn-codex-silence.plist"
OLD_APP_BUNDLE="$HOME/Applications/Fn Codex Silence.app"
OLD_APP_SUPPORT_DIR="$HOME/Library/Application Support/fn-codex-silence"
OLD_LOG_DIR="$HOME/Library/Logs/fn-codex-silence"

REMOVE_LOGS=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remove-logs)
      REMOVE_LOGS=true
      ;;
    -h|--help)
      echo "Usage: sh uninstall.sh [--remove-logs]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if launchctl print "gui/$(id -u)/com.augiefra.codex-dictate-companion" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
  echo "Unloaded LaunchAgent com.augiefra.codex-dictate-companion"
fi

if launchctl print "gui/$(id -u)/com.augiefra.fn-codex-silence" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "$OLD_PLIST_TARGET" >/dev/null 2>&1 || true
  echo "Unloaded old LaunchAgent com.augiefra.fn-codex-silence"
fi

pkill -x codex-dictate-companion >/dev/null 2>&1 || true
pkill -x fn-codex-silence >/dev/null 2>&1 || true
pkill -x "Codex Dictate Companion" >/dev/null 2>&1 || true

if [ -f "$PLIST_TARGET" ]; then
  rm "$PLIST_TARGET"
  echo "Removed $PLIST_TARGET"
fi

if [ -f "$OLD_PLIST_TARGET" ]; then
  rm "$OLD_PLIST_TARGET"
  echo "Removed old $OLD_PLIST_TARGET"
fi

if [ -d "$APP_BUNDLE" ]; then
  rm -rf "$APP_BUNDLE"
  echo "Removed $APP_BUNDLE"
fi

if [ -d "$OLD_APP_BUNDLE" ]; then
  rm -rf "$OLD_APP_BUNDLE"
  echo "Removed old $OLD_APP_BUNDLE"
fi

if [ -d "$OLD_APP_SUPPORT_DIR" ]; then
  rm -rf "$OLD_APP_SUPPORT_DIR"
  echo "Removed old $OLD_APP_SUPPORT_DIR"
fi

if [ "$REMOVE_LOGS" = true ]; then
  if [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
    echo "Removed $LOG_DIR"
  fi

  if [ -d "$OLD_LOG_DIR" ]; then
    rm -rf "$OLD_LOG_DIR"
    echo "Removed old $OLD_LOG_DIR"
  fi
fi
