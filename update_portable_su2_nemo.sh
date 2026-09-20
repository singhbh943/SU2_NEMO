#!/usr/bin/env bash
set -euo pipefail
BASE="${SU2_NEMO_PORTABLE_HOME:-$HOME/SU2_NEMO_PORTABLE}"
URL_BASE="https://github.com/singhbh943/SU2_NEMO/releases/latest/download"
TAR_NAME="SU2_NEMO-portable-linux-x86_64.tar.gz"
SHA_NAME="${TAR_NAME}.sha256"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v curl >/dev/null || { echo "ERROR: curl is required" >&2; exit 10; }
curl -fL "$URL_BASE/$TAR_NAME" -o "$TMP/$TAR_NAME"
curl -fL "$URL_BASE/$SHA_NAME" -o "$TMP/$SHA_NAME"
(cd "$TMP" && sha256sum -c "$SHA_NAME")
mkdir -p "$TMP/extract"
tar -xzf "$TMP/$TAR_NAME" -C "$TMP/extract"
PKG="$(find "$TMP/extract" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "$PKG" ] || { echo "ERROR: extracted package missing" >&2; exit 20; }
"$PKG/verify_runtime.sh"
TAG="$(grep '^SU2_NEMO_TAG=' "$PKG/VERSION" | cut -d= -f2-)"
[ -n "$TAG" ] || { echo "ERROR: VERSION missing release tag" >&2; exit 21; }
DEST="$BASE/releases/$TAG"
mkdir -p "$BASE/releases"
rm -rf "$DEST"
mv "$PKG" "$DEST"
ln -sfnT "$DEST" "$BASE/current"
if [ -e "$BASE/bin" ] && [ ! -L "$BASE/bin" ]; then rm -rf "$BASE/bin"; fi
ln -sfnT "$BASE/current/bin" "$BASE/bin"
echo "PORTABLE_UPDATE=PASS"
echo "VERSION=$TAG"
echo "Set: export PATH=\"$BASE/bin:\$PATH\""
