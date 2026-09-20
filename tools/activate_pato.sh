#!/usr/bin/env bash
# Source this file:
#   source tools/activate_pato.sh
#
# Intentionally do not use `set -u`; PATO/OpenFOAM activation scripts
# reference optional shell variables.

_SU2_PATO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

export PATO_DIR="$_SU2_PATO_ROOT/externals/PATO"
export BUILD_DOCUMENTATION="${BUILD_DOCUMENTATION:-no}"

source "$PATO_DIR/bashrc"

export PATH="$PATO_DIR/install/bin:$PATH"
export LD_LIBRARY_PATH="$PATO_DIR/install/lib:$PATO_DIR/src/thirdParty/mutation++/install/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

unset _SU2_PATO_ROOT
unset _SU2_PATO_ENV
unset _SU2_PATO_CONDA_BASE
