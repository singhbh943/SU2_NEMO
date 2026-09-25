# Unified SU2 8.5 + NEMO + Mutation++ + PATO

This repository extends SU2 8.5.0 "Harrier" in the normal SU2 source/install layout. It does not create a separate parallel SU2-NEMO product tree.

The intended layout is:

```text
~/SU2/
├── SU2/          # source checkout
└── SU2_install/  # one installed prefix
```

The single installation contains standard SU2, the hardened NEMO/Mutation++ implementation, PySU2, NASA PATO, and the validated SU2↔PATO coupling launchers.

## Included capability

- Standard SU2 executables: SU2_CFD, SU2_DEF, SU2_DOT, SU2_GEO, SU2_SOL.
- AIR-5, AIR-7 and AIR-11 NEMO/Mutation++ support.
- Explicit and implicit thermochemical nonequilibrium.
- Catalytic and supercatalytic wall hardening.
- AIR-11 pressure/Jacobian and elemental/charge closure corrections.
- Ambipolar Stefan-Maxwell transport.
- PySU2 built and installed with the same SU2 source.
- PATO 3.1 pinned as `externals/PATO`.
- Isolated OpenFOAM-7/foam-extend PATO environment.
- Persistent SU2↔PATO heat-flux / wall-temperature coupling.

For Mutation++ NEMO production cases use:

```text
REF_DIMENSIONALIZATION= DIMENSIONAL
```

## Recommended fresh install

Miniconda is required for the PATO toolchain. With Miniconda available under `~/miniconda3`:

```bash
mkdir -p "$HOME/SU2"

git clone --branch v0.1.0 --recursive \
  https://github.com/singhbh943/SU2_NEMO.git \
  "$HOME/SU2/SU2"

cd "$HOME/SU2/SU2"

./scripts/install.sh \
  --prefix "$HOME/SU2/SU2_install" \
  --install-deps \
  --install-pato-env \
  --persist-shell
```

The `v0.1.0` tag is the immutable validated release described on the GitHub Releases page.

The installer builds SU2 with:

```text
enable-mpp=true
install-mpp=true
enable-pywrapper=true
```

and builds PATO in the pinned isolated OpenFOAM-7 environment.

## Installed commands

```text
~/SU2/SU2_install/bin/SU2_CFD
~/SU2/SU2_install/bin/SU2_DEF
~/SU2/SU2_install/bin/SU2_DOT
~/SU2/SU2_install/bin/SU2_GEO
~/SU2/SU2_install/bin/SU2_SOL
~/SU2/SU2_install/bin/su2-nemo-python
~/SU2/SU2_install/bin/PATOx
~/SU2/SU2_install/bin/su2-pato
```

Normal SU2 runs use:

```bash
source "$HOME/SU2/SU2_install/etc/su2/activate.sh"
SU2_CFD case.cfg
```

PATO is deliberately activated only when `PATOx` or `su2-pato` is invoked so its OpenFOAM/compiler/MPI environment does not contaminate normal SU2 runs.

## Verify

```bash
cd "$HOME/SU2/SU2"
./scripts/doctor.sh --prefix "$HOME/SU2/SU2_install"
```

A complete installation reports:

```text
SU2_UNIFIED_DOCTOR=PASS
SU2_STANDARD=PASS
SU2_NEMO=PASS
MUTATIONPP=PASS
PYSU2=PASS
PATO=PASS
SU2_PATO_COUPLING=PASS
```

## Update

```bash
cd "$HOME/SU2/SU2"
./scripts/update.sh --prefix "$HOME/SU2/SU2_install"
```

## Coupling

The installed coupling command is:

```bash
su2-pato --su2-case /path/to/su2/case --pato-case /path/to/pato/case
```

The current persistent driver is the validated AIR11 interface implementation and includes case-specific interface cardinalities (139 SU2 wall vertices and 138 PATO faces). Validate geometry, ordering, heat-flux sign, scaling, and material timestep before production use.

## Provenance

The installer writes:

```text
~/SU2/SU2_install/UNIFIED_INSTALLATION
```

with SU2, Mutation++, and PATO commits plus build/install ELF identifiers.

## Licensing and attribution

This is an SU2-derived source tree. Preserve the existing SU2 license and attribution files. Mutation++ and PATO are pinned submodules and retain their own license/legal materials. See `THIRD_PARTY_NOTICES.md`.

The installation validation establishes software/build/runtime reproducibility. It does not by itself validate every physical configuration.
