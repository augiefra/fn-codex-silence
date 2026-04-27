#!/usr/bin/env sh
set -eu

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
MODULE_TARGET="$HS_DIR/fn-mute.lua"
INIT_TARGET="$HS_DIR/init.lua"
BEGIN_MARKER="-- >>> fn-codex-silence >>>"
END_MARKER="-- <<< fn-codex-silence <<<"
LEGACY_BEGIN_MARKER="-- >>> fn-mute-for-codex >>>"
LEGACY_END_MARKER="-- <<< fn-mute-for-codex <<<"
INSTALL_HAMMERSPOON=false
NO_BREW=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-hammerspoon)
      INSTALL_HAMMERSPOON=true
      ;;
    --no-brew)
      NO_BREW=true
      ;;
    -h|--help)
      echo "Usage: sh install.sh [--install-hammerspoon] [--no-brew]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer only supports macOS." >&2
  exit 1
fi

if [ ! -d "/Applications/Hammerspoon.app" ] && [ ! -d "$HOME/Applications/Hammerspoon.app" ]; then
  if [ "$INSTALL_HAMMERSPOON" = true ] && [ "$NO_BREW" = false ] && command -v brew >/dev/null 2>&1; then
    echo "Installing Hammerspoon with Homebrew..."
    brew install --cask hammerspoon
  else
    echo "Hammerspoon is not installed yet."
    echo "Install it from https://www.hammerspoon.org/ or run:"
    echo "  sh install.sh --install-hammerspoon"
    echo
    if command -v open >/dev/null 2>&1; then
      open "https://www.hammerspoon.org/"
    fi
  fi
fi

mkdir -p "$HS_DIR"
cp "$SOURCE_DIR/hammerspoon/fn-mute.lua" "$MODULE_TARGET"

CONFIG_BLOCK="$BEGIN_MARKER
package.loaded[\"fn-mute\"] = nil
require(\"fn-mute\").start({
  mode = \"hold\",
  showAlerts = false,
})
$END_MARKER"

if [ ! -f "$INIT_TARGET" ]; then
  printf '%s\n' "$CONFIG_BLOCK" > "$INIT_TARGET"
  echo "Created $INIT_TARGET"
else
  if grep -q -- "$BEGIN_MARKER" "$INIT_TARGET"; then
    TMP_FILE="$(mktemp)"
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block="$CONFIG_BLOCK" '
      $0 == begin {
        print block
        in_block = 1
        next
      }
      $0 == end {
        in_block = 0
        next
      }
      !in_block { print }
    ' "$INIT_TARGET" > "$TMP_FILE"
    mv "$TMP_FILE" "$INIT_TARGET"
    echo "Updated existing fn-codex-silence block in $INIT_TARGET"
  elif grep -q -- "$LEGACY_BEGIN_MARKER" "$INIT_TARGET"; then
    TMP_FILE="$(mktemp)"
    awk -v begin="$LEGACY_BEGIN_MARKER" -v end="$LEGACY_END_MARKER" -v block="$CONFIG_BLOCK" '
      $0 == begin {
        print block
        in_block = 1
        next
      }
      $0 == end {
        in_block = 0
        next
      }
      !in_block { print }
    ' "$INIT_TARGET" > "$TMP_FILE"
    mv "$TMP_FILE" "$INIT_TARGET"
    echo "Migrated legacy fn-mute block in $INIT_TARGET"
  elif grep -q -- 'fn-mute' "$INIT_TARGET"; then
    echo "$INIT_TARGET already references fn-mute without installer markers."
    echo "Leaving it unchanged; edit it manually if you want to switch to the managed block."
  else
    printf '\n%s\n' "$CONFIG_BLOCK" >> "$INIT_TARGET"
    echo "Updated $INIT_TARGET"
  fi
fi

echo "Installed $MODULE_TARGET"

if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.reload()' >/dev/null 2>&1 || true
  echo "Reloaded Hammerspoon with hs CLI."
elif command -v open >/dev/null 2>&1; then
  open -a Hammerspoon >/dev/null 2>&1 || true
  echo "Opened Hammerspoon. Use Reload Config if it was already running."
else
  echo "Open or reload Hammerspoon."
fi

echo "Grant Accessibility permission to Hammerspoon if macOS asks."
