#!/usr/bin/env bash
set -eo pipefail

ENV="${SU2_PATO_CONDA_ENV:-su2-nemo-pato}"
CONDA_BASE="${SU2_PATO_CONDA_BASE:-$HOME/miniconda3}"

export ZSH_NAME="${ZSH_NAME:-}"

source "$CONDA_BASE/etc/profile.d/conda.sh"

if ! conda env list | awk '{print $1}' | grep -Fxq "$ENV"; then
    conda create -y \
        -n "$ENV" \
        -c conda-forge \
        -c pato.devel \
        --strict-channel-priority \
        pato=3.1
fi

conda activate "$ENV"

# PATO 3.1 package pins GCC/binutils 11.2/2.36.1. On newer Conda
# installations the solver may otherwise select a newer glibc sysroot
# containing RELR sections that GNU ld 2.36 cannot read.
conda install -y \
    -n "$ENV" \
    -c conda-forge \
    -c pato.devel \
    --strict-channel-priority \
    'pato=3.1' \
    'gcc_impl_linux-64=11.2.0' \
    'gxx_impl_linux-64=11.2.0' \
    'binutils_impl_linux-64=2.36.1' \
    'ld_impl_linux-64=2.36.1' \
    'sysroot_linux-64=2.17' \
    'kernel-headers_linux-64=3.10.0'

PINFILE="$CONDA_PREFIX/conda-meta/pinned"
touch "$PINFILE"

sed -i \
    -e '/^sysroot_linux-64[[:space:]]/d' \
    -e '/^kernel-headers_linux-64[[:space:]]/d' \
    "$PINFILE"

echo 'sysroot_linux-64 2.17.*' >> "$PINFILE"
echo 'kernel-headers_linux-64 3.10.0.*' >> "$PINFILE"

echo "PATO_ENVIRONMENT_INSTALL=PASS"
