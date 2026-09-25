# SU2-NEMO Production Solver

Production-hardened SU2 NEMO with Mutation++ support for thermochemical nonequilibrium, ionized air mixtures, catalytic-wall physics, implicit thermochemistry, and extreme-Mach robustness.

This repository is an independently maintained SU2-derived implementation. It is not the upstream SU2 project. Upstream SU2 project information and license files are retained in this repository.

## Validated production coverage

The v0.1.0 implementation includes:

- AIR-5, AIR-7, and AIR-11 Mutation++ mixtures and mechanisms.
- Two-temperature NEMO thermochemical nonequilibrium.
- Ionization and finite-rate chemistry.
- Explicit and implicit integration.
- Non-catalytic, catalytic, and supercatalytic wall paths.
- Accepted-state recovery and thermochemical admissibility/backtracking.
- Implicit chemistry and vibrational/electronic-energy Jacobians.
- AIR-11 pressure-derivative support.
- Ambipolar Stefan-Maxwell diffusion.
- Thread-safe Mutation++ transport.
- Eigen DSO symbol isolation for Mutation++.
- Exact catalytic species-flux heat reporting.
- Transient thermochemical admissibility limiting.
- AIR-11 supercatalytic N/O elemental conservation and zero net charge-flux enforcement.
- PySU2 support built from the same source tree.

For Mutation++ NEMO production cases, use:

```text
REF_DIMENSIONALIZATION= DIMENSIONAL
```

## Source installation

On Ubuntu, clone the release and build the complete solver stack:

```bash
git clone --branch v0.1.0 --recursive \
  https://github.com/singhbh943/SU2_NEMO.git

cd SU2_NEMO

./scripts/install.sh \
  --prefix "$HOME/SU2_NEMO" \
  --install-deps
```

If the required compiler, CMake, Ninja, OpenMPI, and other dependencies are already installed, omit `--install-deps`:

```bash
./scripts/install.sh \
  --prefix "$HOME/SU2_NEMO" \
  --jobs "$(nproc)"
```

The installer initializes the pinned Mutation++ submodule, configures SU2 with Mutation++ and PySU2 enabled, builds the source tree, constructs a relocatable runtime, records provenance, and verifies the installation.

## Verify the installation

```bash
./scripts/doctor.sh --prefix "$HOME/SU2_NEMO"
```

A successful installation reports:

```text
SU2_NEMO_DOCTOR=PASS
```

The installed solver is available at:

```text
$HOME/SU2_NEMO/bin/SU2_CFD
```

Add it to your shell path:

```bash
export PATH="$HOME/SU2_NEMO/bin:$PATH"
```

Then run a case normally:

```bash
SU2_CFD case.cfg
```

## PySU2

The installer also builds and packages PySU2:

```bash
"$HOME/SU2_NEMO/bin/su2-nemo-python" your_script.py
```

or activate the runtime environment:

```bash
source "$HOME/SU2_NEMO/runtime/su2_nemo_env.sh"
```

## Updating an installation

From a source checkout:

```bash
./scripts/update.sh --prefix "$HOME/SU2_NEMO"
```

The update path requires a clean tracked source tree and uses a fast-forward-only update.

## Portable Linux runtime

A verified source build can generate a portable Linux x86_64 runtime:

```bash
./make_su2_nemo_tarball.sh
```

The portable runtime includes the SU2_CFD executable, the required Mutation++ shared library and data, PySU2 runtime files, examples, provenance metadata, checksums, and verification tooling. Compatibility with the target system libraries, including glibc and OpenMPI, is still required.

## Release validation

The v0.1.0 installation workflow was validated from a fresh public GitHub clone into an independent installation prefix. The release gate verified:

- a fresh source build;
- pinned Mutation++ submodule provenance;
- SU2_CFD runtime linkage to the packaged Mutation++ library;
- PySU2 import from the installed runtime;
- AIR-5, AIR-7, and AIR-11 mixture/mechanism data;
- runtime SHA-256 manifest integrity;
- clean Mutation++ library packaging;
- installation provenance; and
- the complete `doctor.sh` verification path.

The validation establishes reproducibility of the software installation/runtime path. It does not by itself establish physical validation for every geometry, flow condition, material model, or numerical configuration.

## Implementation record

The permanent implementation report and patch records are stored under:

```text
validation_checkpoints/final_patches/
```

In particular:

```text
validation_checkpoints/final_patches/
NEMO_EXTREME_MACH_PERMANENT_IMPLEMENTATION_REPORT.md
```

documents the hardened NEMO/Mutation++ implementation.

## Upstream projects and licensing

This repository is derived from SU2 and uses Mutation++ as a pinned submodule. Preserve the license and attribution files shipped with both projects.

- SU2 license texts are retained in `COPYING` and `LICENSE.md`.
- Mutation++ license text is retained by the pinned submodule and copied into the packaged runtime documentation.
- See `THIRD_PARTY_NOTICES.md` for the release-specific notice, including a metadata inconsistency observed in the pinned Mutation++ revision.

## Citation

See `CITATION.cff` for this release. When publishing results, also cite the relevant upstream SU2 and Mutation++ publications.

## Repository

https://github.com/singhbh943/SU2_NEMO
