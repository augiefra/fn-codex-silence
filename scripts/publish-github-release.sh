#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-github-release.sh <version>

Publishes dist/release-<version> artifacts to a public GitHub Release.
Run scripts/package-release.sh first.
EOF
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 1
fi

VERSION="$1"
TAG="v$VERSION"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RELEASE_DIR="$SOURCE_DIR/dist/release-$VERSION"
NOTES_PATH="$RELEASE_DIR/RELEASE_NOTES.md"
DMG_PATH="$RELEASE_DIR/Codex-Dictate-Companion-$VERSION-arm64.dmg"
ZIP_PATH="$RELEASE_DIR/Codex-Dictate-Companion-$VERSION-arm64.zip"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if [ ! -f "$DMG_PATH" ] || [ ! -f "$ZIP_PATH" ] || [ ! -f "$NOTES_PATH" ]; then
  echo "Missing release artifacts in $RELEASE_DIR." >&2
  echo "Run scripts/package-release.sh --version $VERSION first." >&2
  exit 1
fi

gh auth status >/dev/null

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag "$TAG"
fi

git push origin "$TAG"

gh release create "$TAG" \
  "$DMG_PATH" \
  "$ZIP_PATH" \
  --title "Codex Dictate Companion $VERSION" \
  --notes-file "$NOTES_PATH"
