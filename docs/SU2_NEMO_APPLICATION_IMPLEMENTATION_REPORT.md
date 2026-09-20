# SU2 NEMO: Application and Implementation Report

**Repository:** `singhbh943/SU2_NEMO`
**Release:** `nemo-extreme-mach-hardened-20260920-r2`
**Packaging release commit:** `dff95f3a688c9af70e269657802d8f9488b1282d`
**Validated solver base:** `719dfc7611d7fa25a895eef24b591f7c9a60fd95`
**Mutation++ commit:** `c44160ef22ca9a9236ab2e10b8b9acb3ff7eefad`

---

## 1. Purpose

This report documents the **applications, numerical capabilities, implementation changes, validation scope, installation workflow, and practical use** of the hardened SU2 NEMO solver distributed through the `SU2_NEMO` repository.

The release targets high-enthalpy and hypersonic flows in which the assumptions of a calorically perfect gas are insufficient. The implementation focuses on robust nonequilibrium CFD using SU2 NEMO coupled with Mutation++, including finite-rate chemistry, two-temperature thermochemistry, ionized mixtures, catalytic walls, implicit source treatment, and transport suitable for extreme-Mach-number applications.

The r2 release does not alter the validated numerical solver implementation from the hardened solver base. It adds reproducible installation, update, verification, and portable-runtime packaging.

---

## 2. Main Application Areas

The solver is intended for simulations involving strong thermochemical nonequilibrium, including:

- hypersonic and atmospheric-entry flows;
- high-enthalpy blunt-body and cylinder flows;
- shock-layer thermochemistry;
- dissociation and ionization of air mixtures;
- translational-rotational and vibrational-electronic nonequilibrium;
- catalytic, partially catalytic, and non-catalytic wall studies;
- aerodynamic heating and wall heat-flux prediction;
- species transport in chemically reacting flows;
- comparison of AIR-5, AIR-7, and AIR-11 thermochemical models;
- explicit and implicit NEMO simulations;
- restart-based long-duration production calculations;
- high-Mach robustness studies in which positivity, admissibility, and thermochemical closure are critical.

Typical research outputs include wall heat flux, surface pressure, drag/lift, shock-layer temperature, vibrational-electronic temperature, species distributions, ionization structure, and convergence histories.

---

## 3. Supported Gas Models

### 3.1 AIR-5

AIR-5 provides a neutral air chemistry model suitable for dissociation-focused nonequilibrium calculations.

The hardened solver includes tested support for:

- Mutation++ AIR-5 thermochemistry;
- finite-rate chemistry;
- accepted-state recovery;
- enthalpy consistency;
- catalytic-wall treatment;
- explicit and implicit NEMO infrastructure.

### 3.2 AIR-7

AIR-7 extends the gas model to ionized conditions.

Permanent AIR-7 data included in the release:

- `air7_Park.xml`
- `air_7.xml`

The permanent data were included in the Mutation++ fork so a fresh clone does not require manual copying of AIR-7 files.

### 3.3 AIR-11

AIR-11 provides a more complete ionized-air description and is the primary extreme-Mach production model used during the final hardening stage.

The solver includes specific AIR-11 support for:

- thermodynamic derivatives;
- pressure derivative `dP/dU`;
- implicit chemistry;
- vibrational-electronic source Jacobians;
- admissibility handling;
- finite-rate ionized chemistry;
- catalytic-wall production runs.

---

## 4. Two-Temperature Nonequilibrium Model

The NEMO formulation retains separate energy modes:

- translational-rotational temperature, \(T\);
- vibrational-electronic temperature, \(T_{ve}\).

The solver therefore evolves both total energy and vibrational-electronic energy instead of collapsing the flow to a one-temperature equilibrium state.

This capability is essential in strong shock layers where translational heating occurs faster than vibrational relaxation, dissociation, and ionization.

---

## 5. Mutation++ Integration

Mutation++ is used as the thermochemical backend for:

