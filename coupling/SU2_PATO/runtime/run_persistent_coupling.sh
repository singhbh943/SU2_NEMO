#!/usr/bin/env bash

set -e
set -o pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

ROOT="${SU2_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

SU2_CASE="${SU2_PATO_SU2_CASE:-}"
PATO_CASE="${SU2_PATO_PATO_CASE:-}"
CFG="${SU2_PATO_CFG:-}"
WORK="${SU2_PATO_WORK:-}"

DRIVER="$ROOT/coupling/SU2_PATO/runtime/run_persistent_coupling.py"

MAP_T="$ROOT/coupling/SU2_PATO/map_pato_temperature_to_su2.py"

PYSU2_RUN="$ROOT/coupling/SU2_PATO/runtime/run_pysu2.sh"

CYCLES="${SU2_PATO_CYCLES:-3}"
Q_SCALE="${SU2_PATO_Q_SCALE:-1e-5}"
PATO_DT="${SU2_PATO_DT:-1e-12}"

usage()
{
    cat <<'USAGE'
Usage:
  run_persistent_coupling.sh \
    --su2-case PATH \
    --pato-case PATH \
    [--cfg PATH_OR_FILENAME] \
    [--work PATH] \
    [--cycles N] \
    [--q-scale VALUE] \
    [--pato-dt VALUE]

Required:
  --su2-case PATH
      SU2 CFD case directory.

  --pato-case PATH
      PATO material-response case directory.

Optional:
  --cfg PATH_OR_FILENAME
      SU2 configuration file.
      Default: <SU2_CASE>/air11_pato_coupled.cfg

  --work PATH
      Coupling runtime directory.
      Default: <SU2_CASE>/SU2_PATO_RUNTIME

  --cycles N
      Number of coupling exchanges.
      Default: 3

  --q-scale VALUE
      Heat-flux multiplier.
      Default: 1e-5

  --pato-dt VALUE
      PATO time increment.
      Default: 1e-12

Environment equivalents:
  SU2_ROOT
  SU2_PATO_SU2_CASE
  SU2_PATO_PATO_CASE
  SU2_PATO_CFG
  SU2_PATO_WORK
  SU2_PATO_CYCLES
  SU2_PATO_Q_SCALE
  SU2_PATO_DT
USAGE
}

need_value()
{
    if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        echo "ERROR: $1 requires a value" >&2
        exit 2
    fi
}

while [ "$#" -gt 0 ]
do
    case "$1" in

        --su2-case)
            need_value "$@"
            SU2_CASE="$2"
            shift 2
            ;;

        --pato-case)
            need_value "$@"
            PATO_CASE="$2"
            shift 2
            ;;

        --cfg)
            need_value "$@"
            CFG="$2"
            shift 2
            ;;

        --work)
            need_value "$@"
            WORK="$2"
            shift 2
            ;;

        --cycles)
            need_value "$@"
            CYCLES="$2"
            shift 2
            ;;

        --q-scale)
            need_value "$@"
            Q_SCALE="$2"
            shift 2
            ;;

        --pato-dt)
            need_value "$@"
            PATO_DT="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$SU2_CASE" ]; then
    echo "ERROR: SU2 case is required." >&2
    echo "Use --su2-case or SU2_PATO_SU2_CASE." >&2
    exit 2
fi

if [ -z "$PATO_CASE" ]; then
    echo "ERROR: PATO case is required." >&2
    echo "Use --pato-case or SU2_PATO_PATO_CASE." >&2
    exit 2
fi

if [ ! -d "$ROOT" ]; then
    echo "ERROR: SU2 root not found:" >&2
    echo "$ROOT" >&2
    exit 1
fi

if [ ! -d "$SU2_CASE" ]; then
    echo "ERROR: SU2 case not found:" >&2
    echo "$SU2_CASE" >&2
    exit 1
fi

if [ ! -d "$PATO_CASE" ]; then
    echo "ERROR: PATO case not found:" >&2
    echo "$PATO_CASE" >&2
    exit 1
fi

ROOT="$(readlink -f "$ROOT")"
SU2_CASE="$(readlink -f "$SU2_CASE")"
PATO_CASE="$(readlink -f "$PATO_CASE")"

if [ -z "$CFG" ]; then
    CFG="$SU2_CASE/air11_pato_coupled.cfg"
elif [[ "$CFG" != /* ]]; then
    CFG="$SU2_CASE/$CFG"
fi

if [ -z "$WORK" ]; then
    WORK="$SU2_CASE/SU2_PATO_RUNTIME"
fi

mkdir -p "$WORK"
WORK="$(readlink -f "$WORK")"

REFERENCE_PROFILE="${SU2_PATO_REFERENCE_PROFILE:-$WORK/reference_su2_wall_profile.csv}"
REFERENCE_FACES="${SU2_PATO_REFERENCE_FACES:-$WORK/reference_pato_faces.csv}"

for F in \
    "$CFG" \
    "$DRIVER" \
    "$REFERENCE_PROFILE" \
    "$REFERENCE_FACES" \
    "$MAP_T" \
    "$PYSU2_RUN"
do
    if [ ! -f "$F" ]; then
        echo "ERROR: required file missing:"
        echo "$F"
        exit 1
    fi
done

if [ ! -d "$PATO_CASE" ]; then
    echo "ERROR: permanent PATO case missing:"
    echo "$PATO_CASE"
    exit 1
fi

LATEST="$(
python3 - "$PATO_CASE" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

times = []

for d in root.iterdir():

    if not d.is_dir():
        continue

    try:
        value = float(d.name)
    except ValueError:
        continue

    times.append((value, d.name))

if not times:
    raise SystemExit(
        "ERROR: no numeric PATO state"
    )

print(max(times)[1])
PY
)"

echo "PATO_START_TIME=$LATEST"

TA="$PATO_CASE/$LATEST/porousMat/Ta"

if [ ! -f "$TA" ]; then
    echo "ERROR: latest PATO Ta missing:"
    echo "$TA"
    exit 1
fi

INITIAL_RETURN="$WORK/pato_temperature_initial.csv"

python3 "$MAP_T" \
    "$TA" \
    "$REFERENCE_FACES" \
    "$REFERENCE_PROFILE" \
    "$INITIAL_RETURN" \
    --metadata "$WORK/pato_temperature_initial.json" \
    --status TEST_ONLY

export SU2_PATO_ROOT="$ROOT"
export SU2_PATO_WORK="$WORK"
export SU2_PATO_CASE="$PATO_CASE"
export SU2_PATO_REFERENCE_PROFILE="$REFERENCE_PROFILE"

export SU2_PATO_CYCLES="$CYCLES"
export SU2_PATO_Q_SCALE="$Q_SCALE"
export SU2_PATO_DT="$PATO_DT"
export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"

echo "============================================================"
echo " SU2-PATO RUNTIME CONFIGURATION"
echo "============================================================"
echo "SU2_ROOT=$ROOT"
echo "SU2_CASE=$SU2_CASE"
echo "SU2_CFG=$CFG"
echo "PATO_CASE=$PATO_CASE"
echo "WORK=$WORK"
echo "CYCLES=$CYCLES"
echo "Q_SCALE=$Q_SCALE"
echo "PATO_DT=$PATO_DT"
echo "============================================================"

cd "$SU2_CASE"

"$PYSU2_RUN" \
    "$DRIVER" \
    "$CFG" \
    "$INITIAL_RETURN"

RC=$?

echo "PERSISTENT_COUPLING_RC=$RC"

exit "$RC"
