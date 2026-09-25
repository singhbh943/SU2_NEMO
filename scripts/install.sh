#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DEFAULT_PREFIX="$(cd "$ROOT/.." && pwd)/SU2_install"
PREFIX="${SU2_INSTALL_PREFIX:-$DEFAULT_PREFIX}"
JOBS="$(nproc)"
INSTALL_DEPS=0
INSTALL_PATO_ENV=0
CLEAN_BUILD=0
PERSIST_SHELL=0
SKIP_PATO_BUILD=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/install.sh [options]

Installs standard SU2 + NEMO + Mutation++ + PySU2 + PATO + SU2-PATO
into one official-style SU2 installation prefix.

Options:
  --prefix PATH          Install prefix. Default: sibling SU2_install directory.
  --jobs N               Parallel build jobs. Default: nproc.
  --install-deps         Install Ubuntu SU2 build dependencies.
  --install-pato-env     Create/update the pinned PATO 3.1 Conda environment.
  --skip-pato-build      Reuse an already-built PATO submodule.
  --clean-build          Remove the SU2 Meson build directory before configure.
  --persist-shell        Add the unified SU2 activation to ~/.bashrc.
  -h, --help             Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-}"; shift 2 ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --install-pato-env) INSTALL_PATO_ENV=1; shift ;;
    --skip-pato-build) SKIP_PATO_BUILD=1; shift ;;
    --clean-build) CLEAN_BUILD=1; shift ;;
    --persist-shell) PERSIST_SHELL=1; shift ;;
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

PATO="$ROOT/externals/PATO"
COUPLING="$ROOT/coupling/SU2_PATO"
CONDA_BASE="${SU2_PATO_CONDA_BASE:-$HOME/miniconda3}"
PATO_ENV="${SU2_PATO_CONDA_ENV:-su2-nemo-pato}"
PYTHON_BIN="$(command -v python3)"

echo "============================================================"
echo " UNIFIED SU2 + NEMO + MUTATION++ + PATO INSTALL"
echo "============================================================"
echo "SOURCE=$ROOT"
echo "PREFIX=$PREFIX"
echo "JOBS=$JOBS"

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null
if ! git -C "$ROOT" diff --ignore-submodules=dirty --quiet || ! git -C "$ROOT" diff --cached --ignore-submodules=dirty --quiet; then
  echo "ERROR: tracked SU2 source changes exist; commit or revert them before installation." >&2
  git -C "$ROOT" status --short
  exit 10
fi

if [[ $INSTALL_DEPS -eq 1 ]]; then
  "$ROOT/install_dependencies_ubuntu.sh"
fi

for cmd in git python3 cmake ninja mpicxx tar ldd readelf; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $cmd" >&2
    exit 11
  }
done

echo
echo "===== SUBMODULES ====="
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive
[[ -d "$ROOT/subprojects/Mutationpp" ]] || { echo "ERROR: Mutation++ submodule missing" >&2; exit 12; }
[[ -d "$PATO" ]] || { echo "ERROR: PATO submodule missing" >&2; exit 13; }

MPP_COMMIT="$(git -C "$ROOT/subprojects/Mutationpp" rev-parse HEAD)"
PATO_COMMIT="$(git -C "$PATO" rev-parse HEAD)"
echo "MUTATIONPP_COMMIT=$MPP_COMMIT"
echo "PATO_COMMIT=$PATO_COMMIT"

if [[ $INSTALL_PATO_ENV -eq 1 ]]; then
  [[ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]] || {
    echo "ERROR: Conda activation not found: $CONDA_BASE/etc/profile.d/conda.sh" >&2
    exit 14
  }
  "$ROOT/tools/install_pato_environment.sh"
else
  [[ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]] || {
    echo "ERROR: PATO requires Conda at $CONDA_BASE." >&2
    echo "Install Miniconda, then rerun with --install-pato-env." >&2
    exit 14
  }
  set +u
  source "$CONDA_BASE/etc/profile.d/conda.sh"
  if ! conda env list | awk '{print $1}' | grep -Fxq "$PATO_ENV"; then
    echo "ERROR: PATO environment '$PATO_ENV' is missing." >&2
    echo "Rerun with --install-pato-env." >&2
    exit 15
  fi
  set -u
fi

if [[ $CLEAN_BUILD -eq 1 ]]; then
  rm -rf "$ROOT/build"
fi

