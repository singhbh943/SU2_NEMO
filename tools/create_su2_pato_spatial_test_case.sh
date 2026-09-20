#!/usr/bin/env bash
# Generate a TEST_ONLY spatial PATO strip driven by the topology-ordered
# SU2 wall heat-flux distribution.
#
# Usage:
#   tools/create_su2_pato_spatial_test_case.sh \
#       <su2_surface_vtu> \
#       <destination_case> \
#       [number_of_surface_faces]
#
# No PATOx execution is performed here.

set -eo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PATO="$ROOT/externals/PATO"
BASE="$PATO/tutorials/1D/PureConduction"

VTU="${1:?usage: $0 <su2_surface_vtu> <destination_case> [number_of_surface_faces]}"
DST="${2:?usage: $0 <su2_surface_vtu> <destination_case> [number_of_surface_faces]}"
NFACES="${3:-138}"

PROFILE_TOOL="$ROOT/coupling/SU2_PATO/extract_su2_wall_profile.py"
MAP_TOOL="$ROOT/coupling/SU2_PATO/map_su2_profile_to_pato_faces.py"

test -f "$VTU" || {
    echo "ERROR: VTU missing: $VTU"
    exit 10
}

test -d "$BASE" || {
    echo "ERROR: PATO PureConduction base missing: $BASE"
    exit 11
}

case "$NFACES" in
    ''|*[!0-9]*)
        echo "ERROR: number_of_surface_faces must be an integer"
        exit 12
        ;;
esac

[ "$NFACES" -ge 2 ] || {
    echo "ERROR: at least two surface faces are required"
    exit 13
}

[ ! -e "$DST" ] || {
    echo "ERROR: destination exists; refusing overwrite: $DST"
    exit 14
}

mkdir -p "$(dirname "$DST")"
cp -a "$BASE" "$DST"

MAPDIR="$DST/SU2_SPATIAL_MAPPING"
mkdir -p "$MAPDIR"

python3 "$PROFILE_TOOL" \
    "$VTU" \
    "$MAPDIR/su2_wall_profile.csv" \
    --metadata "$MAPDIR/su2_wall_profile.json"

python3 "$MAP_TOOL" \
    "$MAPDIR/su2_wall_profile.csv" \
    "$MAPDIR/pato_top_face_loads.csv" \
    --faces "$NFACES" \
    --sign positive-magnitude \
    --q-list "$MAPDIR/q_top_nonuniform.txt" \
    --metadata "$MAPDIR/pato_top_face_loads.json"

L="$(
    python3 - "$MAPDIR/pato_top_face_loads.json" <<'PY'
import json, sys
print(f"{json.load(open(sys.argv[1]))['arc_length_m']:.16g}")
PY
)"

DEPTH="0.05"
WIDTH="0.01"
NY="100"

BLOCK="$DST/system/porousMat/blockMeshDict"

cat > "$BLOCK" <<EOF
/*--------------------------------*- C++ -*----------------------------------*\\
| =========                 |                                                 |
| \\\\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox           |
|  \\\\    /   O peration     | Version:  7                                   |
|   \\\\  /    A nd           |                                                 |
|    \\\\/     M anipulation  |                                                 |
\\*---------------------------------------------------------------------------*/

FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      blockMeshDict;
}

convertToMeters 1;

vertices
(
    (0      0       0)
    ($L     0       0)
    ($L     $DEPTH  0)
    (0      $DEPTH  0)
    (0      0       $WIDTH)
    ($L     0       $WIDTH)
    ($L     $DEPTH  $WIDTH)
    (0      $DEPTH  $WIDTH)
);

blocks
(
    hex (0 1 2 3 4 5 6 7)
        ($NFACES $NY 1)
        simpleGrading (1 0.1 1)
);

edges
(
);

boundary
(
    top
    {
        type patch;
        faces
        (
            (3 2 6 7)
        );
    }

    bottom
    {
        type patch;
        faces
        (
            (0 4 5 1)
        );
    }

    sides
    {
        type patch;
        faces
        (
            (0 3 7 4)
            (1 5 6 2)
            (0 1 2 3)
            (4 7 6 5)
        );
    }
);

mergePatchPairs
(
);

// ************************************************************************* //
EOF

TA="$DST/origin.0/porousMat/Ta"

python3 - "$TA" "$MAPDIR/pato_top_face_loads.csv" <<'PY'
import csv
import re
import sys
from pathlib import Path

