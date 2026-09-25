# SU2-NEMO Installation

This document describes the supported v0.1.0 installation and runtime workflow.

## Requirements

The source installer is intended for a compatible Linux system. The Ubuntu dependency helper installs the build tools used by the validated release:

```bash
./install_dependencies_ubuntu.sh
```

The dependency set includes a C/C++ toolchain, Git, Python 3, CMake, Ninja, OpenMPI development/runtime packages, zlib development files, curl, and CA certificates.

## Fresh source installation

Clone the release:

```bash
git clone --branch v0.1.0 --recursive \
  https://github.com/singhbh943/SU2_NEMO.git

cd SU2_NEMO
```

Install everything under a dedicated prefix:

```bash
./scripts/install.sh \
  --prefix "$HOME/SU2_NEMO" \
  --install-deps
```

If dependencies are already present:

```bash
./scripts/install.sh \
  --prefix "$HOME/SU2_NEMO" \
  --jobs "$(nproc)"
```

The installer performs the following permanent steps:

1. verifies the source checkout;
2. initializes the pinned Mutation++ submodule;
3. configures Meson with `enable-mpp=true` and `enable-pywrapper=true`;
4. builds SU2_CFD, Mutation++, and PySU2;
5. constructs the runtime under `<prefix>/runtime`;
6. installs Mutation++ data and the required shared library;
7. packages PySU2 and creates `su2-nemo-python`;
8. regenerates the final SHA-256 runtime manifest;
9. verifies the source and runtime; and
10. creates stable `current` and `bin` links.

## Verify

Run:

```bash
./scripts/doctor.sh --prefix "$HOME/SU2_NEMO"
```

The expected final marker is:

```text
SU2_NEMO_DOCTOR=PASS
```

## Run SU2_CFD

```bash
export PATH="$HOME/SU2_NEMO/bin:$PATH"
SU2_CFD case.cfg
```

For Mutation++ NEMO production cases:

```text
REF_DIMENSIONALIZATION= DIMENSIONAL
```

## Run PySU2

```bash
"$HOME/SU2_NEMO/bin/su2-nemo-python" your_script.py
```

The wrapper configures the packaged Python, Mutation++ data, Mutation++ shared-library path, and OpenMPI OSC setting.

## Update

From the checked-out source tree:

```bash
./scripts/update.sh --prefix "$HOME/SU2_NEMO"
```

The updater refuses tracked local modifications and uses a fast-forward-only Git update before rebuilding/revalidating.

## Release/source verification

Before packaging or publishing a source state:

```bash
./scripts/release_check.sh
```

The check validates script syntax, NEMO source markers, the Mutation++ submodule gitlink and repository metadata, implementation-report presence, release placeholders, and—when initialized—the pinned Mutation++ revision and AIR-5/AIR-7/AIR-11 data.

## Portable runtime

After a verified source build:

```bash
./make_su2_nemo_tarball.sh
```

The resulting Linux x86_64 package can be verified with:

```bash
./verify_runtime.sh
```

A portable binary runtime still depends on compatible host system libraries such as glibc and OpenMPI.

## Compatibility entry points

The historical top-level commands remain as compatibility wrappers:

```bash
./install_su2_nemo.sh
./update_su2_nemo.sh
```

New usage should prefer `scripts/install.sh`, `scripts/update.sh`, and `scripts/doctor.sh`.
