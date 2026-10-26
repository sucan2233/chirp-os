#!/bin/bash
# Offline release preparation only: no GitHub requests, upload, or publishing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CHECK=0
case "${1:-}" in
    '') [[ $# == 0 ]] || exit 2 ;;
    --release) [[ $# == 1 ]] || exit 2 ;;
    --check) [[ $# == 1 ]] || exit 2; CHECK=1 ;;
    *) echo 'Usage: scripts/release-pro-macos.sh [--release | --check]' >&2; exit 2 ;;
esac
VERSION="$(cat "$ROOT/scripts/pro-version.txt")"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$ || "$VERSION" == 0.0.0 ]]; then
    echo 'Invalid Pro version: expected X.Y.Z (major <= 9999; minor/patch <= 99)' >&2
    exit 1
fi
export RELEASE_TAG="${RELEASE_TAG:-pro-v$VERSION}"
if [[ "$RELEASE_TAG" != "pro-v$VERSION" ]]; then
    echo 'RELEASE_TAG must be pro-v plus scripts/pro-version.txt' >&2
    exit 1
fi
SOURCE_COMMIT="$(git rev-parse HEAD)"
TAG_COMMIT="$(git rev-parse --verify "refs/tags/$RELEASE_TAG^{commit}")"
if [[ "$SOURCE_COMMIT" != "$TAG_COMMIT" ]]; then
    echo 'Release tag must already exist and point to the current source commit' >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo 'Release preparation requires a clean source tree; commit source changes before tagging' >&2
    exit 1
fi
git ls-files --error-unmatch scripts/pro-version.txt config/pro-update-public-key.txt "docs/releases/$RELEASE_TAG.md" >/dev/null
[[ -s "docs/releases/$RELEASE_TAG.md" ]] || { echo 'Release notes are missing or empty' >&2; exit 1; }
PRIVATE_KEY="${CHIRPOS_UPDATE_PRIVATE_KEY_FILE:-$ROOT/.local/pro-update-private-key}"
PUBLIC_KEY="$ROOT/config/pro-update-public-key.txt"
swift "$ROOT/scripts/pro-update-sign.swift" check-key "$PRIVATE_KEY" "$PUBLIC_KEY"
if [[ "$CHECK" == 1 ]]; then
    printf 'Pro release preflight OK: %s at %s\n' "$RELEASE_TAG" "$SOURCE_COMMIT"
    exit 0
fi
bash "$ROOT/scripts/package-pro-macos.sh" --release
ARCH="$(uname -m)"
OUTPUT="$ROOT/dist/pro-release"
ARCHIVE="$OUTPUT/ChirpOS-Pro-$VERSION-macOS-$ARCH.zip"
swift "$ROOT/scripts/pro-update-sign.swift" verify "$ARCHIVE" "$VERSION" "$PUBLIC_KEY"
(
    cd "$OUTPUT"
    shasum -a 256 -c SHA256SUMS.txt
)
printf 'Offline Pro release ready: %s\nTag: %s\nSource: %s\n' "$OUTPUT" "$RELEASE_TAG" "$SOURCE_COMMIT"
printf 'GitHub workflow must verify the uploaded ZIP API digest before publishing the draft.\n'