- mixture thermodynamics;
- species properties;
- finite-rate kinetics;
- vibrational/electronic energy transfer;
- transport data;
- multicomponent diffusion support.

The production contract for Mutation++ NEMO cases is:

```text
REF_DIMENSIONALIZATION= DIMENSIONAL
```

The hardened solver intentionally fails fast for unsupported Mutation++ nondimensional configurations rather than silently using inconsistent reference-state assumptions.

---

## 6. Thermochemical Admissibility and Accepted-State Recovery

Extreme-Mach calculations can generate candidate conservative states that are mathematically produced by the numerical update but are not physically admissible for the thermochemical backend.

The hardened solver therefore protects the accepted solution state during conservative-to-primitive conversion.

Key behavior includes:

1. evaluate a candidate state;
2. reject thermochemically invalid states;
3. restore the last accepted conservative state before retry/fallback;
4. preserve the accepted state during recovery;
5. avoid contaminating the solution with a failed trial state.

Temperature admissibility is backend aware:

- Mutation++ is not restricted by the previous generic upper-temperature cap;
- native SU2 thermochemistry retains its applicable temperature restrictions.

This is particularly important for high-temperature shock layers and ionized AIR-11 calculations.

---

## 7. Implicit Chemistry and Energy-Transfer Jacobians

The solver contains implicit-source support for nonequilibrium chemistry and vibrational-electronic energy transfer.

Implemented coverage includes:

- chemistry-source Jacobians;
- vibrational/electronic source derivatives;
- AIR-5, AIR-7, and AIR-11 pathways;
- consistency checks against finite-difference derivatives;
- AIR-11-specific thermodynamic derivative verification.

This allows stiff thermochemical source terms to participate consistently in implicit NEMO calculations rather than being treated as a disconnected explicit correction.

---

## 8. AIR-11 Pressure Derivative

The AIR-11 Mutation++ pressure derivative implementation was hardened through an exact `ComputedPdU` override.

The derivative treatment accounts for the ionized, two-temperature mixture formulation and was checked against finite-difference reference values.

This correction is important for implicit flux/source linearization because an inconsistent pressure derivative directly degrades the nonlinear and linearized update.

---

## 9. Ambipolar Stefan-Maxwell Transport

The Mutation++ transport integration uses:

> Mutation++ Stefan-Maxwell ambipolar closure with composition/barodiffusion/two-temperature partial-pressure driving, without explicit Soret diffusion.

The implementation includes:

- local thread-safe Eigen storage;
- Mutation++ Stefan-Maxwell diffusion velocities;
- ambipolar treatment for ionized mixtures;
- species diffusive mass fluxes;
- energy diffusion contributions for all species including electrons;
- mixture-averaged fallback behavior;
- axisymmetric consistency fixes.

The Mutation++ transport path was also hardened to avoid shared mutable work arrays that could lead to thread-safety problems.

---

## 10. Eigen Symbol Isolation

A runtime segmentation fault was traced to Eigen symbol interposition between SU2 and Mutation++ shared-library code.

The Mutation++ library build was hardened using hidden inline visibility and symbolic binding so its Eigen implementation remains isolated from incompatible symbols in the parent executable.

This change is part of the permanent Mutation++ fork used by the release.

---

## 11. Catalytic-Wall Implementation

The NEMO wall treatment supports:

- non-catalytic walls;
- partial catalytic walls;
- fully catalytic finite-rate limiting behavior;
- the existing separate supercatalytic branch.

For partial catalytic calculations, a catalytic efficiency can be prescribed, for example:

```text
CATALYTIC_WALL= (wall)
SUPERCATALYTIC_WALL= NO
CATALYTIC_EFFICIENCY= 0.2
```

The catalytic heat contribution is reported using the exact wall species viscous flux.

The corrected wall heat contribution follows the species enthalpy transport form

\[
q_{\mathrm{species}} = \sum_s J_s h_s,
\]

