#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DEST="${1:-$HOME/SU2_NEMO/runtime}"
BIN="$SRC/build/SU2_CFD/src/SU2_CFD"
MPP_BUILD="$SRC/build/subprojects/Mutationpp"

[ -x "$BIN" ] || { echo "ERROR: SU2_CFD build missing: $BIN" >&2; exit 10; }
git -C "$SRC/subprojects/Mutationpp" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: Mutation++ submodule unavailable" >&2; exit 11;
}

STAGE="${DEST}.new.$$"
BACKUP="${DEST}.previous"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/libexec" "$STAGE/lib" "$STAGE/share/mutationpp" "$STAGE/docs" "$STAGE/tools" "$STAGE/examples"

install -m 0755 "$BIN" "$STAGE/libexec/SU2_CFD.real"

shopt -s nullglob
MPP_LIBS=("$MPP_BUILD"/libmutation*.so*)
shopt -u nullglob
[ "${#MPP_LIBS[@]}" -gt 0 ] || { echo "ERROR: Mutation++ shared library not found in $MPP_BUILD" >&2; exit 12; }
cp -a "${MPP_LIBS[@]}" "$STAGE/lib/"

cp -a "$SRC/subprojects/Mutationpp/data" "$STAGE/share/mutationpp/"
cp -a "$SRC/TestCases/nonequilibrium" "$STAGE/examples/"
cp "$SRC/validation_checkpoints/final_patches/NEMO_EXTREME_MACH_PERMANENT_IMPLEMENTATION_REPORT.md" "$STAGE/docs/IMPLEMENTATION_REPORT.md"
cp "$SRC/SU2_NEMO_INSTALL.md" "$STAGE/docs/"

for F in \
  install_dependencies_ubuntu.sh \
  install_su2_nemo.sh \
  update_su2_nemo.sh \
  verify_su2_nemo.sh \
  update_portable_su2_nemo.sh \
  su2_nemo_manager.sh \
  make_su2_nemo_tarball.sh \
  su2_nemo_env.sh
 do
  cp "$SRC/$F" "$STAGE/tools/$F"
 done
cp "$SRC/su2_nemo_env.sh" "$STAGE/su2_nemo_env.sh"

for F in LICENSE LICENSE.txt LICENSE.md COPYING; do
  [ ! -f "$SRC/$F" ] || cp "$SRC/$F" "$STAGE/docs/SU2_$F"
  [ ! -f "$SRC/subprojects/Mutationpp/$F" ] || cp "$SRC/subprojects/Mutationpp/$F" "$STAGE/docs/Mutationpp_$F"
done

cat > "$STAGE/bin/SU2_CFD" <<'WRAP'
#!/usr/bin/env bash
set -e
SELF="$(readlink -f "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
export MPP_DIRECTORY="$ROOT/share/mutationpp"
export MPP_DATA_DIRECTORY="$ROOT/share/mutationpp/data"
export LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export OMPI_MCA_osc="${OMPI_MCA_osc:-pt2pt}"
exec "$ROOT/libexec/SU2_CFD.real" "$@"
WRAP
chmod +x "$STAGE/bin/SU2_CFD"

cat > "$STAGE/verify_runtime.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REAL="$ROOT/libexec/SU2_CFD.real"

echo "============================================================"
echo " SU2 NEMO PORTABLE RUNTIME VERIFICATION"
echo "============================================================"
[ -x "$ROOT/bin/SU2_CFD" ]
[ -x "$REAL" ]
[ -d "$ROOT/share/mutationpp/data" ]
[ -f "$ROOT/share/mutationpp/data/mixtures/air_7.xml" ]
[ -f "$ROOT/share/mutationpp/data/mechanisms/air7_Park.xml" ]
shopt -s nullglob
LIBS=("$ROOT"/lib/libmutation*.so*)
shopt -u nullglob
[ "${#LIBS[@]}" -gt 0 ] || { echo "ERROR: packaged Mutation++ shared library missing" >&2; exit 10; }

LDD_OUT="$(LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$REAL")"
echo "$LDD_OUT"
if echo "$LDD_OUT" | grep -Fq 'not found'; then
  echo "ERROR: unresolved shared-library dependency" >&2; exit 11
fi
echo "$LDD_OUT" | grep -F "$ROOT/lib/" >/dev/null || {
  echo "ERROR: packaged Mutation++ library is not selected by the loader" >&2; exit 12;
}

if [ -f "$ROOT/MANIFEST.sha256" ]; then
  (cd "$ROOT" && sha256sum -c MANIFEST.sha256)
fi

echo "PORTABLE_RUNTIME=PASS"
echo "MUTATIONPP_LIBRARY=PASS"
echo "MUTATIONPP_DATA=PASS"
echo "AIR7_DATA=PASS"
echo "SHARED_LIBRARIES=PASS"
echo "Set PATH with: export PATH=\"$ROOT/bin:\$PATH\""
VERIFY
chmod +x "$STAGE/verify_runtime.sh"

SU2_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
MPP_COMMIT="$(git -C "$SRC/subprojects/Mutationpp" rev-parse HEAD)"
TAG="$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || true)"
[ -n "$TAG" ] || TAG="unreleased-$SU2_COMMIT"
BIN_SHA="$(sha256sum "$BIN" | awk '{print $1}')"

cat > "$STAGE/VERSION" <<VERSION
SU2_NEMO_TAG=$TAG
SU2_COMMIT=$SU2_COMMIT
MUTATIONPP_COMMIT=$MPP_COMMIT
SU2_CFD_SHA256=$BIN_SHA
ARCH=$(uname -m)
SYSTEM=$(uname -s)
VERSION

cat > "$STAGE/README_FIRST.txt" <<README
SU2 NEMO PORTABLE RUNTIME
=========================
After extraction no SU2 rebuild is required on a compatible Linux x86_64 machine.

Verify:
  ./verify_runtime.sh

Use with PATH only:
  export PATH="\$(pwd)/bin:\$PATH"
  SU2_CFD your_case.cfg

Or activate the full environment:
  source ./su2_nemo_env.sh

The launcher configures Mutation++ shared-library/data paths and OMPI_MCA_osc=pt2pt.
For Mutation++ NEMO production cases use:
  REF_DIMENSIONALIZATION= DIMENSIONAL
README

(
  cd "$STAGE"
  find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
)

rm -rf "$BACKUP"
if [ -e "$DEST" ]; then mv "$DEST" "$BACKUP"; fi
mv "$STAGE" "$DEST"
echo "RUNTIME_REFRESH=PASS"
echo "RUNTIME=$DEST"
