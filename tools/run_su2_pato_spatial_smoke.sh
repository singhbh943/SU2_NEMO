#!/usr/bin/env bash
# Permanent spatial SU2_NEMO -> PATO execution smoke.
#
# Usage:
#   tools/run_su2_pato_spatial_smoke.sh \
#       [source_case] [smoke_case] [log_dir]
#
# Defaults:
#   source_case = ~/SU2_PATO_CASES/AIR11_TPS_SPATIAL_TEST_ONLY
#   smoke_case  = ~/SU2_PATO_CASES/AIR11_TPS_SPATIAL_SMOKE
#   log_dir     = ~/SU2_PATO_SPATIAL_SMOKE
#
# The source case is TEST_ONLY unless it was generated from a convergence-gated
# production load. This runner verifies execution plumbing only.

set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PATO="$ROOT/externals/PATO"

SOURCE_CASE="${1:-$HOME/SU2_PATO_CASES/AIR11_TPS_SPATIAL_TEST_ONLY}"
SMOKE_CASE="${2:-$HOME/SU2_PATO_CASES/AIR11_TPS_SPATIAL_SMOKE}"
LOGROOT="${3:-$HOME/SU2_PATO_SPATIAL_SMOKE}"

echo "============================================================"
echo " SPATIAL SU2 NEMO -> PATO TWO-STEP SMOKE"
echo "============================================================"

test -d "$SOURCE_CASE" || {
    echo "ERROR: source case missing: $SOURCE_CASE"
    exit 10
}

if [ -e "$SMOKE_CASE" ]; then
    echo "ERROR: smoke destination exists; refusing overwrite: $SMOKE_CASE"
    exit 11
fi

MANIFEST="$SOURCE_CASE/SU2_PATO_SPATIAL_TEST_ONLY_MANIFEST.json"
test -f "$MANIFEST" || {
    echo "ERROR: spatial manifest missing: $MANIFEST"
    exit 12
}

python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m["status"] == "TEST_ONLY"
assert m["physical_interpretation_allowed"] is False
assert m["pato_surface_faces"] == 138
print("SPATIAL_SOURCE_CASE_TEST_ONLY=PASS")
PY

mkdir -p "$(dirname "$SMOKE_CASE")" "$LOGROOT"
cp -a "$SOURCE_CASE" "$SMOKE_CASE"

cat > "$SMOKE_CASE/SPATIAL_SMOKE_NOTICE.txt" <<'EOF'
SU2_NEMO -> PATO SPATIAL EXECUTION-PATH SMOKE RUN

TEST_ONLY. This run validates only that the nonuniform SU2-derived wall
heat-flux field is accepted by PATO and advances the material-energy solve.
No material-response value from a non-converged aerodynamic load is physical.
EOF

# No nounset: activation scripts use optional environment variables.
source "$ROOT/tools/activate_pato.sh"

PATOX="$PATO/install/bin/PATOx"
test -x "$PATOX" || {
    echo "ERROR: source-built PATOx missing: $PATOX"
    exit 20
}

command -v foamDictionary >/dev/null 2>&1

CONTROL="$SMOKE_CASE/system/controlDict"

foamDictionary "$CONTROL" -entry startFrom -set startTime
foamDictionary "$CONTROL" -entry startTime -set 0
foamDictionary "$CONTROL" -entry stopAt -set endTime
foamDictionary "$CONTROL" -entry deltaT -set 1e-12
foamDictionary "$CONTROL" -entry endTime -set 2e-12

if foamDictionary "$CONTROL" -entry writeControl >/dev/null 2>&1; then
    foamDictionary "$CONTROL" -entry writeControl -set timeStep
fi

if foamDictionary "$CONTROL" -entry writeInterval >/dev/null 2>&1; then
    foamDictionary "$CONTROL" -entry writeInterval -set 1
fi

if foamDictionary "$CONTROL" -entry adjustTimeStep >/dev/null 2>&1; then
    foamDictionary "$CONTROL" -entry adjustTimeStep -set no
fi

cd "$SMOKE_CASE"

rm -rf -- 0
cp -a origin.0 0

test -f constant/porousMat/polyMesh/points || {
    echo "ERROR: spatial mesh missing"
    exit 30
}

foamDictionary 0/porousMat/Ta >/dev/null

PATO_LOG="$LOGROOT/PATOx.log"

if timeout 180s "$PATOX" >"$PATO_LOG" 2>&1; then
    PATO_RC=0
else
    PATO_RC=$?
fi

echo "PATOX_RC=$PATO_RC"
tail -120 "$PATO_LOG"

[ "$PATO_RC" -eq 0 ] || {
    echo "ERROR: PATOx returned $PATO_RC"
    exit 40
}

TRUE_FATAL="$(
    grep -nEi \
        'FOAM FATAL ERROR|FOAM FATAL IO ERROR|Segmentation fault|Floating point exception[[:space:]]*\(core dumped\)|terminate called after throwing|Aborted[[:space:]]*\(core dumped\)' \
        "$PATO_LOG" \
        || true
)"

[ -z "$TRUE_FATAL" ] || {
    echo "ERROR: true fatal marker found:"
    echo "$TRUE_FATAL"
    exit 41
}

grep -q 'runTime = 1e-12 s' "$PATO_LOG" || exit 42
grep -q 'runTime = 2e-12 s' "$PATO_LOG" || exit 43
grep -q 'Solving for Ta' "$PATO_LOG" || exit 44

test -f "$SMOKE_CASE/2e-12/porousMat/Ta" || {
    echo "ERROR: final Ta output missing"
    exit 45
}

foamDictionary "$SMOKE_CASE/2e-12/porousMat/Ta" >/dev/null

echo
echo "============================================================"
echo "SU2_PATO_SPATIAL_TWO_STEP_SMOKE=PASS"
echo "SOURCE_BUILT_PATOX=PASS"
echo "PATO_TIME_1E-12=PASS"
echo "PATO_TIME_2E-12=PASS"
echo "PATO_TA_SOLVE=PASS"
echo "SPATIAL_NONUNIFORM_Q_ACCEPTED=YES"
echo "TEST_ONLY=YES"
echo "PHYSICAL_INTERPRETATION_ALLOWED=NO"
echo "============================================================"
