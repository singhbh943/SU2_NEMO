#!/usr/bin/env python3

import csv
import math
import sys

from mpi4py import MPI
import pysu2


from pathlib import Path
import os
import re
import subprocess
cfg, temp_csv = sys.argv[1:3]

FLOW_SOL = 0
MATCH_TOL = 1.0e-5


with open(temp_csv, newline="") as f:
    rows = list(csv.DictReader(f))

if len(rows) != 139:
    raise SystemExit(
        f"ERROR: expected 139 return vertices, found {len(rows)}"
    )

profile = []

for r in rows:
    profile.append(
        (
            float(r["x"]),
            float(r["y"]),
            float(r["z"]),
            float(r["wall_temperature_K"]),
        )
    )

temps = [p[3] for p in profile]

# Physical sanity check for PATO -> SU2 wall-temperature coupling.
# The first coupled state may legitimately be close to the initial
# solid temperature (~300 K), so do not impose the old 450--650 K
# smoke-test operating band here.
if min(temps) < 200.0 or max(temps) > 5000.0:
    raise SystemExit(
        "ERROR: refusing nonphysical temperature profile: "
        f"{min(temps)} .. {max(temps)} K"
    )

print("INPUT_RETURN_ROWS =", len(profile))
print("INPUT_T_MIN =", min(temps))
print("INPUT_T_MAX =", max(temps))
print("SAFE_INPUT_PROFILE=PASS")


driver = None

