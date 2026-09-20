#!/usr/bin/env python3
"""Validate a SU2->PATO wall-load CSV."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", type=Path)
    ap.add_argument("--massfrac-tol", type=float, default=5e-4)
    args = ap.parse_args()

    required = {
        "point_id",
        "x",
        "y",
        "z",
        "Pressure",
        "Temperature_tr",
        "Temperature_ve",
        "Heat_Flux",
        *{f"MassFrac_{i}" for i in range(11)},
    }

    with args.csv.open(newline="") as f:
        r = csv.DictReader(f)

        if r.fieldnames is None:
            raise SystemExit("ERROR: CSV has no header")

        missing = sorted(required - set(r.fieldnames))
        if missing:
            raise SystemExit("ERROR: missing columns: " + ", ".join(missing))

        rows = list(r)

    if not rows:
        raise SystemExit("ERROR: CSV has no wall points")

    q = []
    p = []
    tt = []
    tve = []
    max_massfrac_error = 0.0

    for lineno, row in enumerate(rows, start=2):
        vals = {}

        for name in required - {"point_id"}:
            try:
                value = float(row[name])
            except Exception as exc:
                raise SystemExit(
                    f"ERROR: line {lineno}: invalid {name}: {row.get(name)!r}"
                ) from exc

            if not math.isfinite(value):
                raise SystemExit(
                    f"ERROR: line {lineno}: non-finite {name}: {value}"
                )

            vals[name] = value

        if vals["Pressure"] <= 0:
            raise SystemExit(f"ERROR: line {lineno}: non-positive pressure")

        if vals["Temperature_tr"] <= 0 or vals["Temperature_ve"] <= 0:
            raise SystemExit(f"ERROR: line {lineno}: non-positive temperature")

        ys = [vals[f"MassFrac_{i}"] for i in range(11)]

        if min(ys) < -1e-8:
            raise SystemExit(f"ERROR: line {lineno}: negative mass fraction")

        err = abs(sum(ys) - 1.0)
        max_massfrac_error = max(max_massfrac_error, err)

        q.append(vals["Heat_Flux"])
        p.append(vals["Pressure"])
        tt.append(vals["Temperature_tr"])
        tve.append(vals["Temperature_ve"])

    if max_massfrac_error > args.massfrac_tol:
        raise SystemExit(
            f"ERROR: mass-fraction sum error {max_massfrac_error:.6e} "
            f"> tolerance {args.massfrac_tol:.6e}"
        )

    imax_abs = max(range(len(q)), key=lambda i: abs(q[i]))

    print(f"ROWS={len(rows)}")
    print(f"HEAT_FLUX_MIN={min(q):.12e}")
    print(f"HEAT_FLUX_MAX={max(q):.12e}")
    print(f"HEAT_FLUX_MAX_ABS_POINT={rows[imax_abs]['point_id']}")
    print(f"HEAT_FLUX_MAX_ABS_RAW={q[imax_abs]:.12e}")
    print(f"PRESSURE_RANGE={min(p):.12e},{max(p):.12e}")
    print(f"TEMPERATURE_TR_RANGE={min(tt):.12e},{max(tt):.12e}")
    print(f"TEMPERATURE_VE_RANGE={min(tve):.12e},{max(tve):.12e}")
    print(f"MAX_MASSFRAC_SUM_ERROR={max_massfrac_error:.12e}")
    print("SU2_PATO_INTERFACE_VALIDATE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
