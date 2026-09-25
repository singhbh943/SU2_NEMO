#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PREFIX="${SU2_NEMO_PREFIX:-$HOME/SU2_NEMO}"

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

PREFIX="$(python3 - "$PREFIX" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"

RUNTIME="$PREFIX/current"
[[ -d "$RUNTIME" ]] || RUNTIME="$PREFIX/runtime"

fail=0

pass_file() {
  if [[ -f "$1" ]]; then echo "PASS file $1"; else echo "FAIL missing $1"; fail=1; fi
}
pass_exec() {
  if [[ -x "$1" ]]; then echo "PASS executable $1"; else echo "FAIL executable $1"; fail=1; fi
}

echo "============================================================"
echo " SU2 NEMO DOCTOR"
echo "============================================================"
echo "SOURCE=$ROOT"
echo "PREFIX=$PREFIX"
echo "RUNTIME=$RUNTIME"

pass_exec "$RUNTIME/bin/SU2_CFD"
pass_exec "$RUNTIME/libexec/SU2_CFD.real"
pass_exec "$RUNTIME/bin/su2-nemo-python"
pass_exec "$RUNTIME/verify_runtime.sh"

pass_file "$RUNTIME/VERSION"
pass_file "$RUNTIME/share/mutationpp/data/mixtures/air_5.xml"
pass_file "$RUNTIME/share/mutationpp/data/mixtures/air_7.xml"
pass_file "$RUNTIME/share/mutationpp/data/mixtures/air_11.xml"
pass_file "$RUNTIME/share/mutationpp/data/mechanisms/air5_Park.xml"
pass_file "$RUNTIME/share/mutationpp/data/mechanisms/air7_Park.xml"
pass_file "$RUNTIME/share/mutationpp/data/mechanisms/air11_Park.xml"

shopt -s nullglob
libs=("$RUNTIME"/lib/libmutation*.so*)
shopt -u nullglob
if [[ ${#libs[@]} -gt 0 ]]; then
  echo "PASS Mutation++ shared library"
else
  echo "FAIL Mutation++ shared library"
  fail=1
fi

if [[ -x "$RUNTIME/libexec/SU2_CFD.real" ]]; then
  LDD_OUT="$(LD_LIBRARY_PATH="$RUNTIME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$RUNTIME/libexec/SU2_CFD.real")"
  echo "$LDD_OUT"
  if echo "$LDD_OUT" | grep -Fq 'not found'; then
    echo "FAIL unresolved shared library"
    fail=1
  else
    echo "PASS shared libraries"
  fi
fi

if [[ -x "$RUNTIME/verify_runtime.sh" ]]; then
  "$RUNTIME/verify_runtime.sh" || fail=1
fi

if [[ -d "$RUNTIME/python" ]]; then
  if PYTHONPATH="$RUNTIME/python${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import pysu2
print("PASS PySU2 import")
PY
  then
    :
  else
    echo "FAIL PySU2 import"
    fail=1
  fi
else
  echo "FAIL PySU2 runtime missing"
  fail=1
fi

if [[ -x "$ROOT/verify_su2_nemo.sh" ]]; then
  "$ROOT/verify_su2_nemo.sh" "$ROOT" "$RUNTIME" || fail=1
fi

if [[ $fail -eq 0 ]]; then
  echo "SU2_NEMO_DOCTOR=PASS"
else
  echo "SU2_NEMO_DOCTOR=FAIL"
fi
exit "$fail"
