#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

echo "============================================================"
echo " UNIFIED SU2 NEMO PATO RELEASE CHECK"
echo "============================================================"

require_file() { [[ -f "$1" ]] || { echo "ERROR: missing required file: $1" >&2; exit 10; }; }
require_grep() { grep -Fq "$1" "$2" || { echo "ERROR: required marker not found in $2: $1" >&2; exit 12; }; }

for f in   scripts/install.sh   scripts/update.sh   scripts/doctor.sh   scripts/release_check.sh   install_su2_nemo.sh   update_su2_nemo.sh   tools/activate_pato.sh   tools/build_pato.sh   tools/install_pato_environment.sh   coupling/SU2_PATO/runtime/run_persistent_coupling.sh   coupling/SU2_PATO/runtime/run_pysu2.sh
do
  require_file "$f"
  bash -n "$f"
done

python3 -m py_compile   coupling/SU2_PATO/runtime/run_persistent_coupling.py   coupling/SU2_PATO/map_su2_profile_to_pato_faces.py   coupling/SU2_PATO/map_pato_temperature_to_su2.py

echo "SCRIPT_AND_PYTHON_SYNTAX=PASS"

require_grep 'CMutationTCLib::ComputedPdU' SU2_CFD/src/fluid/CMutationTCLib.cpp
require_grep 'ComputeStefanMaxwellDiffusionVelocities' SU2_CFD/src/fluid/CMutationTCLib.cpp
require_grep 'GetEveSourceTermJacobian' SU2_CFD/src/fluid/CMutationTCLib.cpp
echo "NEMO_SOURCE_MARKERS=PASS"

require_file .gitmodules
require_grep 'subprojects/Mutationpp' .gitmodules
require_grep 'https://github.com/singhbh943/Mutationpp.git' .gitmodules
require_grep 'externals/PATO' .gitmodules
require_grep 'https://github.com/singhbh943/pato.git' .gitmodules

MPP_GITLINK="$(git ls-files --stage subprojects/Mutationpp | awk '$1=="160000"{print $2}')"
PATO_GITLINK="$(git ls-files --stage externals/PATO | awk '$1=="160000"{print $2}')"

[[ -n "$MPP_GITLINK" ]] || { echo "ERROR: Mutation++ gitlink missing" >&2; exit 13; }
[[ -n "$PATO_GITLINK" ]] || { echo "ERROR: PATO gitlink missing" >&2; exit 14; }

echo "MUTATIONPP_GITLINK=$MPP_GITLINK"
echo "PATO_GITLINK=$PATO_GITLINK"
echo "SUBMODULE_METADATA=PASS"

require_file validation_checkpoints/final_patches/NEMO_EXTREME_MACH_PERMANENT_IMPLEMENTATION_REPORT.md
require_file coupling/SU2_PATO/runtime/run_persistent_coupling.py
require_file coupling/SU2_PATO/map_su2_profile_to_pato_faces.py
require_file coupling/SU2_PATO/map_pato_temperature_to_su2.py

echo "IMPLEMENTATION_AND_COUPLING_SOURCE=PASS"

if grep -InE   'REPLACE_ME|YOUR_GITHUB_EMAIL|PUT_THE_EXACT_EMAIL_HERE'   scripts/install.sh   scripts/update.sh   scripts/doctor.sh   install_su2_nemo.sh   update_su2_nemo.sh   SU2_NEMO_INSTALL.md   README.md
then
  echo "ERROR: release placeholder found" >&2
  exit 11
fi

echo "RELEASE_PLACEHOLDER_CHECK=PASS"
echo "SU2_NEMO_RELEASE_CHECK=PASS"
