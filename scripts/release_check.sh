#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

echo "============================================================"
echo " SU2 NEMO RELEASE CHECK"
echo "============================================================"

for f in   scripts/install.sh   scripts/update.sh   scripts/doctor.sh   scripts/release_check.sh   install_su2_nemo.sh   update_su2_nemo.sh   refresh_su2_nemo_runtime.sh   verify_su2_nemo.sh
do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 10; }
  bash -n "$f"
done

grep -Fq 'CMutationTCLib::ComputedPdU' SU2_CFD/src/fluid/CMutationTCLib.cpp
grep -Fq 'ComputeStefanMaxwellDiffusionVelocities' SU2_CFD/src/fluid/CMutationTCLib.cpp
grep -Fq 'GetEveSourceTermJacobian' SU2_CFD/src/fluid/CMutationTCLib.cpp
grep -Fq "subprojects/Mutationpp" .gitmodules
grep -Fq "https://github.com/singhbh943/Mutationpp.git" .gitmodules

test -f validation_checkpoints/final_patches/NEMO_EXTREME_MACH_PERMANENT_IMPLEMENTATION_REPORT.md
test -f subprojects/Mutationpp/data/mixtures/air_5.xml
test -f subprojects/Mutationpp/data/mixtures/air_7.xml
test -f subprojects/Mutationpp/data/mixtures/air_11.xml

if grep -RInE   'REPLACE_ME|YOUR_GITHUB_EMAIL|PUT_THE_EXACT_EMAIL_HERE'   scripts install_su2_nemo.sh update_su2_nemo.sh SU2_NEMO_INSTALL.md
then
  echo "ERROR: release placeholder found" >&2
  exit 11
fi

echo "SU2_NEMO_RELEASE_CHECK=PASS"