ta_path = Path(sys.argv[1])
face_csv = Path(sys.argv[2])

with face_csv.open(newline="") as f:
    rows = list(csv.DictReader(f))

q = [float(r["Heat_Flux"]) for r in rows]

text = ta_path.read_text()

def matching_brace(s, open_i):
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
    raise SystemExit("ERROR: boundaryField not found")

bf_open = text.find("{", m.start())
bf_close = matching_brace(text, bf_open)
bf = text[bf_open + 1 : bf_close]

pm = re.search(r"(?m)^([ \t]*)top[ \t]*\s*\{", bf)
if not pm:
    raise SystemExit("ERROR: top patch not found")

indent = pm.group(1)
po = bf.find("{", pm.start())
pc = matching_brace(bf, po)

start = bf_open + 1 + pm.start()
end = bf_open + 1 + pc + 1

qlines = "\n".join(f"{indent}        {x:.12e}" for x in q)

new_patch = f"""{indent}top
{indent}{{
{indent}    type            basicWallHeatFluxTemperature;
{indent}    mode            flux;
{indent}    q               nonuniform List<scalar>
{indent}    {len(q)}
{indent}    (
{qlines}
{indent}    );
{indent}    kappa           1.000000000000e+00;
{indent}    emissivity      0.000000000000e+00;
{indent}    value           uniform 5.500000000000e+02;
{indent}}}"""

banner = (
    "// -------------------------------------------------------------------------\n"
    "// SU2_NEMO -> PATO SPATIAL TEST_ONLY CASE\n"
    "// Source SU2 solution is NOT converged; no physical interpretation allowed.\n"
    "// q on 'top' is a conservative face-average map of the SU2 wall profile.\n"
    "// Source ordering is reconstructed from VTU_LINE connectivity.\n"
    "// -------------------------------------------------------------------------\n"
)

ta_path.write_text(banner + text[:start] + new_patch + text[end:])
PY

cp -a "$DST/origin.0" "$DST/0"

cat > "$DST/README_SU2_PATO_SPATIAL_TEST_ONLY.md" <<EOF
# SU2 NEMO -> PATO spatial TEST_ONLY case

Status: **TEST_ONLY**

The current aerodynamic source solution is non-converged. This case is
only for validating spatial coupling software.

Spatial mapping:
- source wall order: reconstructed from VTU line-cell connectivity;
- source coordinate: cumulative wall arclength;
- PATO surface coordinate: strip x-coordinate;
- strip length: $L m;
- PATO top faces: $NFACES;
- mapping: exact face-average integration of the piecewise-linear source
  heat-flux profile;
- sign policy: positive-magnitude.

The mapper preserves integral q ds across the 2-D source arclength to
roundoff.

The PATO direct heat-flux boundary still uses test-only kappa=1 in the
basicWallHeatFluxTemperature BC. This is an execution/coupling case, not
a physical TPS result.
EOF

python3 - "$VTU" "$MAPDIR" "$DST" "$NFACES" "$L" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

vtu = Path(sys.argv[1]).resolve()
mapdir = Path(sys.argv[2]).resolve()
dst = Path(sys.argv[3]).resolve()
nfaces = int(sys.argv[4])
length = float(sys.argv[5])

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

profile = json.loads((mapdir / "su2_wall_profile.json").read_text())
mapping = json.loads((mapdir / "pato_top_face_loads.json").read_text())

manifest = {
    "status": "TEST_ONLY",
    "physical_interpretation_allowed": False,
    "reason": "Spatial mapping is driven by the current non-converged SU2 development solution.",
    "source_vtu": str(vtu),
    "source_vtu_sha256": sha256(vtu),
    "source_profile": profile,
    "spatial_mapping": mapping,
    "pato_surface_faces": nfaces,
    "pato_strip_length_m": length,
    "pato_strip_depth_m": 0.05,
    "pato_strip_width_m": 0.01,
    "heat_flux_bc": "basicWallHeatFluxTemperature",
    "sign_policy": "positive-magnitude",
}

(dst / "SU2_PATO_SPATIAL_TEST_ONLY_MANIFEST.json").write_text(
    json.dumps(manifest, indent=2) + "\n"
)
PY

echo "CASE=$DST"
echo "VTU=$VTU"
echo "NFACES=$NFACES"
echo "STRIP_LENGTH=$L"
echo "TA=$TA"
echo "SU2_PATO_SPATIAL_CASE_CREATE=PASS"
