#!/usr/bin/env bash
set -euo pipefail
HOME_NEMO="${SU2_NEMO_HOME:-$HOME/SU2_NEMO}"
SRC="$HOME_NEMO/source"
RUNTIME="$HOME_NEMO/runtime"
REPO="https://github.com/singhbh943/SU2_NEMO.git"
BRANCH="nemo-extreme-mach-hardening"

if [ -e "$SRC" ]; then
  echo "ERROR: source already exists: $SRC" >&2
  echo "Use $SRC/update_su2_nemo.sh for an existing source installation." >&2
  exit 10
fi
mkdir -p "$HOME_NEMO"
git clone --branch "$BRANCH" "$REPO" "$SRC"
cd "$SRC"
git submodule sync --recursive
git submodule update --init --recursive
python3 ./meson.py setup build -Denable-mpp=true
if command -v ninja >/dev/null 2>&1; then NINJA="$(command -v ninja)"; elif [ -x "$SRC/ninja" ]; then NINJA="$SRC/ninja"; else echo "ERROR: ninja not found" >&2; exit 20; fi
"$NINJA" -C build SU2_CFD/src/SU2_CFD -j"$(nproc)"
"$SRC/refresh_su2_nemo_runtime.sh" "$RUNTIME"
"$SRC/verify_su2_nemo.sh" "$SRC" "$RUNTIME"
ln -sfnT "$RUNTIME" "$HOME_NEMO/current"
if [ -e "$HOME_NEMO/bin" ] && [ ! -L "$HOME_NEMO/bin" ]; then rm -rf "$HOME_NEMO/bin"; fi
ln -sfnT "$HOME_NEMO/current/bin" "$HOME_NEMO/bin"
echo "FRESH_SU2_NEMO_INSTALL=PASS"
echo "Add once: export PATH=\"$HOME_NEMO/bin:\$PATH\""
