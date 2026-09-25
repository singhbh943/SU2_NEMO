#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PREFIX="${SU2_NEMO_PREFIX:-$HOME/SU2_NEMO}"
JOBS="$(nproc)"
INSTALL_DEPS=0
CLEAN_BUILD=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/install.sh [--prefix PATH] [--jobs N] [--install-deps] [--clean-build]

Options:
  --prefix PATH     Installation prefix. Default: $HOME/SU2_NEMO
  --jobs N          Parallel build jobs. Default: nproc
  --install-deps    Install Ubuntu build dependencies first.
  --clean-build     Remove the existing Meson build directory before configuring.
  -h, --help        Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-}"; shift 2 ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --clean-build) CLEAN_BUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$PREFIX" ]] || { echo "ERROR: empty --prefix" >&2; exit 2; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --jobs must be a positive integer" >&2; exit 2; }

PREFIX="$(python3 - "$PREFIX" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"

echo "============================================================"
echo " SU2 NEMO SOURCE INSTALL"
echo "============================================================"
echo "SOURCE=$ROOT"
echo "PREFIX=$PREFIX"
echo "JOBS=$JOBS"

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null
if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  echo "ERROR: tracked source changes exist; commit or revert them before installation." >&2
  git -C "$ROOT" status --short
  exit 10
fi

if [[ $INSTALL_DEPS -eq 1 ]]; then
  "$ROOT/install_dependencies_ubuntu.sh"
fi

for cmd in git python3 cmake ninja mpicxx; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $cmd" >&2
    echo "Run: ./scripts/install.sh --install-deps" >&2
    exit 11
  }
done

echo
echo "===== SUBMODULES ====="
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive
git -C "$ROOT/subprojects/Mutationpp" rev-parse --is-inside-work-tree >/dev/null

if [[ $CLEAN_BUILD -eq 1 ]]; then
  rm -rf "$ROOT/build"
fi

echo
echo "===== CONFIGURE ====="
if [[ -d "$ROOT/build" ]]; then
  python3 "$ROOT/meson.py" setup "$ROOT/build" --reconfigure     -Denable-mpp=true     -Denable-pywrapper=true
else
  python3 "$ROOT/meson.py" setup "$ROOT/build"     -Denable-mpp=true     -Denable-pywrapper=true
fi

echo
echo "===== BUILD SU2 NEMO + MUTATION++ + PYSU2 ====="
ninja -C "$ROOT/build" -j"$JOBS"

test -x "$ROOT/build/SU2_CFD/src/SU2_CFD"

echo
echo "===== CREATE RUNTIME ====="
mkdir -p "$PREFIX"
"$ROOT/refresh_su2_nemo_runtime.sh" "$PREFIX/runtime"

PYSU2_BUILD="$ROOT/build/SU2_PY/pySU2"
if [[ ! -d "$PYSU2_BUILD" ]]; then
  echo "ERROR: PySU2 build directory missing: $PYSU2_BUILD" >&2
  exit 20
fi

rm -rf "$PREFIX/runtime/python"
mkdir -p "$PREFIX/runtime/python"
cp -a "$PYSU2_BUILD"/. "$PREFIX/runtime/python/"

cat > "$PREFIX/runtime/bin/su2-nemo-python" <<'PYWRAP'
#!/usr/bin/env bash
set -euo pipefail
SELF="$(readlink -f "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
export PYTHONPATH="$ROOT/python${PYTHONPATH:+:$PYTHONPATH}"
export MPP_DIRECTORY="$ROOT/share/mutationpp"
export MPP_DATA_DIRECTORY="$ROOT/share/mutationpp/data"
export LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export OMPI_MCA_osc="${OMPI_MCA_osc:-pt2pt}"
exec python3 "$@"
PYWRAP
chmod +x "$PREFIX/runtime/bin/su2-nemo-python"

cat >> "$PREFIX/runtime/su2_nemo_env.sh" <<'ENVADD'

# SU2_NEMO_PYTHON_RUNTIME
if [ -d "$SU2_NEMO_ROOT/python" ]; then
  export PYTHONPATH="$SU2_NEMO_ROOT/python${PYTHONPATH:+:$PYTHONPATH}"
fi
ENVADD

echo
echo "===== VERIFY SOURCE + RUNTIME ====="
"$ROOT/verify_su2_nemo.sh" "$ROOT" "$PREFIX/runtime"
"$PREFIX/runtime/verify_runtime.sh"

PYTHONPATH="$PREFIX/runtime/python${PYTHONPATH:+:$PYTHONPATH}"   python3 - <<'PY'
import pysu2
print("PYSU2_IMPORT=PASS")
PY

echo
echo "===== STABLE INSTALL LINKS ====="
ln -sfnT "$PREFIX/runtime" "$PREFIX/current"

if [[ -e "$PREFIX/bin" && ! -L "$PREFIX/bin" ]]; then
  rm -rf "$PREFIX/bin.previous"
  mv "$PREFIX/bin" "$PREFIX/bin.previous"
fi
ln -sfnT "$PREFIX/current/bin" "$PREFIX/bin"

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_BRANCH="$(git -C "$ROOT" branch --show-current)"
MPP_COMMIT="$(git -C "$ROOT/subprojects/Mutationpp" rev-parse HEAD)"

cat > "$PREFIX/INSTALLATION" <<EOF
SOURCE_ROOT=$ROOT
SOURCE_BRANCH=$SOURCE_BRANCH
SOURCE_COMMIT=$SOURCE_COMMIT
MUTATIONPP_COMMIT=$MPP_COMMIT
PREFIX=$PREFIX
EOF

echo
echo "============================================================"
echo " SU2 NEMO INSTALL COMPLETE"
echo "============================================================"
echo "SOURCE_COMMIT=$SOURCE_COMMIT"
echo "MUTATIONPP_COMMIT=$MPP_COMMIT"
echo "SU2_CFD=$PREFIX/bin/SU2_CFD"
echo "PYSU2_PYTHON=$PREFIX/bin/su2-nemo-python"
echo "SU2_NEMO_INSTALL=PASS"
echo
echo "Add to PATH:"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
