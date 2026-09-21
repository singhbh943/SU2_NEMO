#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/SU2_CFD/src/solvers/CNEMOEulerSolver.cpp"

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

a = s.index(
    "void CNEMOEulerSolver::ExplicitEuler_Iteration("
)
b = s.index(
    "\nvoid CNEMOEulerSolver::PrepareImplicitIteration",
    a,
)

f = s[a:b]

checks = [
    ("candidate increment",
     "LinSysSol[index] = -Res*Delta;"),
    ("NEMO limiter",
     "ComputeUnderRelaxationFactor(config);"),
    ("limited update",
     "alpha*LinSysSol[index]"),
    ("solution communication",
     "MPI_QUANTITIES::SOLUTION"),
]

for name, token in checks:
    if token not in f:
        raise SystemExit(
            f"FAIL: {name}: missing {token}"
        )
    print(f"PASS: {name}")

if "Explicit_Iteration<EULER_EXPLICIT>" in f:
    raise SystemExit(
        "FAIL: generic direct explicit update restored"
    )

print("PASS: generic direct explicit update absent")
print("NEMO_EXPLICIT_MACH40_SOURCE_GUARD=PASS")
PY
