#!/usr/bin/env python3
"""Extract an ordered SU2 wall profile using VTU line-cell connectivity.

The ordinary wall CSV stores point IDs in VTK point order. Spatial coupling
must not assume that point IDs are already in wall-arclength order.

This tool reconstructs the open wall polyline from VTK_LINE connectivity,
then emits a topology-ordered profile with cumulative arclength s.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path

from export_su2_wall import RawVTU, dataarrays, section


REQUIRED = [
    "Pressure",
    "Temperature_tr",
    "Temperature_ve",
    "Heat_Flux",
    *[f"MassFrac_{i}" for i in range(11)],
]


def reconstruct_open_chain(npoints: int, edges: list[tuple[int, int]]) -> list[int]:
    adj: dict[int, list[int]] = defaultdict(list)

    for a, b in edges:
        if a == b:
            raise RuntimeError(f"degenerate wall edge {a}-{b}")
        adj[a].append(b)
        adj[b].append(a)

    used_points = sorted(adj)

    if len(used_points) != npoints:
        missing = sorted(set(range(npoints)) - set(used_points))
        raise RuntimeError(
            f"not every VTU point belongs to the wall chain; "
            f"used={len(used_points)}, total={npoints}, missing={missing[:12]}"
        )

    bad_degree = {p: len(adj[p]) for p in used_points if len(adj[p]) not in (1, 2)}
    if bad_degree:
        raise RuntimeError(f"wall topology is not a simple chain: {bad_degree}")

    endpoints = sorted(p for p in used_points if len(adj[p]) == 1)

    if len(endpoints) != 2:
        raise RuntimeError(
            f"expected an open polyline with 2 endpoints, found {len(endpoints)}"
        )

    # Deterministic orientation. The reverse direction is physically equivalent
    # for heat-load magnitude mapping and can be requested explicitly.
    start = endpoints[0]

    order = [start]
    prev = None
    cur = start

    while True:
        candidates = [n for n in adj[cur] if n != prev]
        if not candidates:
            break
        if len(candidates) != 1:
            raise RuntimeError(f"ambiguous wall traversal at point {cur}")

        nxt = candidates[0]
        order.append(nxt)
        prev, cur = cur, nxt

    if len(order) != npoints:
        raise RuntimeError(
            f"wall traversal did not visit every point: {len(order)} / {npoints}"
        )

    return order


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("vtu", type=Path)
    ap.add_argument("profile_csv", type=Path)
    ap.add_argument("--metadata", type=Path)
    ap.add_argument("--reverse", action="store_true")
    args = ap.parse_args()

    v = RawVTU(args.vtu)

    missing = [name for name in REQUIRED if name not in v.point_descs]
    if missing:
        raise SystemExit("ERROR: missing required arrays: " + ", ".join(missing))

    cells = {
        a.get("Name", ""): a
        for a in dataarrays(section(v.header_text, "Cells"))
        if a.get("Name")
    }

    for name in ("connectivity", "offsets", "types"):
        if name not in cells:
            raise SystemExit(f"ERROR: VTU Cells/{name} array is missing")

    conn = [int(x) for x in v.read_array(cells["connectivity"])]
    offsets = [int(x) for x in v.read_array(cells["offsets"])]
    types = [int(x) for x in v.read_array(cells["types"])]

    edges: list[tuple[int, int]] = []
    start = 0

    for ci, (end, ctype) in enumerate(zip(offsets, types)):
        ids = conn[start:end]
        start = end

        if len(ids) != 2:
            raise SystemExit(
                f"ERROR: wall cell {ci} has {len(ids)} points; expected 2"
            )

        # VTK_LINE = 3. Keep the explicit check so topology mistakes are caught.
        if ctype != 3:
            raise SystemExit(
                f"ERROR: wall cell {ci} has VTK type {ctype}; expected VTK_LINE=3"
            )

        edges.append((ids[0], ids[1]))

    if len(edges) != v.ncells:
        raise SystemExit(
            f"ERROR: decoded edge count {len(edges)} != NumberOfCells {v.ncells}"
        )

    order = reconstruct_open_chain(v.npoints, edges)

    if args.reverse:
        order.reverse()

    pts = v.points()
    arrays = {name: v.point_array(name) for name in REQUIRED}

    s = [0.0]
    for a, b in zip(order, order[1:]):
        s.append(s[-1] + math.dist(pts[a], pts[b]))

    q = [float(arrays["Heat_Flux"][pid]) for pid in order]

    integral = 0.0
    for i in range(len(order) - 1):
        ds = s[i + 1] - s[i]
        integral += 0.5 * (q[i] + q[i + 1]) * ds

    args.profile_csv.parent.mkdir(parents=True, exist_ok=True)

    fields = [
        "path_index",
        "point_id",
        "s",
        "s_normalized",
        "x",
        "y",
        "z",
        *REQUIRED,
    ]

    with args.profile_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()

        L = s[-1]

        for path_i, pid in enumerate(order):
            x, y, z = pts[pid]
            row = {
                "path_index": path_i,
                "point_id": pid,
                "s": f"{s[path_i]:.12e}",
                "s_normalized": f"{(s[path_i] / L if L else 0.0):.12e}",
                "x": f"{x:.12e}",
                "y": f"{y:.12e}",
                "z": f"{z:.12e}",
            }

            for name in REQUIRED:
                row[name] = f"{float(arrays[name][pid]):.12e}"

            w.writerow(row)

    metadata_path = args.metadata or args.profile_csv.with_suffix(
        args.profile_csv.suffix + ".json"
    )

    metadata = {
        "source_vtu": str(args.vtu.resolve()),
        "number_of_points": v.npoints,
        "number_of_line_cells": len(edges),
        "ordered_start_point_id": order[0],
        "ordered_end_point_id": order[-1],
        "reversed": args.reverse,
        "arc_length_m": s[-1],
        "raw_heat_flux_min_W_m2": min(q),
        "raw_heat_flux_max_W_m2": max(q),
        "integral_q_ds_W_m": integral,
        "ordering": "VTK_LINE connectivity",
    }

    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")

    print(f"PROFILE_CSV={args.profile_csv}")
    print(f"METADATA={metadata_path}")
    print(f"POINTS={v.npoints}")
    print(f"LINE_CELLS={len(edges)}")
    print(f"START_POINT_ID={order[0]}")
    print(f"END_POINT_ID={order[-1]}")
    print(f"ARC_LENGTH={s[-1]:.12e}")
    print(f"INTEGRAL_Q_DS={integral:.12e}")
    print("SU2_WALL_TOPOLOGY_PROFILE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
