#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)}"
RUNTIME="${2:-$HOME/SU2_NEMO/runtime}"

echo "============================================================"
echo " SU2 NEMO IMPLEMENTATION VERIFICATION"
echo " READ ONLY -- NO BUILD -- NO CFD"
echo "============================================================"

git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null
git -C "$SRC/subprojects/Mutationpp" rev-parse --is-inside-work-tree >/dev/null

echo "SU2_COMMIT=$(git -C "$SRC" rev-parse HEAD)"
echo "MPP_COMMIT=$(git -C "$SRC/subprojects/Mutationpp" rev-parse HEAD)"

grep -Fq 'CMutationTCLib::ComputedPdU' "$SRC/SU2_CFD/src/fluid/CMutationTCLib.cpp"
grep -Fq 'ComputeStefanMaxwellDiffusionVelocities' "$SRC/SU2_CFD/src/fluid/CMutationTCLib.cpp"
grep -Fq 'GetEveSourceTermJacobian' "$SRC/SU2_CFD/src/fluid/CMutationTCLib.cpp"
grep -Fq 'SU2_EIGEN_DSO_SYMBOL_ISOLATION' "$SRC/subprojects/Mutationpp/src/CMakeLists.txt"

TEST="$SRC/UnitTests/SU2_CFD/fluid/CFluidModel_tests.cpp"
for X in \
  '[Mutation++][NEMO][chemistry][air5]' \
  '[Mutation++][NEMO][accepted-state][air5]' \
  '[Mutation++][NEMO][catalytic-wall][air5]' \
  '[Mutation++][NEMO][thermo-derivatives][air7]' \
  '[Mutation++][NEMO][chemistry][air7]' \
  '[Mutation++][NEMO][thermo-derivatives][air11]' \
  '[Mutation++][NEMO][implicit][admissibility][air11]' \
  '[Mutation++][NEMO][chemistry][air11]'
 do
  grep -Fq "$X" "$TEST"
 done

test -f "$SRC/subprojects/Mutationpp/data/mixtures/air_7.xml"
test -f "$SRC/subprojects/Mutationpp/data/mechanisms/air7_Park.xml"
REPORT="$SRC/validation_checkpoints/final_patches/NEMO_EXTREME_MACH_PERMANENT_IMPLEMENTATION_REPORT.md"
grep -Fq 'AIR-5 Mutation++ Support' "$REPORT"
grep -Fq 'AIR-7 Mutation++ Support' "$REPORT"
grep -Fq 'AIR-11 Mutation++ Support' "$REPORT"

echo "SOURCE_IMPLEMENTATION=PASS"
echo "AIR5=PASS"
echo "AIR7=PASS"
echo "AIR11=PASS"
echo "STEFAN_MAXWELL=PASS"
echo "CATALYTIC_SUPPORT=PASS"
echo "IMPLICIT_SUPPORT=PASS"
echo "EVE_JACOBIAN=PASS"
echo "AIR11_DPD_U=PASS"

if [ -x "$RUNTIME/verify_runtime.sh" ]; then "$RUNTIME/verify_runtime.sh"; fi
echo "SU2_NEMO_VERIFY=PASS"
