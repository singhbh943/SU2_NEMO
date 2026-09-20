#!/usr/bin/env bash
# Prepare a provenance-locked SU2_NEMO wall-load package for PATO.
#
# Usage:
#   tools/prepare_su2_pato_converged_load.sh \
#       <su2_case_dir> \
#       <convergence_log> \
#       <output_dir> \
#       [initial_wall_temperature_K]
#
# This tool does NOT run SU2 or PATO.
#
# Policy:
#   - known non-convergence evidence => reject
#   - no explicit positive convergence evidence => reject
#   - only a positively verified run may produce a CONVERGED load package
#
# Positive evidence currently accepted:
#   - "Convergence criterion satisfied"
#   - "Convergence criteria satisfied"
#   - "Convergence achieved"
#   - a final SU2 convergence-summary data row whose Converged column is Yes
#
# Known rejection evidence includes:
#   - "Maximum number of iterations reached ... before convergence"
#   - explicit final convergence-summary rows ending in No

set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

CASE="${1:?usage: $0 <su2_case_dir> <convergence_log> <output_dir> [initial_wall_temperature_K]}"
LOG="${2:?usage: $0 <su2_case_dir> <convergence_log> <output_dir> [initial_wall_temperature_K]}"
OUT="${3:?usage: $0 <su2_case_dir> <convergence_log> <output_dir> [initial_wall_temperature_K]}"
TWALL="${4:-550}"

VTU="$CASE/soln_surface.vtu"
EXPORTER="$ROOT/coupling/SU2_PATO/export_su2_wall.py"
VALIDATOR="$ROOT/coupling/SU2_PATO/validate_interface.py"
WRITER="$ROOT/coupling/SU2_PATO/write_pato_heatflux.py"

echo "============================================================"
echo " SU2_NEMO -> PATO CONVERGED LOAD PREPARATION"
echo "============================================================"
echo "CASE=$CASE"
echo "LOG=$LOG"
echo "VTU=$VTU"
echo "OUT=$OUT"
echo "INITIAL_WALL_TEMPERATURE_K=$TWALL"

test -d "$CASE" || {
    echo "ERROR: SU2 case directory not found: $CASE"
    exit 10
}

test -f "$LOG" || {
    echo "ERROR: convergence log not found: $LOG"
    exit 11
}

test -f "$VTU" || {
    echo "ERROR: surface VTU not found: $VTU"
    exit 12
}

test -f "$EXPORTER"
test -f "$VALIDATOR"
test -f "$WRITER"

echo
echo "===== CONVERGENCE GATE ====="

GATE_JSON="$(
    python3 - "$LOG" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(errors="replace")
lines = text.splitlines()

negative_patterns = [
    r"Maximum number of iterations reached.*before convergence",
    r"did not converge",
    r"not converged",
]

negative_hits = []
for pat in negative_patterns:
    m = re.search(pat, text, flags=re.I | re.S)
    if m:
        negative_hits.append(m.group(0)[:300])

positive_hits = []
for pat in (
    r"Convergence criterion satisfied",
    r"Convergence criteria satisfied",
    r"Convergence achieved",
):
    m = re.search(pat, text, flags=re.I)
    if m:
        positive_hits.append(m.group(0))

# Parse the LAST convergence-summary block if present.
summary_start = None
for i, line in enumerate(lines):
    if "Convergence Field" in line and "Converged" in line:
        summary_start = i

summary_rows = []
if summary_start is not None:
    for line in lines[summary_start + 1:]:
        if "File Writing Summary" in line or "Finalizing Solver" in line:
            break
        if not line.lstrip().startswith("|"):
            continue
        cells = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(cells) >= 4 and cells[-1] in {"Yes", "No"}:
            summary_rows.append(cells)

summary_all_yes = bool(summary_rows) and all(row[-1] == "Yes" for row in summary_rows)
summary_any_no = any(row[-1] == "No" for row in summary_rows)

if summary_all_yes:
    positive_hits.append("final convergence summary: all criteria Yes")

if summary_any_no:
    negative_hits.append("final convergence summary contains No")

if negative_hits:
    status = "REJECTED"
    reason = "negative convergence evidence"
