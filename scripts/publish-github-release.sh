#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-github-release.sh [--zip-only] <version>

Publishes dist/release-<version> artifacts to a public GitHub Release.
Run scripts/package-release.sh first.
EOF
}

ZIP_ONLY=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --zip-only)
      ZIP_ONLY=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "${VERSION:-}" ]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 1
      fi
      VERSION="$1"
      ;;
  esac
  shift
done

if [ -z "${VERSION:-}" ]; then
  usage >&2
  exit 1
fi

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

if [ ! -f "$ZIP_PATH" ] || [ ! -f "$NOTES_PATH" ]; then
  echo "Missing release artifacts in $RELEASE_DIR." >&2
  echo "Run scripts/package-release.sh --version $VERSION first." >&2
  exit 1
fi

if [ "$ZIP_ONLY" = false ] && [ ! -f "$DMG_PATH" ]; then
  echo "Missing DMG artifact in $RELEASE_DIR." >&2
  echo "Pass --zip-only to publish only the notarized ZIP." >&2
  exit 1
fi

gh auth status >/dev/null

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag "$TAG"
fi

git push origin "$TAG"

if [ "$ZIP_ONLY" = true ]; then
  gh release create "$TAG" \
    "$ZIP_PATH" \
    --title "Codex Dictate Companion $VERSION" \
    --notes-file "$NOTES_PATH"
else
  gh release create "$TAG" \
    "$DMG_PATH" \
    "$ZIP_PATH" \
    --title "Codex Dictate Companion $VERSION" \
    --notes-file "$NOTES_PATH"
fi