try:

    driver = pysu2.CSinglezoneDriver(
        cfg,
        1,
        MPI.COMM_WORLD,
    )

    marker_ids = driver.GetMarkerIndices()

    if "wall" not in marker_ids:
        raise RuntimeError(
            f"wall marker not found; available={marker_ids}"
        )

    wall = marker_ids["wall"]

    nvert = int(driver.GetNumberMarkerNodes(wall))

    print("WALL_MARKER =", wall)
    print("PYSU2_WALL_VERTICES =", nvert)

    if nvert != len(profile):
        raise RuntimeError(
            f"wall count mismatch: PySU2={nvert}, return={len(profile)}"
        )

    coords = driver.MarkerCoordinates(wall)

    shape = coords.Shape()

    nrows = int(shape[0])
    ndim = int(shape[1])

    print("MARKER_COORD_SHAPE =", shape)

    if nrows != nvert:
        raise RuntimeError(
            f"coordinate rows={nrows}, wall vertices={nvert}"
        )

    mapping = {}
    used = set()
    max_dist = 0.0

    for iv in range(nvert):

        c = [
            float(coords.Get(iv, d))
            for d in range(ndim)
        ]

        if ndim == 2:
            c.append(0.0)

        best_j = None
        best_d2 = None

        for j, p in enumerate(profile):

            dx = c[0] - p[0]
            dy = c[1] - p[1]
            dz = c[2] - p[2]

            d2 = dx*dx + dy*dy + dz*dz

            if best_d2 is None or d2 < best_d2:
                best_d2 = d2
                best_j = j

        dist = math.sqrt(best_d2)

        if dist > MATCH_TOL:
            raise RuntimeError(
                f"coordinate match failed at iVertex={iv}: "
                f"distance={dist:.12e}"
            )

        if best_j in used:
            raise RuntimeError(
                f"non-unique coordinate mapping: profile row {best_j}"
            )

        used.add(best_j)
        mapping[iv] = profile[best_j][3]
        max_dist = max(max_dist, dist)

    if len(mapping) != nvert or len(used) != len(profile):
        raise RuntimeError("incomplete coordinate mapping")

    print(f"MAX_COORD_MATCH_DISTANCE={max_dist:.12e}")
    print("PATO_TO_PYSU2_COORDINATE_MAP=PASS")


    ROOT = Path(os.environ["SU2_PATO_ROOT"])
    WORK = Path(os.environ["SU2_PATO_WORK"])
    PATO_CASE = Path(os.environ["SU2_PATO_CASE"])
    STATIC_PROFILE = Path(
        os.environ["SU2_PATO_REFERENCE_PROFILE"]
    )

    N_CYCLES = int(
        os.environ.get("SU2_PATO_CYCLES", "3")
    )

    Q_SCALE = float(
        os.environ.get("SU2_PATO_Q_SCALE", "1e-5")
    )

    PATO_DT = float(
        os.environ.get("SU2_PATO_DT", "1e-12")
    )


    MAP_Q = (
        ROOT
        / "coupling"
        / "SU2_PATO"
        / "map_su2_profile_to_pato_faces.py"
    )

    MAP_T = (
        ROOT
        / "coupling"
        / "SU2_PATO"
        / "map_pato_temperature_to_su2.py"
    )

    ACTIVATE_PATO = ROOT / "tools" / "activate_pato.sh"

    WORK.mkdir(parents=True, exist_ok=True)

    def latest_pato_time():
        times = []

        for item in PATO_CASE.iterdir():

            if not item.is_dir():
                continue

            try:
                value = float(item.name)
            except ValueError:
                continue

            times.append((value, item.name))

        if not times:
            raise RuntimeError(
                "no numeric PATO time directories"
            )

        return max(times)

    def wall_xyz():
        result = []

        for iv in range(nvert):

            xyz = [
                float(coords.Get(iv, d))
                for d in range(ndim)
            ]

            while len(xyz) < 3:
                xyz.append(0.0)

            result.append(tuple(xyz[:3]))

        return result

    PY_XYZ = wall_xyz()

    def load_temperature(csv_file):

        with open(csv_file, newline="") as f:
            rows = list(csv.DictReader(f))

        if len(rows) != 139:
            raise RuntimeError(
                f"expected 139 temperatures, got {len(rows)}"
            )

        source = [
            (
                float(r["x"]),
                float(r["y"]),
                float(r["z"]),
                float(r["wall_temperature_K"]),
            )
            for r in rows
        ]

        temperatures = []
        distances = []

        for xyz in PY_XYZ:

            best_d2 = None
            best_i = None

            for i, pnt in enumerate(source):

                d2 = (
                    (xyz[0] - pnt[0]) ** 2
                    + (xyz[1] - pnt[1]) ** 2
                    + (xyz[2] - pnt[2]) ** 2
                )

                if best_d2 is None or d2 < best_d2:
                    best_d2 = d2
                    best_i = i

            distances.append(math.sqrt(best_d2))
            temperatures.append(source[best_i][3])

        max_distance = max(distances)

        if max_distance > 1.0e-6:
            raise RuntimeError(
                "temperature coordinate mismatch: "
                f"{max_distance}"
            )

        if not all(
            math.isfinite(x)
            for x in temperatures
        ):
            raise RuntimeError(
                "nonfinite wall temperature"
            )

        print(
            "PATO_TO_PYSU2_COORD_MAX_DISTANCE="
            f"{max_distance:.12e}"
        )

        return temperatures

    def write_su2_profile(qwall, cycle):

        with STATIC_PROFILE.open(newline="") as f:
            rows = list(csv.DictReader(f))
            fields = list(rows[0].keys())

        if len(rows) != 139:
            raise RuntimeError(
                f"reference profile rows={len(rows)}"
            )

        if "Heat_Flux" not in fields:
            raise RuntimeError(
                "Heat_Flux missing in reference profile"
            )

        used = set()
        max_distance = 0.0

        for row in rows:

            xyz = (
                float(row["x"]),
                float(row["y"]),
                float(row["z"]),
            )

            best_d2 = None
            best_iv = None

            for iv, point in enumerate(PY_XYZ):

                d2 = (
                    (xyz[0] - point[0]) ** 2
                    + (xyz[1] - point[1]) ** 2
                    + (xyz[2] - point[2]) ** 2
                )

                if best_d2 is None or d2 < best_d2:
                    best_d2 = d2
                    best_iv = iv

            distance = math.sqrt(best_d2)

            max_distance = max(
                max_distance,
                distance,
            )

            if best_iv in used:
                raise RuntimeError(
                    "duplicate PySU2 wall-vertex map"
                )

            used.add(best_iv)

            row["Heat_Flux"] = (
                f"{qwall[best_iv]:.12e}"
            )

        if len(used) != 139:
            raise RuntimeError(
                "incomplete PySU2 wall map"
            )

        if max_distance > 1.0e-6:
            raise RuntimeError(
                "heat-flux coordinate mismatch: "
                f"{max_distance}"
            )

        output = (
            WORK
            / f"su2_wall_profile_cycle_{cycle:06d}.csv"
        )

        with output.open("w", newline="") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=fields,
            )

            writer.writeheader()
            writer.writerows(rows)

        print(
            "PYSU2_TO_PROFILE_COORD_MAX_DISTANCE="
            f"{max_distance:.12e}"
        )

        return output

    def conservative_map(profile, cycle):

        face_csv = (
            WORK
            / f"pato_faces_raw_cycle_{cycle:06d}.csv"
        )

        q_list = (
            WORK
            / f"q_raw_cycle_{cycle:06d}.txt"
        )

        metadata = (
            WORK
            / f"pato_faces_raw_cycle_{cycle:06d}.json"
        )

        cmd = [
            sys.executable,
            str(MAP_Q),
            str(profile),
            str(face_csv),
            "--faces",
            "138",
            # Permanent thermal sign convention:
            #
            # SU2 NEMO GetMarkerNormalHeatFlux() is positive for
            # aerodynamic heat delivered toward the wall.
            #
            # PATO basicWallHeatFluxTemperature uses
            #     refGrad = q/kappa
            # and Fourier conduction gives
            #     q_out = -kappa*dT/dn = -q.
            #
            # Thus positive PATO q is heat entering the TPS.
            # SU2 -> PATO therefore uses the SAME sign.
            "--sign",
            "same",
            "--q-list",
            str(q_list),
            "--metadata",
            str(metadata),
        ]

        result = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
        )

        print(result.stdout, end="")

        if result.returncode != 0:
            print(result.stderr, end="")

            raise RuntimeError(
                "SU2-to-PATO conservative map failed"
            )

        return face_csv

    def scale_flux(face_csv, cycle):

        with face_csv.open(newline="") as f:
            rows = list(csv.DictReader(f))
            fields = list(rows[0].keys())

        if len(rows) != 138:
            raise RuntimeError(
                f"expected 138 PATO faces, got {len(rows)}"
            )

        q_values = []

        for row in rows:

            value = (
                float(row["Heat_Flux"])
                * Q_SCALE
            )

            if not math.isfinite(value):
                raise RuntimeError(
                    "nonfinite scaled heat flux"
                )

            row["Heat_Flux"] = (
                f"{value:.12e}"
            )

            q_values.append(value)

        scaled_csv = (
            WORK
            / f"pato_faces_cycle_{cycle:06d}.csv"
        )

        q_file = (
            WORK
            / f"pato_q_cycle_{cycle:06d}.txt"
        )

        with scaled_csv.open("w", newline="") as f:

            writer = csv.DictWriter(
                f,
                fieldnames=fields,
            )

            writer.writeheader()
            writer.writerows(rows)

        with q_file.open("w") as f:

            f.write(
                "nonuniform List<scalar>\n"
            )

            f.write("138\n(\n")

            for value in q_values:
                f.write(
                    f"    {value:.12e}\n"
                )

            f.write(")\n")

        print(
            f"CYCLE_{cycle}_PATO_Q_MIN="
            f"{min(q_values):.12e}"
        )

        print(
            f"CYCLE_{cycle}_PATO_Q_MAX="
            f"{max(q_values):.12e}"
        )

        return scaled_csv, q_file

    def install_q(q_file):

        time_value, time_name = latest_pato_time()

        ta = (
            PATO_CASE
            / time_name
            / "porousMat"
            / "Ta"
        )

        if not ta.is_file():
            raise RuntimeError(
                f"PATO Ta missing: {ta}"
            )

        text = ta.read_text()
        q_text = q_file.read_text().strip()

        pattern = re.compile(
            r'(\bq\s+)'
            r'nonuniform\s+List<scalar>\s+'
            r'\d+\s*\(.*?\)\s*;',
            re.S,
        )

        updated, count = pattern.subn(
            lambda m: (
                m.group(1)
                + q_text
                + ";"
            ),
            text,
            count=1,
        )

        if count != 1:
            raise RuntimeError(
                "PATO q-field replacement failed: "
                f"{count}"
            )

        ta.write_text(updated)

        print(
            "PATO_Q_INSTALLED_AT="
            f"{time_name}"
        )

        return time_value

    def advance_pato(start_time, cycle):

        end_time = start_time + PATO_DT
        end_string = f"{end_time:.15g}"
        dt_string = f"{PATO_DT:.15g}"

        logfile = (
            WORK
            / f"pato_cycle_{cycle:06d}.log"
        )

        command = f'''
set -e

source "{ACTIVATE_PATO}"

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry startFrom -set latestTime

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry endTime -set {end_string}

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry deltaT -set {dt_string}

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry maxDeltaT -set {dt_string}

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry minDeltaT -set {dt_string}

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry writeInterval -set {dt_string}

foamDictionary "{PATO_CASE}/system/controlDict" \
    -entry writePrecision -set 15

cd "{PATO_CASE}"

PATOx
'''

        with logfile.open("w") as f:

            result = subprocess.run(
                ["bash", "-c", command],
                text=True,
                stdout=f,
                stderr=subprocess.STDOUT,
            )

        print(
            f"CYCLE_{cycle}_PATO_RC="
            f"{result.returncode}"
        )

        if result.returncode != 0:
            raise RuntimeError(
                "PATO failed; see "
                f"{logfile}"
            )

        new_time, new_name = latest_pato_time()

        if new_time <= start_time:
            raise RuntimeError(
                "PATO did not advance: "
                f"{start_time} -> {new_time}"
            )

        print(
            f"CYCLE_{cycle}_PATO_TIME="
            f"{start_time:.15e}"
            "->"
            f"{new_time:.15e}"
        )

        return new_name

    def map_temperature(
        pato_time,
        face_csv,
        profile_csv,
        cycle,
    ):

        ta = (
            PATO_CASE
            / pato_time
            / "porousMat"
            / "Ta"
        )

        output = (
            WORK
            / f"pato_temperature_cycle_{cycle + 1:06d}.csv"
        )

        metadata = (
            WORK
            / f"pato_temperature_cycle_{cycle + 1:06d}.json"
        )

        cmd = [
            sys.executable,
            str(MAP_T),
            str(ta),
            str(face_csv),
            str(profile_csv),
            str(output),
            "--metadata",
            str(metadata),
            "--status",
            "TEST_ONLY",
        ]

        result = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
        )

        print(result.stdout, end="")

        if result.returncode != 0:
            print(result.stderr, end="")

            raise RuntimeError(
                "PATO-to-SU2 temperature map failed"
            )

        return output

    # Load the initial PATO wall temperature from the actual
    # temperature-return CSV supplied to this permanent driver.
    # Do not derive the initial temperature vector from the
    # coordinate-mapping container.
    initial_temperature_csv = Path(sys.argv[2])

    current_twall = load_temperature(
        initial_temperature_csv
    )

    if len(current_twall) != nvert:
        raise RuntimeError(
            "initial Twall count does not match "
            f"PySU2 wall vertices: "
            f"{len(current_twall)} != {nvert}"
        )

    if not all(
        math.isfinite(value)
        for value in current_twall
    ):
        raise RuntimeError(
            "nonfinite initial PATO wall temperature"
        )

    if (
        min(current_twall) < 200.0
        or max(current_twall) > 5000.0
    ):
        raise RuntimeError(
            "initial PATO wall temperature outside "
            "physical safety range"
        )

    print(
        "INITIAL_COUPLED_TWALL_COUNT="
        f"{len(current_twall)}"
    )

    print(
        "INITIAL_COUPLED_TWALL_MIN="
        f"{min(current_twall):.15e}"
    )

    print(
        "INITIAL_COUPLED_TWALL_MAX="
        f"{max(current_twall):.15e}"
    )

    print("INITIAL_COUPLED_TWALL=PASS")

    previous_q = None


    print()
    print(
        "============================================================"
    )
    print(" PERSISTENT SU2 <-> PATO COUPLING")
    print(f" CYCLES={N_CYCLES}")
    print(f" Q_SCALE={Q_SCALE:.12e}")
    print(f" PATO_DT={PATO_DT:.12e}")
    print(
        "============================================================"
    )

    for cycle in range(N_CYCLES):

        print()
        print(
            "============================================================"
        )
        print(
            f" COUPLING CYCLE {cycle}"
        )
        print(
            "============================================================"
        )

        driver.Preprocess(cycle)

        for iv in range(nvert):

            driver.SetMarkerCustomTemperature(
                wall,
                iv,
                current_twall[iv],
            )

        driver.BoundaryConditionsUpdate()

        print(
            f"CYCLE_{cycle}_TWALL_APPLIED=PASS"
        )

        driver.Run()
        driver.Postprocess()

        print(
            f"CYCLE_{cycle}_SU2_RUN=PASS"
        )

        qwall = [
            float(
                driver.GetMarkerNormalHeatFlux(
                    FLOW_SOL,
                    wall,
                    iv,
                )
            )
            for iv in range(nvert)
        ]

        if len(qwall) != 139:
            raise RuntimeError(
                "expected 139 SU2 heat-flux values"
            )

        if not all(
            math.isfinite(x)
            for x in qwall
        ):
            raise RuntimeError(
                "nonfinite SU2 heat flux"
            )

        print(
            f"CYCLE_{cycle}_SU2_Q_COUNT="
            f"{len(qwall)}"
        )

        print(
            f"CYCLE_{cycle}_SU2_Q_MIN="
            f"{min(qwall):.12e}"
        )

        print(
            f"CYCLE_{cycle}_SU2_Q_MAX="
            f"{max(qwall):.12e}"
        )

        api_file = (
            WORK
            / f"su2_api_q_cycle_{cycle:06d}.csv"
        )

        with api_file.open("w", newline="") as f:

            writer = csv.writer(f)

            writer.writerow([
                "vertex",
                "x",
                "y",
                "z",
                "wall_temperature_K",
                "normal_heat_flux_W_m2",
            ])

            for iv in range(nvert):

                x, y, z = PY_XYZ[iv]

                writer.writerow([
                    iv,
                    f"{x:.12e}",
                    f"{y:.12e}",
                    f"{z:.12e}",
                    f"{current_twall[iv]:.15e}",
                    f"{qwall[iv]:.12e}",
                ])

        print(
            f"CYCLE_{cycle}_SU2_Q_EXPORT=PASS"
        )

        if previous_q is not None:

            dq = [
                b - a
                for a, b
                in zip(previous_q, qwall)
            ]

            print(
                f"CYCLE_{cycle}_MAX_ABS_DQ="
                f"{max(abs(x) for x in dq):.12e}"
            )

        driver.Update()

        print(
            f"CYCLE_{cycle}_SU2_UPDATE=PASS"
        )

        profile = write_su2_profile(
            qwall,
            cycle,
        )

        raw_faces = conservative_map(
            profile,
            cycle,
        )

        faces, q_file = scale_flux(
            raw_faces,
            cycle,
        )

        start_time = install_q(
            q_file
        )

        new_pato_time = advance_pato(
            start_time,
            cycle,
        )

        return_csv = map_temperature(
            new_pato_time,
            faces,
            profile,
            cycle,
        )

        new_twall = load_temperature(
            return_csv
        )

        dt_values = [
            b - a
            for a, b
            in zip(current_twall, new_twall)
        ]

        print(
            f"CYCLE_{cycle}_TWALL_MIN="
            f"{min(new_twall):.15e}"
        )

        print(
            f"CYCLE_{cycle}_TWALL_MAX="
            f"{max(new_twall):.15e}"
        )

        print(
            f"CYCLE_{cycle}_MAX_ABS_DT="
            f"{max(abs(x) for x in dt_values):.15e}"
        )

        print(
            f"CYCLE_{cycle}_COUPLING=PASS"
        )

        current_twall = new_twall
        previous_q = qwall

    print(
        "PERSISTENT_SU2_PATO_COUPLING=PASS"
    )

finally:

    if driver is not None:
        driver.Finalize()
