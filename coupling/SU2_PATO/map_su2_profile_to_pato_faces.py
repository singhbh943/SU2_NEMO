#!/usr/bin/env python3
"""Map an ordered SU2 wall profile conservatively to PATO strip faces.

The source profile is piecewise linear in arclength. For every target PATO
face interval, this tool computes the exact average of each mapped source
field over that interval.

For Heat_Flux this means:
    q_face = (1 / ds_face) * integral_face q(s) ds

Therefore the discrete target integral sum(q_face * ds_face) preserves the
piecewise-linear SU2 source integral to roundoff when both span the same
arclength.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import math
from pathlib import Path


NON_FIELD_COLUMNS = {
    "path_index",
    "point_id",
    "s",
    "s_normalized",
    "x",
    "y",
    "z",
}


def interp(s: list[float], y: list[float], x: float) -> float:
    if x <= s[0]:
        return y[0]
    if x >= s[-1]:
        return y[-1]

    j = bisect.bisect_right(s, x) - 1
    x0, x1 = s[j], s[j + 1]
    y0, y1 = y[j], y[j + 1]

    if x1 == x0:
        return 0.5 * (y0 + y1)

    a = (x - x0) / (x1 - x0)
    return y0 + a * (y1 - y0)


def integrate_piecewise_linear(
    s: list[float],
    y: list[float],
    a: float,
    b: float,
) -> float:
    if not (s[0] <= a <= b <= s[-1]):
        raise ValueError(f"integration interval [{a}, {b}] outside [{s[0]}, {s[-1]}]")

    knots = [a]
    lo = bisect.bisect_right(s, a)
    hi = bisect.bisect_left(s, b)
    knots.extend(s[lo:hi])
    knots.append(b)

    total = 0.0

    for x0, x1 in zip(knots, knots[1:]):
        y0 = interp(s, y, x0)
        y1 = interp(s, y, x1)
        total += 0.5 * (y0 + y1) * (x1 - x0)

    return total


def sign_transform(values: list[float], mode: str) -> list[float]:
    if mode == "same":
        return values[:]
    if mode == "flip":
        return [-x for x in values]
    if mode == "positive-magnitude":
        return [abs(x) for x in values]
    raise ValueError(mode)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("profile_csv", type=Path)
    ap.add_argument("face_csv", type=Path)
    ap.add_argument("--faces", type=int, required=True)
    ap.add_argument(
        "--sign",
        choices=("same", "flip", "positive-magnitude"),
        required=True,
    )
    ap.add_argument("--q-list", type=Path)
    ap.add_argument("--metadata", type=Path)
    args = ap.parse_args()

    if args.faces < 1:
        raise SystemExit("ERROR: --faces must be >= 1")

    with args.profile_csv.open(newline="") as f:
        r = csv.DictReader(f)
        rows = list(r)
        fieldnames = r.fieldnames or []

    if len(rows) < 2:
        raise SystemExit("ERROR: source profile needs at least two points")

    s = [float(r["s"]) for r in rows]

    if any(b <= a for a, b in zip(s, s[1:])):
        raise SystemExit("ERROR: source arclength must be strictly increasing")

    L = s[-1] - s[0]

    if L <= 0:
        raise SystemExit("ERROR: non-positive source arclength")

    scalar_fields = [n for n in fieldnames if n not in NON_FIELD_COLUMNS]
    source = {
        name: [float(row[name]) for row in rows]
        for name in scalar_fields
    }

    if "Heat_Flux" not in source:
        raise SystemExit("ERROR: Heat_Flux missing from source profile")

    source["Heat_Flux"] = sign_transform(source["Heat_Flux"], args.sign)

    ds = L / args.faces

    face_rows = []

    for i in range(args.faces):
        a = s[0] + i * ds
        b = s[0] + (i + 1) * ds
        c = 0.5 * (a + b)

        row = {
            "face_id": i,
            "s0": a,
            "s1": b,
            "s_center": c,
            "s_normalized": (c - s[0]) / L,
            "ds": ds,
        }

        for name, values in source.items():
            integ = integrate_piecewise_linear(s, values, a, b)
            row[name] = integ / ds

        face_rows.append(row)

    source_q_integral = integrate_piecewise_linear(
        s,
        source["Heat_Flux"],
        s[0],
        s[-1],
    )
    target_q_integral = sum(row["Heat_Flux"] * row["ds"] for row in face_rows)

    rel_error = abs(target_q_integral - source_q_integral) / max(
        abs(source_q_integral), 1.0
    )

    if rel_error > 1e-11:
        raise SystemExit(
            f"ERROR: conservative heat-load mapping failed: relative error={rel_error:.6e}"
        )

    args.face_csv.parent.mkdir(parents=True, exist_ok=True)

    out_fields = [
        "face_id",
        "s0",
        "s1",
        "s_center",
        "s_normalized",
        "ds",
        *scalar_fields,
    ]

    with args.face_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=out_fields)
        w.writeheader()

        for row in face_rows:
            w.writerow(
                {
                    k: (
                        str(row[k])
                        if k == "face_id"
                        else f"{float(row[k]):.12e}"
                    )
                    for k in out_fields
                }
            )

    q_list_path = args.q_list or args.face_csv.with_name("q_top_nonuniform.txt")
    q_values = [row["Heat_Flux"] for row in face_rows]

    with q_list_path.open("w") as f:
        f.write("nonuniform List<scalar>\n")
        f.write(f"{len(q_values)}\n")
        f.write("(\n")
        for q in q_values:
            f.write(f"    {q:.12e}\n")
        f.write(")\n")

    metadata_path = args.metadata or args.face_csv.with_suffix(
        args.face_csv.suffix + ".json"
    )

    metadata = {
        "source_profile": str(args.profile_csv.resolve()),
        "target_faces": args.faces,
        "sign_policy": args.sign,
        "arc_length_m": L,
        "face_length_m": ds,
        "source_integral_q_ds_W_m": source_q_integral,
        "target_integral_q_ds_W_m": target_q_integral,
        "relative_integral_error": rel_error,
        "mapped_q_min_W_m2": min(q_values),
        "mapped_q_max_W_m2": max(q_values),
        "mapping": "exact face average of piecewise-linear source profile",
    }

    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")

    print(f"FACE_CSV={args.face_csv}")
    print(f"Q_LIST={q_list_path}")
    print(f"METADATA={metadata_path}")
    print(f"TARGET_FACES={args.faces}")
    print(f"ARC_LENGTH={L:.12e}")
    print(f"FACE_LENGTH={ds:.12e}")
    print(f"SOURCE_INTEGRAL_Q_DS={source_q_integral:.12e}")
    print(f"TARGET_INTEGRAL_Q_DS={target_q_integral:.12e}")
    print(f"RELATIVE_INTEGRAL_ERROR={rel_error:.12e}")
    print(f"MAPPED_Q_MIN={min(q_values):.12e}")
    print(f"MAPPED_Q_MAX={max(q_values):.12e}")
    print("SU2_PATO_CONSERVATIVE_SPATIAL_MAP=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
