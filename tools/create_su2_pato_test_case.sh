#!/usr/bin/env bash
# Generate a PATO TEST_ONLY material-response case from the pinned
# PATO 3.1 PureConduction tutorial and an exported SU2 wall-load package.
#
# Usage:
#   tools/create_su2_pato_test_case.sh \
#       <wall_load_dir> \
#       <destination_case>
#
# This tool DOES NOT run PATOx.

set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PATO="$ROOT/externals/PATO"

LOAD_DIR="${1:?usage: $0 <wall_load_dir> <destination_case>}"
DST="${2:?usage: $0 <wall_load_dir> <destination_case>}"

BASE="$PATO/tutorials/1D/PureConduction"
LOAD_CSV="$LOAD_DIR/wall_loads.csv"
LOAD_META="$LOAD_DIR/Ta.top.snippet.json"

test -d "$BASE" || {
    echo "ERROR: missing base tutorial: $BASE"
    exit 10
}

test -f "$LOAD_CSV" || {
    echo "ERROR: missing $LOAD_CSV"
    exit 11
}

test -f "$LOAD_META" || {
    echo "ERROR: missing $LOAD_META"
    exit 12
}

if [ -e "$DST" ]; then
    echo "ERROR: destination exists; refusing to overwrite: $DST"
    exit 13
fi

TA_CANDIDATES="$(
    find "$BASE" \
        -type f \
        -path '*/origin.0/*/Ta' \
        -print
)"

TA_COUNT="$(printf '%s\n' "$TA_CANDIDATES" | sed '/^$/d' | wc -l)"

[ "$TA_COUNT" -eq 1 ] || {
    echo "ERROR: expected exactly one origin.0/*/Ta in $BASE"
    printf '%s\n' "$TA_CANDIDATES"
    exit 14
}

BASE_TA="$(printf '%s\n' "$TA_CANDIDATES" | sed '/^$/d')"
REL_TA="${BASE_TA#"$BASE"/}"

mkdir -p "$(dirname "$DST")"
cp -a "$BASE" "$DST"

TA="$DST/$REL_TA"

python3 - "$TA" "$LOAD_META" <<'PY'
import json
import re
import sys
from pathlib import Path

ta_path = Path(sys.argv[1])
meta_path = Path(sys.argv[2])

meta = json.loads(meta_path.read_text())

q = float(meta["pato_q_W_m2"])
sign_policy = str(meta["sign_policy"])
source_point = meta.get("source_point_id")
source_xyz = meta.get("source_xyz")
source_pressure = meta.get("source_pressure_Pa")
source_ttr = meta.get("source_temperature_tr_K")
source_tve = meta.get("source_temperature_ve_K")
source_q = meta.get("su2_heat_flux_raw_W_m2")

text = ta_path.read_text()

def matching_brace(s: str, open_i: int) -> int:
    depth = 0
    in_line = False
    in_block = False
    in_string = False
    quote = ""
    i = open_i

    while i < len(s):
        c = s[i]
        n = s[i + 1] if i + 1 < len(s) else ""

        if in_line:
            if c == "\n":
                in_line = False
            i += 1
            continue

        if in_block:
            if c == "*" and n == "/":
                in_block = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                in_string = False
            i += 1
            continue

        if c == "/" and n == "/":
            in_line = True
            i += 2
            continue

        if c == "/" and n == "*":
            in_block = True
            i += 2
            continue

        if c in ("'", '"'):
            in_string = True
            quote = c
            i += 1
            continue

        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i

        i += 1

    raise RuntimeError("unbalanced braces")

m = re.search(r"\bboundaryField\b\s*\{", text)
if not m:
    raise SystemExit("ERROR: boundaryField block not found")

bf_open = text.find("{", m.start())
bf_close = matching_brace(text, bf_open)
bf = text[bf_open + 1 : bf_close]

pm = re.search(r"(?m)^([ \t]*)top[ \t]*\s*\{", bf)
if not pm:
    raise SystemExit("ERROR: top patch not found in boundaryField")

indent = pm.group(1)
patch_open_rel = bf.find("{", pm.start())
patch_close_rel = matching_brace(bf, patch_open_rel)

patch_start_rel = pm.start()
patch_end_rel = patch_close_rel + 1

