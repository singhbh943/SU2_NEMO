# Changelog

## [0.1.0] - 2026-09-26

First unified installable release line.

### Solver implementation

- SU2 8.5.0 "Harrier" source base.
- Production-hardened NEMO/Mutation++ path for AIR-5, AIR-7 and AIR-11.
- Explicit/implicit thermochemical nonequilibrium.
- Accepted-state recovery and admissibility/backtracking.
- AIR-11 pressure-derivative and energy/Jacobian corrections.
- Ambipolar Stefan-Maxwell transport.
- Catalytic/supercatalytic wall hardening and elemental/charge closure.

### Unified installation

- Replaced the earlier parallel `~/SU2_NEMO` runtime layout with the normal SU2 source/install layout.
- Default install prefix is the `SU2_install` directory beside the source checkout.
- Standard SU2 executables remain installed normally.
- NEMO is provided through the same installed `SU2_CFD`.
- Mutation++ is installed into the same prefix using `install-mpp=true`.
- PySU2 is installed into the same prefix.
- PATO is pinned as an SU2 submodule, built with its isolated OpenFOAM-7 environment, and exposed through the same install prefix.
- Added unified `PATOx`, `su2-pato`, and `su2-nemo-python` launchers.
- Added unified provenance and doctor checks.

### Coupling

- Integrated the validated persistent SU2-PATO coupling runtime from SU2-PATO-Coupling commit `57ef14be32a4db4dedcfd8a2f6550299fe456ea0`.
- Persistent PySU2 state, SU2 wall heat-flux extraction, conservative SU2→PATO mapping, PATO advancement, and PATO→SU2 wall-temperature feedback are included.
