# Changelog

All notable release-level changes to this SU2-NEMO distribution are recorded here.

## [0.1.0] - 2026-09-26

First installable production-oriented release.

### NEMO and Mutation++ implementation

- Production-hardened NEMO/Mutation++ path for AIR-5, AIR-7, and AIR-11.
- Explicit and implicit thermochemical nonequilibrium support.
- Accepted-state recovery and admissibility/backtracking.
- AIR-11 pressure-derivative support.
- Vibrational/electronic-energy source Jacobian support.
- Ambipolar Stefan-Maxwell transport.
- Thread-safe Mutation++ transport.
- Eigen DSO symbol isolation.
- Exact catalytic species-flux heat reporting.
- Hardened catalytic and supercatalytic wall handling.
- Transient thermochemical admissibility limiting.
- AIR-11 supercatalytic elemental/charge closure corrections.

### Installation and runtime

- Added production source installer under `scripts/install.sh`.
- Added fast-forward-only updater under `scripts/update.sh`.
- Added installation/runtime doctor under `scripts/doctor.sh`.
- Added release-quality source checker under `scripts/release_check.sh`.
- Build enables Mutation++ and PySU2 from the same source checkout.
- Runtime packages SU2_CFD, Mutation++ library/data, PySU2, examples, documentation, provenance, and SHA-256 manifest.
- Runtime packaging excludes Mutation++ Meson object directories.
- Manifest is finalized only after PySU2 and runtime environment files are installed.

### Validation

- Verified installation from an existing validated source tree.
- Verified a completely fresh public GitHub clone, full source build, independent install prefix, doctor, SU2_CFD runtime linkage, PySU2 import, AIR-5/AIR-7/AIR-11 databases, clean library packaging, manifest integrity, and provenance.
