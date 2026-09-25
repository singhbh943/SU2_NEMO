#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

echo "============================================================"
echo " SU2 NEMO RELEASE CHECK"
echo "============================================================"

require_file() {
  [[ -f "$1" ]] || {
    echo "ERROR: missing required file: $1" >&2
    exit 10
  }
}

require_grep() {
  local pattern="$1"
  local file="$2"
  grep -Fq "$pattern" "$file" || {
    echo "ERROR: required marker not found in $file: $pattern" >&2
    exit 12
  }
}

for f in   scripts/install.sh   scripts/update.sh   scripts/doctor.sh   scripts/release_check.sh   install_su2_nemo.sh   update_su2_nemo.sh   refresh_su2_nemo_runtime.sh   verify_su2_nemo.sh
do
  require_file "$f"
  bash -n "$f"
done
echo "SCRIPT_SYNTAX=PASS"

require_grep 'CMutationTCLib::ComputedPdU' SU2_CFD/src/fluid/CMutationTCLib.cpp
require_grep 'ComputeStefanMaxwellDiffusionVelocities' SU2_CFD/src/fluid/CMutationTCLib.cpp
require_grep 'GetEveSourceTermJacobian' SU2_CFD/src/fluid/CMutationTCLib.cpp
echo "NEMO_SOURCE_MARKERS=PASS"

require_file .gitmodules
require_grep 'subprojects/Mutationpp' .gitmodules
require_grep 'https://github.com/singhbh943/Mutationpp.git' .gitmodules

MPP_GITLINK="$(git ls-files --stage subprojects/Mutationpp | awk '$1 == "160000" {print $2}')"
[[ -n "$MPP_GITLINK" ]] || {
  echo "ERROR: Mutation++ submodule gitlink is missing" >&2
  exit 13
}
echo "MUTATIONPP_GITLINK=$MPP_GITLINK"
echo "MUTATIONPP_SUBMODULE_METADATA=PASS"

require_file validation_checkpoints/final_patches/NEMO_EXTREME_MACH_PERMANENT_IMPLEMENTATION_REPORT.md
echo "IMPLEMENTATION_REPORT=PASS"

if git -C subprojects/Mutationpp rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  require_file subprojects/Mutationpp/data/mixtures/air_5.xml
  require_file subprojects/Mutationpp/data/mixtures/air_7.xml
  require_file subprojects/Mutationpp/data/mixtures/air_11.xml
  require_file subprojects/Mutationpp/data/mechanisms/air5_Park.xml
  require_file subprojects/Mutationpp/data/mechanisms/air7_Park.xml
  require_file subprojects/Mutationpp/data/mechanisms/air11_Park.xml
  echo "MUTATIONPP_INITIALIZED_DATA=PASS"
else
  echo "MUTATIONPP_INITIALIZED_DATA=SKIP_NOT_INITIALIZED"
fi

if grep -InE   'REPLACE_ME|YOUR_GITHUB_EMAIL|PUT_THE_EXACT_EMAIL_HERE'   scripts/install.sh   scripts/update.sh   scripts/doctor.sh   install_su2_nemo.sh   update_su2_nemo.sh   SU2_NEMO_INSTALL.md
then
  echo "ERROR: release placeholder found" >&2
  exit 11
fi
echo "RELEASE_PLACEHOLDER_CHECK=PASS"

echo "SU2_NEMO_RELEASE_CHECK=PASS"