echo
echo "===== CONFIGURE SU2 ====="
if [[ -d "$ROOT/build" ]]; then
  "$PYTHON_BIN" "$ROOT/meson.py" setup "$ROOT/build" --reconfigure --prefix "$PREFIX" -Denable-mpp=true -Dinstall-mpp=true -Denable-pywrapper=true
else
  "$PYTHON_BIN" "$ROOT/meson.py" setup "$ROOT/build" --prefix "$PREFIX" -Denable-mpp=true -Dinstall-mpp=true -Denable-pywrapper=true
fi

if [[ -x "$ROOT/ninja" ]]; then
  NINJA="$ROOT/ninja"
else
  NINJA="$(command -v ninja)"
fi

echo
echo "===== BUILD SU2 + NEMO + MUTATION++ + PYSU2 ====="
"$NINJA" -C "$ROOT/build" -j"$JOBS"

echo
echo "===== INSTALL NORMAL SU2 PREFIX ====="
mkdir -p "$PREFIX"
"$NINJA" -C "$ROOT/build" install

for exe in SU2_CFD SU2_DEF SU2_DOT SU2_GEO SU2_SOL; do
  [[ -x "$PREFIX/bin/$exe" ]] || { echo "ERROR: missing installed $exe" >&2; exit 20; }
done

MPP_LIB="$(find "$PREFIX/lib" -maxdepth 2 \( -type f -o -type l \) -name 'libmutation__.so' -print -quit)"
[[ -n "$MPP_LIB" && -f "$MPP_LIB" ]] || { echo "ERROR: installed libmutation__.so not found" >&2; exit 21; }
LIBDIR="$(dirname "$MPP_LIB")"

if [[ ! -d "$PREFIX/mpp-data" ]]; then
  cp -a "$ROOT/subprojects/Mutationpp/data" "$PREFIX/mpp-data"
fi
for f in mixtures/air_5.xml mixtures/air_7.xml mixtures/air_11.xml mechanisms/air5_Park.xml mechanisms/air7_Park.xml mechanisms/air11_Park.xml; do
  [[ -f "$PREFIX/mpp-data/$f" ]] || { echo "ERROR: Mutation++ data missing: $f" >&2; exit 22; }
done

mkdir -p "$PREFIX/share/mutationpp"
rm -f "$PREFIX/share/mutationpp/data"
ln -s "$PREFIX/mpp-data" "$PREFIX/share/mutationpp/data"

[[ -f "$PREFIX/bin/pysu2.py" && -f "$PREFIX/bin/_pysu2.so" ]] || {
  echo "ERROR: installed PySU2 files missing" >&2
  exit 23
}

echo
echo "===== INSTALL NEMO RECORD ====="
rm -rf "$PREFIX/share/su2-nemo"
mkdir -p "$PREFIX/share/su2-nemo"
cp -a "$ROOT/validation_checkpoints/final_patches" "$PREFIX/share/su2-nemo/"
cp -a "$ROOT/SU2_NEMO_INSTALL.md" "$PREFIX/share/su2-nemo/"

echo
echo "===== CREATE NEMO-AWARE SU2_CFD LAUNCHER ====="
rm -f "$PREFIX/bin/SU2_CFD.real"
mv "$PREFIX/bin/SU2_CFD" "$PREFIX/bin/SU2_CFD.real"

cat > "$PREFIX/bin/SU2_CFD" <<EOF
#!/usr/bin/env bash
set -e
export SU2_HOME="$ROOT"
export SU2_RUN="$PREFIX/bin"
export MPP_DIRECTORY="$PREFIX/share/mutationpp"
export MPP_DATA_DIRECTORY="$PREFIX/mpp-data"
export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$PREFIX/bin/SU2_CFD.real" "\$@"
EOF
chmod 0755 "$PREFIX/bin/SU2_CFD"

cat > "$PREFIX/bin/su2-nemo-python" <<EOF
#!/usr/bin/env bash
set -e
export SU2_HOME="$ROOT"
export SU2_RUN="$PREFIX/bin"
export PYTHONPATH="$PREFIX/bin\${PYTHONPATH:+:\$PYTHONPATH}"
export MPP_DIRECTORY="$PREFIX/share/mutationpp"
export MPP_DATA_DIRECTORY="$PREFIX/mpp-data"
export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$PYTHON_BIN" "\$@"
EOF
chmod 0755 "$PREFIX/bin/su2-nemo-python"

if [[ $SKIP_PATO_BUILD -ne 1 ]]; then
  echo
  echo "===== BUILD PATO IN ISOLATED OPENFOAM-7 ENVIRONMENT ====="
  "$ROOT/tools/build_pato.sh"