elif not positive_hits:
    status = "UNVERIFIED"
    reason = "no explicit positive convergence evidence"
else:
    status = "ACCEPTED"
    reason = "explicit positive convergence evidence"

print(json.dumps({
    "status": status,
    "reason": reason,
    "positive_evidence": positive_hits,
    "negative_evidence": negative_hits,
    "summary_rows": summary_rows,
}, separators=(",", ":")))
PY
)"

echo "$GATE_JSON" | python3 -m json.tool

GATE_STATUS="$(
    python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["status"])' \
        <<<"$GATE_JSON"
)"

echo "CONVERGENCE_GATE=$GATE_STATUS"

if [ "$GATE_STATUS" = "REJECTED" ]; then
    echo "ERROR: SU2 run is explicitly non-converged; no PATO load package created."
    exit 20
fi

if [ "$GATE_STATUS" = "UNVERIFIED" ]; then
    echo "ERROR: convergence could not be positively verified; no PATO load package created."
    exit 21
fi

echo "CONVERGENCE_GATE=ACCEPTED"

if [ -e "$OUT" ]; then
    echo "ERROR: output directory already exists; refusing overwrite: $OUT"
    exit 22
fi

mkdir -p "$OUT"

echo
echo "===== EXPORT WALL DATA ====="

python3 "$EXPORTER" \
    "$VTU" \
    "$OUT/wall_loads.csv" \
    2>&1 | tee "$OUT/export.log"

echo
echo "===== VALIDATE WALL DATA ====="

python3 "$VALIDATOR" \
    "$OUT/wall_loads.csv" \
    2>&1 | tee "$OUT/validate.log"

echo
echo "===== CREATE 1-D STAGNATION-POINT PATO LOAD SNIPPET ====="

python3 "$WRITER" \
    "$OUT/wall_loads.csv" \
    "$OUT/Ta.top.snippet" \
    --selection max-abs \
    --sign positive-magnitude \
    --initial-temperature "$TWALL" \
    2>&1 | tee "$OUT/write_pato.log"

echo
echo "===== WRITE PROVENANCE ====="

python3 - "$CASE" "$LOG" "$VTU" "$OUT" "$GATE_JSON" "$TWALL" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

case = Path(sys.argv[1]).resolve()
log = Path(sys.argv[2]).resolve()
vtu = Path(sys.argv[3]).resolve()
out = Path(sys.argv[4]).resolve()
gate = json.loads(sys.argv[5])
twall = float(sys.argv[6])

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

meta = json.loads((out / "Ta.top.snippet.json").read_text())

manifest = {
    "status": "CONVERGED_LOAD",
    "physical_interpretation_allowed": True,
    "scope": (
        "SU2 convergence-gated aerodynamic wall-load package. "
        "The generated PATO snippet is a 1-D maximum-|q| point load, "
        "not a full spatial face-to-face coupling."
    ),
    "su2_case": str(case),
    "convergence_log": str(log),
    "surface_vtu": str(vtu),
    "convergence_gate": gate,
    "sha256": {
        "convergence_log": sha256(log),
        "surface_vtu": sha256(vtu),
        "wall_loads_csv": sha256(out / "wall_loads.csv"),
    },
    "initial_wall_temperature_K": twall,
    "selected_pato_load": meta,
}

(out / "SU2_PATO_CONVERGED_LOAD_MANIFEST.json").write_text(
    json.dumps(manifest, indent=2) + "\n"
)

print("MANIFEST=" + str(out / "SU2_PATO_CONVERGED_LOAD_MANIFEST.json"))
print("VTU_SHA256=" + manifest["sha256"]["surface_vtu"])
print("LOG_SHA256=" + manifest["sha256"]["convergence_log"])
PY

echo
echo "============================================================"
echo "SU2_PATO_CONVERGED_LOAD_PREPARATION=PASS"
echo "CONVERGENCE_GATE=ACCEPTED"
echo "LOAD_STATUS=CONVERGED_LOAD"
echo "PHYSICAL_INTERPRETATION_ALLOWED=YES"
echo "PATO_LOAD_SCOPE=1D_MAX_ABS_POINT"
echo "NO_SU2_RUN=YES"
echo "NO_PATO_RUN=YES"
echo "============================================================"
