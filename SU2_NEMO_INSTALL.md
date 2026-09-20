# SU2 NEMO Production Solver

Production-hardened SU2 NEMO with Mutation++ for AIR-5, AIR-7 and AIR-11 extreme-Mach thermochemical-nonequilibrium simulation.

## Production coverage

- AIR-5, AIR-7, AIR-11
- two-temperature NEMO
- ionization and finite-rate chemistry
- Mutation++ thermochemistry
- explicit and implicit integration
- non-catalytic and catalytic wall paths
- accepted-state recovery and admissibility/backtracking
- implicit chemistry and vibrational/electronic-energy Jacobians
- AIR11 pressure derivative support
- ambipolar Stefan-Maxwell diffusion
- thread-safe Mutation++ transport
- Eigen DSO symbol isolation
- exact catalytic species-flux heat reporting
- dimensional Mutation++ production contract

For Mutation++ production cases:

```text
REF_DIMENSIONALIZATION= DIMENSIONAL
```

## Fastest method: portable TAR

```bash
tar -xzf SU2_NEMO-portable-linux-x86_64.tar.gz
cd SU2_NEMO-*
./verify_runtime.sh
export PATH="$PWD/bin:$PATH"
SU2_CFD case.cfg
```

No SU2 rebuild is needed on a compatible Linux x86_64 machine. The wrapper configures Mutation++ library/data paths automatically. Compatible system libraries (notably glibc/OpenMPI) are still required.

## Fresh source installation

Run dependencies once:

```bash
./install_dependencies_ubuntu.sh
```

Then:

```bash
./install_su2_nemo.sh
export PATH="$HOME/SU2_NEMO/bin:$PATH"
```

## Future source update (no apt reinstall)

```bash
cd ~/SU2_NEMO/source
./update_su2_nemo.sh
```

## Portable update without compiling

From an extracted portable package:

```bash
./tools/update_portable_su2_nemo.sh
```

The latest verified runtime is installed version-by-version under `~/SU2_NEMO_PORTABLE` and exposed through a stable `bin` symlink.

## Manager

```bash
./su2_nemo_manager.sh deps
./su2_nemo_manager.sh install
./su2_nemo_manager.sh update
./su2_nemo_manager.sh verify
./su2_nemo_manager.sh tar
./su2_nemo_manager.sh portable-update
./su2_nemo_manager.sh status
```