patch_start = bf_open + 1 + patch_start_rel
patch_end = bf_open + 1 + patch_end_rel

# This is intentionally a TEST_ONLY direct heat-load boundary.
# kappa=1 is retained explicitly because the PATO BC itself uses
# refGrad=(q+qr)/kappa. It is not claimed to be a physical TPS conductivity.
new_patch = f"""{indent}top
{indent}{{
{indent}    type            basicWallHeatFluxTemperature;
{indent}    mode            flux;
{indent}    q               uniform {q:.12e};
{indent}    kappa           1.000000000000e+00;
{indent}    emissivity      0.000000000000e+00;
{indent}    value           uniform 5.500000000000e+02;
{indent}}}"""

banner = (
    "// -------------------------------------------------------------------------\n"
    "// SU2_NEMO -> PATO TEST_ONLY CASE\n"
    "// Source SU2 solution is NOT converged and MUST NOT be used for physics.\n"
    f"// Source point: {source_point}, xyz={source_xyz}\n"
    f"// SU2 pressure [Pa]: {source_pressure}\n"
    f"// SU2 Ttr [K]: {source_ttr}; SU2 Tve [K]: {source_tve}\n"
    f"// SU2 raw Heat_Flux: {source_q}; sign policy: {sign_policy}\n"
    f"// Imposed PATO q [W/m2]: {q:.12e}\n"
    "// Purpose: software/case plumbing only.\n"
    "// -------------------------------------------------------------------------\n"
)

text = banner + text[:patch_start] + new_patch + text[patch_end:]
ta_path.write_text(text)
PY

cp "$LOAD_CSV" "$DST/SU2_wall_loads_TEST_ONLY.csv"
cp "$LOAD_META" "$DST/SU2_wall_load_TEST_ONLY.json"

PATO_BASE="$(git -C "$PATO" rev-parse HEAD)"
COUPLING_HEAD="$(git -C "$ROOT" rev-parse HEAD)"

python3 - "$DST" "$LOAD_META" "$PATO_BASE" "$COUPLING_HEAD" "$REL_TA" <<'PY'
import json
import sys
from pathlib import Path

dst = Path(sys.argv[1])
src_meta = json.loads(Path(sys.argv[2]).read_text())

manifest = {
    "status": "TEST_ONLY",
    "physical_interpretation_allowed": False,
    "reason": "Source SU2 AIR11 solution did not converge; current load is for coupling verification only.",
    "base_case": "externals/PATO/tutorials/1D/PureConduction",
    "pato_commit": sys.argv[3],
    "su2_nemo_coupling_commit": sys.argv[4],
    "temperature_field": sys.argv[5],
    "source_load_metadata": src_meta,
}

(dst / "SU2_PATO_TEST_ONLY_MANIFEST.json").write_text(
    json.dumps(manifest, indent=2) + "\n"
)
PY

cat > "$DST/README_SU2_PATO_TEST_ONLY.md" <<'README'
# SU2 NEMO -> PATO TEST_ONLY material-response case

**Status: TEST_ONLY**

This working case is generated from PATO's pinned `1D/PureConduction`
tutorial. The aerodynamic wall load comes from the current AIR11 SU2
NEMO test solution, which reached its iteration limit before convergence.

Therefore:

- do not publish temperatures from this case as physical results;
- do not publish recession/pyrolysis results from this case;
- do not use the current heat flux as a validated flight load;
- use this case only to verify SU2 -> interface -> PATO case plumbing.

The top temperature patch is replaced by:

```text
type  basicWallHeatFluxTemperature;
mode  flux;
q     uniform <SU2 test heat-flux magnitude>;
```

The sign policy and exact source point are stored in
`SU2_wall_load_TEST_ONLY.json`.

The initial coupling uses the maximum absolute SU2 wall heat-flux point.
A converged SU2 solution can later replace the load package without
changing the interface architecture.

This first case does not yet implement:
- spatial face-to-face mapping,
- B-prime coupling,
- blowing feedback,
- wall-temperature feedback to SU2,
- recession geometry feedback.
README

echo "CASE=$DST"
echo "TA=$TA"
echo "PATO_BASE=$PATO_BASE"
echo "COUPLING_HEAD=$COUPLING_HEAD"
echo "PATO_TEST_CASE_CREATE=PASS"
