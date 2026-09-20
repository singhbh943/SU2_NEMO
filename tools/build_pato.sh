#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PATO="$ROOT/externals/PATO"
ENV="${SU2_PATO_CONDA_ENV:-su2-nemo-pato}"
CONDA_BASE="${SU2_PATO_CONDA_BASE:-$HOME/miniconda3}"

export ZSH_NAME="${ZSH_NAME:-}"

source "$CONDA_BASE/etc/profile.d/conda.sh"
conda activate "$ENV"

export PATO_DIR="$PATO"
export BUILD_DOCUMENTATION="${BUILD_DOCUMENTATION:-no}"
source "$PATO/bashrc"

[ "${WM_PROJECT_VERSION:-}" = "7" ] || {
    echo "ERROR: PATO requires the isolated OpenFOAM-7 environment"
    exit 10
}

case "${WM_PROJECT_DIR:-}" in
    *OpenFOAM-v1706*)
        echo "ERROR: OpenFOAM-v1706 leaked into PATO build"
        exit 11
        ;;
esac

SYSROOT_VER="$(conda list sysroot_linux-64 | awk '$1=="sysroot_linux-64"{print $2}')"
KHEAD_VER="$(conda list kernel-headers_linux-64 | awk '$1=="kernel-headers_linux-64"{print $2}')"

[ "$SYSROOT_VER" = "2.17" ] || {
    echo "ERROR: expected sysroot_linux-64=2.17, got $SYSROOT_VER"
    exit 12
}

[ "$KHEAD_VER" = "3.10.0" ] || {
    echo "ERROR: expected kernel-headers_linux-64=3.10.0, got $KHEAD_VER"
    exit 13
}

cd "$PATO"
./Allwmake

echo "PATO_BUILD=PASS"
