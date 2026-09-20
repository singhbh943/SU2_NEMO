#!/usr/bin/env python3
"""Export SU2 wall data from raw-appended VTU to CSV.

Supports the SU2 VTK XML format used by the validated NEMO production case:
  - UnstructuredGrid
  - raw <AppendedData>
  - UInt64 block headers
  - uncompressed appended arrays

The parser intentionally uses only the Python standard library.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import struct
import sys
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


TYPE_INFO = {
    "Float32": ("f", 4),
    "Float64": ("d", 8),
    "Int8": ("b", 1),
    "UInt8": ("B", 1),
    "Int16": ("h", 2),
    "UInt16": ("H", 2),
    "Int32": ("i", 4),
    "UInt32": ("I", 4),
    "Int64": ("q", 8),
    "UInt64": ("Q", 8),
}


def attrs(text: str) -> Dict[str, str]:
    return {
        k: v
        for k, _, v in re.findall(
            r"""([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(["'])(.*?)\2""",
            text,
            flags=re.S,
        )
    }


def first_tag_attrs(text: str, tag: str) -> Dict[str, str]:
    m = re.search(rf"<{tag}\b([^>]*)>", text, flags=re.I | re.S)
    if not m:
        raise RuntimeError(f"Missing <{tag}>")
    return attrs(m.group(1))


def section(text: str, tag: str) -> str:
    m = re.search(
        rf"<{tag}\b[^>]*>(.*?)</{tag}>",
        text,
        flags=re.I | re.S,
    )
    if not m:
        raise RuntimeError(f"Missing <{tag}> section")
    return m.group(1)


def dataarrays(section_text: str) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    for m in re.finditer(r"<DataArray\b([^>]*)/?>", section_text, flags=re.I | re.S):
        out.append(attrs(m.group(1)))
    return out


class RawVTU:
    def __init__(self, path: Path):
        self.path = path
        self.blob = path.read_bytes()

        app_tag = self.blob.find(b"<AppendedData")
        if app_tag < 0:
            raise RuntimeError("VTU has no <AppendedData> section")

        tag_end = self.blob.find(b">", app_tag)
        if tag_end < 0:
            raise RuntimeError("Malformed <AppendedData> tag")

        underscore = self.blob.find(b"_", tag_end + 1)
        if underscore < 0:
            raise RuntimeError("Raw appended-data sentinel '_' not found")

        self.data_start = underscore + 1
        self.header_text = self.blob[:app_tag].decode("utf-8", errors="strict")

        vtk = first_tag_attrs(self.header_text, "VTKFile")
        if vtk.get("compressor"):
            raise RuntimeError(
                f"Compressed appended VTU is not supported: {vtk['compressor']}"
            )

        self.byte_order = vtk.get("byte_order", "LittleEndian")
        if self.byte_order == "LittleEndian":
            self.endian = "<"
        elif self.byte_order == "BigEndian":
            self.endian = ">"
        else:
            raise RuntimeError(f"Unsupported byte_order={self.byte_order}")

        self.header_type = vtk.get("header_type", "UInt32")
        if self.header_type not in ("UInt32", "UInt64"):
            raise RuntimeError(f"Unsupported header_type={self.header_type}")

        self.header_fmt = "I" if self.header_type == "UInt32" else "Q"
        self.header_size = 4 if self.header_type == "UInt32" else 8

        piece = first_tag_attrs(self.header_text, "Piece")
        self.npoints = int(piece["NumberOfPoints"])
        self.ncells = int(piece["NumberOfCells"])

        points = dataarrays(section(self.header_text, "Points"))
        if len(points) != 1:
            raise RuntimeError(f"Expected exactly one Points DataArray, got {len(points)}")
        self.points_desc = points[0]

        self.point_descs = {
            a.get("Name", ""): a
            for a in dataarrays(section(self.header_text, "PointData"))
            if a.get("Name")
        }

    def read_array(self, desc: Dict[str, str]) -> List[Tuple[float, ...] | float | int]:
        dtype = desc.get("type")
        if dtype not in TYPE_INFO:
            raise RuntimeError(f"Unsupported VTK data type: {dtype}")

        if desc.get("format", "").lower() != "appended":
            raise RuntimeError(
                f"Only appended arrays are supported; got format={desc.get('format')}"
            )

        offset = int(desc["offset"])
        ncomp = int(desc.get("NumberOfComponents", "1"))

        pos = self.data_start + offset
        if pos + self.header_size > len(self.blob):
            raise RuntimeError("Array header lies beyond end of file")

        (nbytes,) = struct.unpack_from(
            self.endian + self.header_fmt,
            self.blob,
            pos,
        )
        pos += self.header_size
        end = pos + nbytes

        if end > len(self.blob):
            raise RuntimeError("Array payload lies beyond end of file")

        code, item_size = TYPE_INFO[dtype]
        if nbytes % item_size:
            raise RuntimeError(
                f"{desc.get('Name','<unnamed>')}: payload size {nbytes} "
                f"is not divisible by item size {item_size}"
            )

        count = nbytes // item_size
        values = struct.unpack_from(
            self.endian + f"{count}{code}",
            self.blob,
            pos,
        )

        if ncomp == 1:
            return list(values)

        if count % ncomp:
            raise RuntimeError(
                f"{desc.get('Name','<unnamed>')}: component count mismatch"
            )

        return [
            tuple(values[i : i + ncomp])
            for i in range(0, count, ncomp)
        ]

    def points(self) -> List[Tuple[float, float, float]]:
        pts = self.read_array(self.points_desc)
        if len(pts) != self.npoints:
            raise RuntimeError(
                f"Points count mismatch: header={self.npoints}, decoded={len(pts)}"
            )
        return [tuple(map(float, p)) for p in pts]  # type: ignore[arg-type]

    def point_array(self, name: str):
        if name not in self.point_descs:
            raise KeyError(name)
        values = self.read_array(self.point_descs[name])
        if len(values) != self.npoints:
            raise RuntimeError(
                f"{name}: point count mismatch: "
                f"header={self.npoints}, decoded={len(values)}"
            )
        return values


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("vtu", type=Path)
    ap.add_argument("csv", type=Path)
    ap.add_argument(
        "--all-point-scalars",
        action="store_true",
        help="include every scalar PointData array in addition to required fields",
    )
    args = ap.parse_args()

    vtu = RawVTU(args.vtu)

    required = [
        "Pressure",
        "Temperature_tr",
        "Temperature_ve",
        "Heat_Flux",
    ]
    massfrac = [f"MassFrac_{i}" for i in range(11)]

    missing = [n for n in required + massfrac if n not in vtu.point_descs]
    if missing:
        raise SystemExit(
            "ERROR: missing required SU2 wall arrays: " + ", ".join(missing)
        )

    selected = required + massfrac

    if args.all_point_scalars:
        for name, desc in vtu.point_descs.items():
            if int(desc.get("NumberOfComponents", "1")) == 1 and name not in selected:
                selected.append(name)

    pts = vtu.points()
    arrays = {name: vtu.point_array(name) for name in selected}

    args.csv.parent.mkdir(parents=True, exist_ok=True)

    fields = ["point_id", "x", "y", "z"] + selected

    with args.csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()

        for i, (x, y, z) in enumerate(pts):
            row = {
                "point_id": i,
                "x": f"{x:.12e}",
                "y": f"{y:.12e}",
                "z": f"{z:.12e}",
            }

            for name in selected:
                v = arrays[name][i]
                if isinstance(v, tuple):
                    raise RuntimeError(f"Unexpected vector array in scalar export: {name}")
                row[name] = f"{float(v):.12e}"

            w.writerow(row)

    hf = [float(v) for v in arrays["Heat_Flux"]]
    p = [float(v) for v in arrays["Pressure"]]
    t = [float(v) for v in arrays["Temperature_tr"]]

    if not all(math.isfinite(v) for v in hf + p + t):
        raise SystemExit("ERROR: non-finite wall data detected")

    imax_abs = max(range(len(hf)), key=lambda i: abs(hf[i]))

    print(f"VTU={args.vtu}")
    print(f"CSV={args.csv}")
    print(f"POINTS={vtu.npoints}")
    print(f"CELLS={vtu.ncells}")
    print(f"HEAT_FLUX_MIN={min(hf):.12e}")
    print(f"HEAT_FLUX_MAX={max(hf):.12e}")
    print(f"HEAT_FLUX_MAX_ABS_POINT={imax_abs}")
    print(f"HEAT_FLUX_MAX_ABS_RAW={hf[imax_abs]:.12e}")
    print(f"PRESSURE_MIN={min(p):.12e}")
    print(f"PRESSURE_MAX={max(p):.12e}")
    print(f"TEMPERATURE_TR_MIN={min(t):.12e}")
    print(f"TEMPERATURE_TR_MAX={max(t):.12e}")
    print("SU2_WALL_EXPORT=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
