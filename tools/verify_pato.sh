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
export BUILD_DOCUMENTATION=no
source "$PATO/bashrc"

echo "PATO_HEAD=$(git -C "$PATO" rev-parse HEAD)"
echo "OPENFOAM_VERSION=${WM_PROJECT_VERSION:-UNSET}"
echo "OPENFOAM_DIR=${WM_PROJECT_DIR:-UNSET}"

[ "${WM_PROJECT_VERSION:-}" = "7" ]

for F in \
    "$PATO/install/bin/PATOx" \
    "$PATO/install/bin/PATOxs" \
    "$PATO/install/bin/heatTransfer" \
    "$PATO/install/bin/heatTransfer2T" \
    "$PATO/install/bin/solidDisplacementPyrolysisFoam" \
    "$PATO/install/lib/libPATOx.so" \
    "$PATO/install/lib/libSamplingUser.so" \
    "$PATO/src/thirdParty/mutation++/install/lib/libmutation++.so"
do
    test -e "$F"
    echo "FOUND=$F"
done

for B in \
    PATOx \
    PATOxs \
    heatTransfer \
    heatTransfer2T \
    solidDisplacementPyrolysisFoam
do
    BIN="$PATO/install/bin/$B"

    LDD="$(ldd "$BIN")"

    if echo "$LDD" | grep -Fq 'not found'; then
        echo "$LDD"
        echo "ERROR: unresolved library in $B"
        exit 20
    fi
done

echo "PATO_RUNTIME_LINKAGE=PASS"
echo "PATO_VERIFY=PASS"
