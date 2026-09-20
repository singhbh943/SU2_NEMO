#!/usr/bin/env bash

_THIS="${BASH_SOURCE[0]}"
_REAL="$(readlink -f "$_THIS")"
_ROOT="$(cd "$(dirname "$_REAL")" && pwd)"

export SU2_NEMO_ROOT="$_ROOT"

if [ -x "$SU2_NEMO_ROOT/libexec/SU2_CFD.real" ]; then
  export SU2_HOME="$SU2_NEMO_ROOT"
  export SU2_RUN="$SU2_NEMO_ROOT/bin"
  export MPP_DIRECTORY="$SU2_NEMO_ROOT/share/mutationpp"
  export MPP_DATA_DIRECTORY="$SU2_NEMO_ROOT/share/mutationpp/data"
  export LD_LIBRARY_PATH="$SU2_NEMO_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
elif [ -x "$SU2_NEMO_ROOT/build/SU2_CFD/src/SU2_CFD" ]; then
  export SU2_HOME="$SU2_NEMO_ROOT"
  export SU2_RUN="$SU2_NEMO_ROOT/build/SU2_CFD/src"
  export MPP_DIRECTORY="$SU2_NEMO_ROOT/subprojects/Mutationpp"
  export MPP_DATA_DIRECTORY="$SU2_NEMO_ROOT/subprojects/Mutationpp/data"
  export LD_LIBRARY_PATH="$SU2_NEMO_ROOT/build/subprojects/Mutationpp${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
  echo "ERROR: no SU2 NEMO executable was found under $SU2_NEMO_ROOT" >&2
  return 1 2>/dev/null || exit 1
fi

export PATH="$SU2_RUN:$PATH"
export OMPI_MCA_osc="${OMPI_MCA_osc:-pt2pt}"
unset _THIS _REAL _ROOT
