#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DEFAULT_PREFIX="$(cd "$ROOT/.." && pwd)/SU2_install"
PREFIX="${SU2_INSTALL_PREFIX:-$DEFAULT_PREFIX}"

usage() {
  echo "Usage: ./scripts/doctor.sh [--prefix PATH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

PREFIX="$(readlink -f "$PREFIX")"
fail=0

pass_file() { if [[ -f "$1" ]]; then echo "PASS file $1"; else echo "FAIL missing $1"; fail=1; fi; }
pass_exec() { if [[ -x "$1" ]]; then echo "PASS executable $1"; else echo "FAIL executable $1"; fail=1; fi; }

echo "============================================================"
echo " UNIFIED SU2 + NEMO + PATO DOCTOR"
echo "============================================================"
echo "SOURCE=$ROOT"
echo "PREFIX=$PREFIX"

for exe in SU2_CFD SU2_CFD.real SU2_DEF SU2_DOT SU2_GEO SU2_SOL su2-nemo-python PATOx su2-pato; do
  pass_exec "$PREFIX/bin/$exe"
done

pass_file "$PREFIX/bin/pysu2.py"
pass_file "$PREFIX/bin/_pysu2.so"
pass_file "$PREFIX/lib/libmutation__.so"
pass_file "$PREFIX/mpp-data/mixtures/air_5.xml"
pass_file "$PREFIX/mpp-data/mixtures/air_7.xml"
pass_file "$PREFIX/mpp-data/mixtures/air_11.xml"
pass_file "$PREFIX/mpp-data/mechanisms/air5_Park.xml"
pass_file "$PREFIX/mpp-data/mechanisms/air7_Park.xml"
pass_file "$PREFIX/mpp-data/mechanisms/air11_Park.xml"
pass_file "$PREFIX/etc/su2/activate.sh"
pass_file "$PREFIX/etc/su2/activate_pato.sh"
pass_file "$PREFIX/UNIFIED_INSTALLATION"
pass_file "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.py"
pass_file "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.sh"
pass_file "$PREFIX/share/su2-pato/runtime/run_pysu2.sh"

if [[ -x "$PREFIX/bin/SU2_CFD.real" ]]; then
  SU2_LDD="$(LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$PREFIX/bin/SU2_CFD.real")"
  echo "$SU2_LDD"
  echo "$SU2_LDD" | grep -F "$PREFIX/lib/libmutation__.so" >/dev/null || { echo "FAIL SU2_CFD not loading installed Mutation++"; fail=1; }
  if echo "$SU2_LDD" | grep -Fq 'not found'; then echo "FAIL unresolved SU2_CFD library"; fail=1; else echo "PASS SU2_CFD shared libraries"; fi
fi

if [[ -x "$PREFIX/bin/su2-nemo-python" ]]; then
  if "$PREFIX/bin/su2-nemo-python" - <<'PY'
import pysu2
print("PASS PySU2 import", pysu2.__file__)
PY
  then :; else echo "FAIL PySU2 import"; fail=1; fi
fi

if [[ -x "$PREFIX/etc/su2/activate_pato.sh" && -x "$PREFIX/share/PATO/install/bin/PATOx" ]]; then
  if (
    set +u
    source "$PREFIX/etc/su2/activate_pato.sh"
    [[ "${WM_PROJECT_VERSION:-}" == "7" ]]
    case "${WM_PROJECT_DIR:-}" in *OpenFOAM-v1706*) exit 41;; esac
    OUT="$(ldd "$PREFIX/share/PATO/install/bin/PATOx")"
    echo "$OUT"
    ! echo "$OUT" | grep -Fq 'not found'
  ); then
    echo "PASS PATO OpenFOAM-7 runtime"
  else
    echo "FAIL PATO runtime"
    fail=1
  fi
fi

python3 -m py_compile   "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.py"   "$PREFIX/share/su2-pato/map_su2_profile_to_pato_faces.py"   "$PREFIX/share/su2-pato/map_pato_temperature_to_su2.py" || fail=1
bash -n "$PREFIX/share/su2-pato/runtime/run_persistent_coupling.sh" || fail=1
bash -n "$PREFIX/share/su2-pato/runtime/run_pysu2.sh" || fail=1

if [[ -f "$PREFIX/UNIFIED_INSTALLATION" ]]; then
  cat "$PREFIX/UNIFIED_INSTALLATION"
fi

if [[ $fail -eq 0 ]]; then
  echo "SU2_UNIFIED_DOCTOR=PASS"
  echo "SU2_STANDARD=PASS"
  echo "SU2_NEMO=PASS"
  echo "MUTATIONPP=PASS"
  echo "PYSU2=PASS"
  echo "PATO=PASS"
  echo "SU2_PATO_COUPLING=PASS"
else
  echo "SU2_UNIFIED_DOCTOR=FAIL"
fi
exit "$fail"
