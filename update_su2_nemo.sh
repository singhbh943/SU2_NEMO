#!/usr/bin/env bash
set -euo pipefail
HOME_NEMO="${SU2_NEMO_HOME:-$HOME/SU2_NEMO}"
SRC="${SU2_NEMO_SOURCE:-$HOME_NEMO/source}"
RUNTIME="$HOME_NEMO/runtime"
BRANCH="nemo-extreme-mach-hardening"

[ -d "$SRC/.git" ] || { echo "ERROR: source installation not found: $SRC" >&2; exit 10; }
[ -z "$(git -C "$SRC" status --porcelain --ignore-submodules=dirty)" ] || { git -C "$SRC" status --short; echo "ERROR: local SU2 changes exist" >&2; exit 11; }
[ -z "$(git -C "$SRC/subprojects/Mutationpp" status --porcelain)" ] || { echo "ERROR: local Mutation++ changes exist" >&2; exit 12; }

cd "$SRC"
git fetch origin "$BRANCH" --tags
git checkout "$BRANCH"
git merge --ff-only "origin/$BRANCH"
git submodule sync --recursive
git submodule update --init --recursive
if [ -d build ]; then python3 ./meson.py setup build --reconfigure -Denable-mpp=true; else python3 ./meson.py setup build -Denable-mpp=true; fi
if command -v ninja >/dev/null 2>&1; then NINJA="$(command -v ninja)"; elif [ -x "$SRC/ninja" ]; then NINJA="$SRC/ninja"; else echo "ERROR: ninja not found" >&2; exit 20; fi
"$NINJA" -C build SU2_CFD/src/SU2_CFD -j"$(nproc)"
"$SRC/refresh_su2_nemo_runtime.sh" "$RUNTIME"
"$SRC/verify_su2_nemo.sh" "$SRC" "$RUNTIME"
ln -sfnT "$RUNTIME" "$HOME_NEMO/current"
if [ -e "$HOME_NEMO/bin" ] && [ ! -L "$HOME_NEMO/bin" ]; then rm -rf "$HOME_NEMO/bin"; fi
ln -sfnT "$HOME_NEMO/current/bin" "$HOME_NEMO/bin"
echo "SU2_NEMO_INCREMENTAL_UPDATE=PASS"
echo "DEPENDENCIES_REINSTALLED=NO"
echo "FULL_RECLONE=NO"