fi

[[ -x "$PATO/install/bin/PATOx" ]] || { echo "ERROR: PATOx build missing" >&2; exit 30; }
[[ -f "$PATO/install/lib/libPATOx.so" ]] || { echo "ERROR: libPATOx.so missing" >&2; exit 31; }
[[ -f "$PATO/install/lib/libSamplingUser.so" ]] || { echo "ERROR: libSamplingUser.so missing" >&2; exit 32; }

echo
echo "===== INSTALL PATO INTO SAME SU2 PREFIX ====="
rm -rf "$PREFIX/share/PATO"
mkdir -p "$PREFIX/share/PATO"
(
  cd "$PATO"
  tar --exclude='./.git' --exclude='*/__pycache__' --exclude='*.pyc' -cf - .
) | (
  cd "$PREFIX/share/PATO"
  tar -xf -
)
ln -sfn "share/PATO" "$PREFIX/PATO"

mkdir -p "$PREFIX/etc/su2" "$PREFIX/tools"
cat > "$PREFIX/etc/su2/activate_pato.sh" <<'EOF'
#!/usr/bin/env bash
_SU2_PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_SU2_PATO_ENV="${SU2_PATO_CONDA_ENV:-su2-nemo-pato}"
_SU2_PATO_CONDA_BASE="${SU2_PATO_CONDA_BASE:-$HOME/miniconda3}"
export ZSH_NAME="${ZSH_NAME:-}"
if [ ! -f "$_SU2_PATO_CONDA_BASE/etc/profile.d/conda.sh" ]; then
  echo "ERROR: conda.sh not found under $_SU2_PATO_CONDA_BASE"
  return 1 2>/dev/null || exit 1
fi
source "$_SU2_PATO_CONDA_BASE/etc/profile.d/conda.sh"
conda activate "$_SU2_PATO_ENV" || {
  echo "ERROR: could not activate $_SU2_PATO_ENV"
  return 1 2>/dev/null || exit 1
}
export PATO_DIR="$_SU2_PREFIX/share/PATO"
export BUILD_DOCUMENTATION="${BUILD_DOCUMENTATION:-no}"
source "$PATO_DIR/bashrc"
export PATH="$PATO_DIR/install/bin:$PATH"
export LD_LIBRARY_PATH="$PATO_DIR/install/lib:$PATO_DIR/src/thirdParty/mutation++/install/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ "${WM_PROJECT_VERSION:-}" != "7" ]; then
  echo "ERROR: PATO requires OpenFOAM-7"
  return 1 2>/dev/null || exit 1
fi
case "${WM_PROJECT_DIR:-}" in
  *OpenFOAM-v1706*)
    echo "ERROR: OpenFOAM-v1706 contamination detected"
    return 1 2>/dev/null || exit 1
    ;;
esac
unset _SU2_PREFIX _SU2_PATO_ENV _SU2_PATO_CONDA_BASE
EOF
chmod 0755 "$PREFIX/etc/su2/activate_pato.sh"

cat > "$PREFIX/tools/activate_pato.sh" <<EOF
#!/usr/bin/env bash
source "$PREFIX/etc/su2/activate_pato.sh"
EOF
chmod 0755 "$PREFIX/tools/activate_pato.sh"

cat > "$PREFIX/bin/PATOx" <<EOF
#!/usr/bin/env bash
set -e
source "$PREFIX/etc/su2/activate_pato.sh"
exec "$PREFIX/share/PATO/install/bin/PATOx" "\$@"
EOF
chmod 0755 "$PREFIX/bin/PATOx"

echo
echo "===== INSTALL VALIDATED SU2-PATO COUPLING ====="
[[ -f "$COUPLING/runtime/run_persistent_coupling.py" ]] || { echo "ERROR: persistent coupling runtime missing from source" >&2; exit 33; }
rm -rf "$PREFIX/share/su2-pato"
mkdir -p "$PREFIX/share/su2-pato"
(
  cd "$COUPLING"
  tar --exclude='*/__pycache__' --exclude='*.pyc' -cf - .
) | (
  cd "$PREFIX/share/su2-pato"
  tar -xf -
)
mkdir -p "$PREFIX/coupling"
ln -sfn "../share/su2-pato" "$PREFIX/coupling/SU2_PATO"
ln -sfn "share/su2-pato" "$PREFIX/SU2_PATO"
chmod 0755 "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.sh"
chmod 0755 "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.py"