using the exact wall species mass flux already produced by the viscous residual formulation.

This avoids reconstructing the catalytic contribution from an inconsistent approximation and avoids the previously identified area-scaling error.

---

## 12. Heat-Flux Reporting

The solver reports total wall heat flux through SU2's NEMO output pathway.

For catalytic walls, the final implementation uses the exact wall species flux contribution together with the conductive terms.

This is important for high-enthalpy applications because catalytic recombination can substantially modify wall heating even when the external freestream condition is unchanged.

Production heat-flux values should be interpreted only after numerical stationarity/convergence has been established.

---

## 13. Explicit and Implicit Time Integration

The common NEMO infrastructure supports both:

```text
TIME_DISCRE_FLOW= EULER_EXPLICIT
```

and

```text
TIME_DISCRE_FLOW= EULER_IMPLICIT
```

Implicit calculations can use the configured linear solver, for example BCGSTAB, together with the thermochemical Jacobians described above.

The release includes example cases demonstrating the relevant NEMO configuration structure.

---

## 14. Production AIR-11 Application

A production AIR-11 case was used to exercise the final hardened path with:

- Mutation++ `air_11`;
- ionization enabled;
- Mach 23.9;
- freestream pressure \(19.7\,\mathrm{Pa}\);
- \(T_\infty=T_{ve,\infty}=254\,\mathrm{K}\);
- wall temperature \(550\,\mathrm{K}\);
- dimensional Mutation++ operation;
- partial catalytic wall;
- catalytic efficiency \(\gamma=0.2\);
- implicit integration;
- BCGSTAB;
- exact neutral freestream composition;
- restart-based continuation.

The production path demonstrated finite, stable continuation through the hardened AIR-11 implicit/catalytic implementation. These runs establish software-path viability; they are not by themselves a claim of mesh-independent or literature-validated physical convergence.

---

## 15. Validation Scope

The development process included focused and regression validation of:

- AIR-5 chemistry;
- AIR-5 accepted-state recovery;
- AIR-5 catalytic-wall logic;
- AIR-7 thermodynamic derivatives;
- AIR-7 chemistry;
- AIR-11 thermodynamic derivatives;
- AIR-11 admissibility behavior;
- AIR-11 chemistry;
- vibrational-electronic source Jacobians;
- pressure derivatives;
- catalytic heat-flux reporting;
- Mutation++ transport;
- thread safety;
- portable runtime linkage.

The repository contains permanent regression tests and implementation artifacts documenting the hardened paths.

A distinction is maintained between:

- **implementation support** — the code path is implemented in the shared NEMO infrastructure;
- **validation depth** — not every possible gas-model/wall/time-integration combination was subjected to the same length of production CFD run.

---

## 16. Portable Runtime

Release r2 adds a portable Linux x86-64 runtime containing:

- the exact validated `SU2_CFD` executable;
- Mutation++ shared library;
- complete Mutation++ runtime data;
- AIR-5, AIR-7, and AIR-11 data;
- NEMO example cases;
- implementation documentation;
- environment setup;
- runtime verification;
- update utilities.

After extraction:

```bash
tar -xzf SU2_NEMO-portable-linux-x86_64.tar.gz
cd SU2_NEMO-*
./verify_runtime.sh
export PATH="$PWD/bin:$PATH"
```

A case can then be run with:

```bash
SU2_CFD case.cfg
```

The wrapper configures the bundled Mutation++ runtime and data paths automatically.

The portable package still requires a compatible Linux x86-64 userspace and compatible system libraries such as glibc and OpenMPI.

---

## 17. Fresh Source Installation

For a complete source build:

```bash
./install_dependencies_ubuntu.sh
./install_su2_nemo.sh
```

Dependencies are installed separately so normal software updates do not repeatedly invoke the system package manager.

---

## 18. Incremental Updating

For an existing source installation:

```bash
./update_su2_nemo.sh
```

The updater performs:

