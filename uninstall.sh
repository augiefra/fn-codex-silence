#!/usr/bin/env sh
set -eu

HS_DIR="$HOME/.hammerspoon"
MODULE_TARGET="$HS_DIR/fn-mute.lua"
INIT_TARGET="$HS_DIR/init.lua"
BEGIN_MARKER="-- >>> fn-codex-silence >>>"
END_MARKER="-- <<< fn-codex-silence <<<"
LEGACY_BEGIN_MARKER="-- >>> fn-mute-for-codex >>>"
LEGACY_END_MARKER="-- <<< fn-mute-for-codex <<<"

if [ -f "$MODULE_TARGET" ]; then
  rm "$MODULE_TARGET"
  echo "Removed $MODULE_TARGET"
fi

if [ -f "$INIT_TARGET" ] && grep -q -- "$BEGIN_MARKER" "$INIT_TARGET"; then
  TMP_FILE="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin {
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
  echo "Removed managed fn-codex-silence block from $INIT_TARGET"
elif [ -f "$INIT_TARGET" ] && grep -q -- "$LEGACY_BEGIN_MARKER" "$INIT_TARGET"; then
  TMP_FILE="$(mktemp)"
  awk -v begin="$LEGACY_BEGIN_MARKER" -v end="$LEGACY_END_MARKER" '
    $0 == begin {
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
  echo "Removed legacy fn-mute block from $INIT_TARGET"
fi

if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.reload()' >/dev/null 2>&1 || true
  echo "Reloaded Hammerspoon with hs CLI."
fi
