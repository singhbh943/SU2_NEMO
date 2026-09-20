#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

VTU="${1:-$HOME/SU2_PRODUCTION/AIR11_M23p9_PARTIAL_CAT_IMPLICIT/soln_surface.vtu}"
OUT="${2:-$HOME/SU2_PATO_COUPLING/AIR11_M23p9_PARTIAL_CAT_IMPLICIT}"
SIGN="${3:-positive-magnitude}"

mkdir -p "$OUT"

python3 "$ROOT/coupling/SU2_PATO/export_su2_wall.py" \
    "$VTU" \
    "$OUT/wall_loads.csv"

python3 "$ROOT/coupling/SU2_PATO/validate_interface.py" \
    "$OUT/wall_loads.csv"

python3 "$ROOT/coupling/SU2_PATO/write_pato_heatflux.py" \
    "$OUT/wall_loads.csv" \
    "$OUT/Ta.top.snippet" \
    --selection max-abs \
    --sign "$SIGN" \
    --initial-temperature 550

echo
echo "SU2_PATO_ONEWAY_PREPARE=PASS"
echo "WALL_CSV=$OUT/wall_loads.csv"
echo "PATO_TA_SNIPPET=$OUT/Ta.top.snippet"
echo "SIGN_POLICY=$SIGN"