cat > "$PREFIX/share/su2-pato/runtime/run_pysu2.sh" <<EOF
#!/usr/bin/env bash
set -e
export SU2_HOME="$ROOT"
export SU2_RUN="$PREFIX/bin"
export PYTHONPATH="$PREFIX/bin\${PYTHONPATH:+:\$PYTHONPATH}"
export MPP_DIRECTORY="$PREFIX/share/mutationpp"
export MPP_DATA_DIRECTORY="$PREFIX/mpp-data"
export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$PYTHON_BIN" "\$@"
EOF
chmod 0755 "$PREFIX/share/su2-pato/runtime/run_pysu2.sh"

cat > "$PREFIX/bin/su2-pato" <<EOF
#!/usr/bin/env bash
set -e
source "$PREFIX/etc/su2/activate_pato.sh"
export SU2_ROOT="$PREFIX"
export SU2_HOME="$ROOT"
export SU2_RUN="$PREFIX/bin"
export PYTHONPATH="$PREFIX/bin\${PYTHONPATH:+:\$PYTHONPATH}"
export MPP_DIRECTORY="$PREFIX/share/mutationpp"
export MPP_DATA_DIRECTORY="$PREFIX/mpp-data"
exec "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.sh" "\$@"
EOF
chmod 0755 "$PREFIX/bin/su2-pato"

cat > "$PREFIX/etc/su2/activate.sh" <<EOF
#!/usr/bin/env bash
export SU2_HOME="$ROOT"
export SU2_RUN="$PREFIX/bin"
export PATH="$PREFIX/bin:\$PATH"
export PYTHONPATH="$PREFIX/bin\${PYTHONPATH:+:\$PYTHONPATH}"
export MPP_DIRECTORY="$PREFIX/share/mutationpp"
export MPP_DATA_DIRECTORY="$PREFIX/mpp-data"
export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
chmod 0755 "$PREFIX/etc/su2/activate.sh"

if [[ $PERSIST_SHELL -eq 1 ]]; then
  BLOCK_START="# >>> SU2_UNIFIED_NEMO_PATO >>>"
  if ! grep -Fq "$BLOCK_START" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" <<EOF

$BLOCK_START
if [ -f "$PREFIX/etc/su2/activate.sh" ]; then
  source "$PREFIX/etc/su2/activate.sh"
fi
# <<< SU2_UNIFIED_NEMO_PATO <<<
EOF
  fi
fi

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
BUILD_SHA="$(sha256sum "$ROOT/build/SU2_CFD/src/SU2_CFD" | awk '{print $1}')"
INSTALL_SHA="$(sha256sum "$PREFIX/bin/SU2_CFD.real" | awk '{print $1}')"
BUILD_ID="$(readelf -n "$ROOT/build/SU2_CFD/src/SU2_CFD" | awk '/Build ID:/ {print $3; exit}')"
INSTALL_ID="$(readelf -n "$PREFIX/bin/SU2_CFD.real" | awk '/Build ID:/ {print $3; exit}')"

cat > "$PREFIX/UNIFIED_INSTALLATION" <<EOF
INSTALL_LAYOUT=OFFICIAL_SU2_STYLE
SU2_SOURCE=$ROOT
SU2_INSTALL=$PREFIX
SU2_COMMIT=$SOURCE_COMMIT
MUTATIONPP_COMMIT=$MPP_COMMIT
PATO_COMMIT=$PATO_COMMIT
SU2_CFD_BUILD_SHA256=$BUILD_SHA
SU2_CFD_INSTALLED_SHA256=$INSTALL_SHA
SU2_CFD_BUILD_ID=$BUILD_ID
SU2_CFD_INSTALLED_ID=$INSTALL_ID
MUTATIONPP_LIBRARY=$MPP_LIB
MUTATIONPP_DATA=$PREFIX/mpp-data
PATO_DIR=$PREFIX/share/PATO
COUPLING_DIR=$PREFIX/share/su2-pato
EOF

echo
echo "===== FINAL UNIFIED DOCTOR ====="
"$ROOT/scripts/doctor.sh" --prefix "$PREFIX"

echo
echo "============================================================"
echo " UNIFIED SU2 INSTALL COMPLETE"
echo "============================================================"
echo "SU2_CFD=$PREFIX/bin/SU2_CFD"
echo "PYSU2=$PREFIX/bin/su2-nemo-python"
echo "PATOx=$PREFIX/bin/PATOx"
echo "SU2_PATO=$PREFIX/bin/su2-pato"
echo "UNIFIED_SU2_NEMO_PATO_INSTALL=PASS"