1. Git fetch;
2. branch fast-forward;
3. submodule synchronization;
4. Mutation++ update;
5. Meson reconfiguration;
6. incremental Ninja compilation;
7. runtime refresh;
8. verification.

It does not reinstall Ubuntu dependencies.

For a portable-only installation:

```bash
./tools/update_portable_su2_nemo.sh
```

This retrieves the newest portable release, checks its checksum, verifies the extracted package, and switches the local runtime to the new version without compiling SU2.

---

## 19. Verification Utilities

The release provides:

```text
install_dependencies_ubuntu.sh
install_su2_nemo.sh
update_su2_nemo.sh
update_portable_su2_nemo.sh
verify_su2_nemo.sh
make_su2_nemo_tarball.sh
su2_nemo_manager.sh
su2_nemo_env.sh
```

The manager provides a single front end for common operations:

```bash
./su2_nemo_manager.sh deps
./su2_nemo_manager.sh install
./su2_nemo_manager.sh update
./su2_nemo_manager.sh verify
./su2_nemo_manager.sh tar
./su2_nemo_manager.sh portable-update
./su2_nemo_manager.sh status
```

---

## 20. Example NEMO Configuration Skeleton

A typical Mutation++ ionized-air case can use:

```text
SOLVER= NEMO_NAVIER_STOKES

FLUID_MODEL= MUTATIONPP
GAS_MODEL= air_11
IONIZATION= YES

REF_DIMENSIONALIZATION= DIMENSIONAL

TIME_DISCRE_FLOW= EULER_IMPLICIT
LINEAR_SOLVER= BCGSTAB

MARKER_ISOTHERMAL= (wall, 550.0)

CATALYTIC_WALL= (wall)
SUPERCATALYTIC_WALL= NO
CATALYTIC_EFFICIENCY= 0.2
```

Exact freestream composition, numerical flux, limiter, CFL, convergence target, mesh, and wall model should be selected for the intended physical problem rather than copied blindly from a validation case.

---

## 21. Reproducibility Identity

The hardened numerical implementation is anchored by:

```text
Validated solver base:
719dfc7611d7fa25a895eef24b591f7c9a60fd95

Mutation++:
c44160ef22ca9a9236ab2e10b8b9acb3ff7eefad
```

The r2 packaging commit is:

```text
dff95f3a688c9af70e269657802d8f9488b1282d
```

The packaging commit adds installation, update, verification, and portable-runtime infrastructure without changing the hardened numerical solver implementation.

---

## 22. Recommended Scientific Workflow

For a new application:

1. select the appropriate AIR-5/AIR-7/AIR-11 model;
2. define physically consistent freestream composition and temperatures;
3. select the wall catalytic model;
4. use `REF_DIMENSIONALIZATION= DIMENSIONAL` with Mutation++;
5. begin from conservative numerical settings;
6. verify positivity and thermochemical stability;
7. continue to numerical stationarity;
8. perform restart consistency checks;
9. perform mesh-independence assessment;
10. compare against experiments or literature only under matched geometry, freestream, wall, chemistry, transport, and heat-flux definitions.

---

## 23. Summary

The released SU2 NEMO solver combines the SU2 nonequilibrium flow framework with a hardened Mutation++ backend for extreme-Mach thermochemical calculations.

The main permanent additions address:

- AIR-5/AIR-7/AIR-11 thermochemistry;
- high-temperature state admissibility;
- accepted-state recovery;
- implicit chemistry and vibrational-electronic source Jacobians;
- AIR-11 pressure derivatives;
- ambipolar Stefan-Maxwell transport;
- Mutation++ thread safety;
- Eigen shared-library isolation;
- catalytic-wall species transport;
- exact catalytic heat-flux reporting;
- reproducible dimensional Mutation++ operation;
- installation, verification, incremental updating, and portable deployment.

The r2 release is intended to provide both a research-grade source tree and a practical packaged runtime while keeping the numerical implementation and its validation history traceable through Git.
