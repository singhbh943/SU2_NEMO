#!/usr/bin/env bash
# SU2_NEMO -> PATO execution-path smoke run.
#
# This is a TEST_ONLY execution check. It must not be used to claim a
# physically validated TPS result when the source SU2 load is non-converged.
#
# Usage:
#   tools/run_su2_pato_smoke.sh [source_case] [smoke_case] [log_dir]
#
# Defaults:
#   source_case = ~/SU2_PATO_CASES/AIR11_TPS_TEST_ONLY
#   smoke_case  = ~/SU2_PATO_CASES/AIR11_TPS_SMOKE
#   log_dir     = ~/SU2_PATO_SMOKE
#
# The destination smoke case must not already exist.

set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PATO="$ROOT/externals/PATO"

SOURCE_CASE="${1:-$HOME/SU2_PATO_CASES/AIR11_TPS_TEST_ONLY}"
SMOKE_CASE="${2:-$HOME/SU2_PATO_CASES/AIR11_TPS_SMOKE}"
LOGROOT="${3:-$HOME/SU2_PATO_SMOKE}"

echo "============================================================"
echo " SU2 NEMO -> PATO EXECUTION-PATH SMOKE RUN"
echo " TEST_ONLY -- TWO TINY TIMESTEPS"
echo "============================================================"

cd "$ROOT"

test -d "$SOURCE_CASE" || {
    echo "ERROR: source case missing: $SOURCE_CASE"
    exit 10
}

test -f "$SOURCE_CASE/SU2_PATO_TEST_ONLY_MANIFEST.json" || {
    echo "ERROR: TEST_ONLY manifest missing"
    exit 11
}

python3 - "$SOURCE_CASE/SU2_PATO_TEST_ONLY_MANIFEST.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m["status"] == "TEST_ONLY"
assert m["physical_interpretation_allowed"] is False
print("SOURCE_CASE_TEST_ONLY=PASS")
PY

if [ -e "$SMOKE_CASE" ]; then
    echo "ERROR: destination already exists: $SMOKE_CASE"
    echo "Choose a new smoke-case path; existing results are never overwritten."
    exit 12
fi

mkdir -p "$(dirname "$SMOKE_CASE")" "$LOGROOT"
cp -a "$SOURCE_CASE" "$SMOKE_CASE"

cat > "$SMOKE_CASE/SMOKE_RUN_NOTICE.txt" <<'EOF'
SU2_NEMO -> PATO EXECUTION-PATH SMOKE RUN

TEST_ONLY. The current aerodynamic load may come from a non-converged
SU2 development run. This case verifies execution plumbing only.

No temperature, pyrolysis, recession, or material response from this
case is a physical validation result.
EOF

# No nounset: PATO/OpenFOAM activation uses optional environment variables.
source "$ROOT/tools/activate_pato.sh"

PATOX="$PATO/install/bin/PATOx"
test -x "$PATOX" || {
    echo "ERROR: source-built PATOx missing: $PATOX"
    exit 20
}

command -v blockMesh >/dev/null
command -v foamDictionary >/dev/null

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
rm -rf -- constant/porousMat/polyMesh

BLOCK_LOG="$LOGROOT/blockMesh.log"
if blockMesh -region porousMat >"$BLOCK_LOG" 2>&1; then
    BLOCK_RC=0
else
    BLOCK_RC=$?
fi

echo "BLOCKMESH_RC=$BLOCK_RC"
tail -60 "$BLOCK_LOG"

[ "$BLOCK_RC" -eq 0 ] || exit 30
test -f constant/porousMat/polyMesh/points || exit 31

PATO_LOG="$LOGROOT/PATOx.log"

if timeout 180s "$PATOX" >"$PATO_LOG" 2>&1; then
    PATO_RC=0
else
    PATO_RC=$?
fi

echo "PATOX_RC=$PATO_RC"
tail -100 "$PATO_LOG"

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

grep -q 'runTime = 1e-12 s' "$PATO_LOG" || {
    echo "ERROR: first timestep missing"
    exit 42
}

grep -q 'runTime = 2e-12 s' "$PATO_LOG" || {
    echo "ERROR: second timestep missing"
    exit 43
}

grep -q 'Solving for Ta' "$PATO_LOG" || {
    echo "ERROR: Ta solve missing"
    exit 44
}

Q_LINE="$(
    grep -n \
        'q[[:space:]]*uniform' \
        "$SMOKE_CASE/0/porousMat/Ta" \
        | sed -n '1p'
)"

[ -n "$Q_LINE" ] || {
    echo "ERROR: heat-flux boundary not present"
    exit 45
}

echo
echo "============================================================"
echo "SU2_PATO_EXECUTION_SMOKE=PASS"
echo "SOURCE_BUILT_PATOX=PASS"
echo "BLOCKMESH=PASS"
echo "PATOX_EXECUTION=PASS"
echo "SU2_TEST_HEATFLUX_REACHED_PATO_CASE=YES"
echo "TIMESTEP=1e-12"
echo "REQUESTED_STEPS=2"
echo "TEST_ONLY=YES"
echo "PHYSICAL_INTERPRETATION_ALLOWED=NO"
echo "============================================================"
