#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
OUT="${1:-$HOME/SU2_NEMO_RELEASES}"
mkdir -p "$OUT"
TAG="$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || true)"
[ -n "$TAG" ] || TAG="commit-$(git -C "$SRC" rev-parse --short=12 HEAD)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG="SU2_NEMO-${TAG}-linux-x86_64"
STAGE="$TMP/$PKG"
"$SRC/refresh_su2_nemo_runtime.sh" "$STAGE"
(
  cd "$STAGE"
  find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
)
TAR="$OUT/SU2_NEMO-portable-linux-x86_64.tar.gz"
SHA="$TAR.sha256"
tar -C "$TMP" -czf "$TAR" "$PKG"
(cd "$OUT" && sha256sum "$(basename "$TAR")" > "$(basename "$SHA")")
echo "PORTABLE_TAR=$TAR"
echo "PORTABLE_SHA=$SHA"
echo "PORTABLE_PACKAGE_ROOT=$PKG"
echo "PORTABLE_TAR_CREATION=PASS"
