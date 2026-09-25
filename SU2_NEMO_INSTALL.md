# Unified SU2-NEMO-PATO Installation

The supported installation follows the normal SU2 source + install-prefix structure:

```text
~/SU2/SU2          source tree
~/SU2/SU2_install  installed tree
```

NEMO is part of the installed `SU2_CFD`; it is not installed as a second independent SU2 tree.

## Fresh install

Prerequisite: Miniconda/Conda is available. The validated setup uses `~/miniconda3`.

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

If system dependencies and the pinned PATO Conda environment already exist:

```bash
./scripts/install.sh --prefix "$HOME/SU2/SU2_install" --jobs "$(nproc)"
```

## What the installer does

1. Initializes all pinned submodules recursively.
2. Verifies or creates the PATO 3.1 Conda environment when requested.
3. Configures SU2 8.5 with Mutation++, Mutation++ installation, and PySU2.
4. Builds and installs the normal SU2 executables into `SU2_install/bin`.
5. Installs `libmutation__.so` and AIR-5/AIR-7/AIR-11 data into the same prefix.
6. Creates an NEMO-aware `SU2_CFD` launcher while preserving the installed ELF as `SU2_CFD.real`.
7. Builds PATO in the isolated OpenFOAM-7/foam-extend environment.
8. Copies the PATO runtime/source support tree into `SU2_install/share/PATO`.
9. Installs the validated persistent SU2-PATO coupling under `SU2_install/share/su2-pato`.
10. Creates `PATOx`, `su2-pato`, and `su2-nemo-python` launchers.
11. Writes installation provenance and runs the unified doctor.

## Verify

```bash
./scripts/doctor.sh --prefix "$HOME/SU2/SU2_install"
```

## Normal SU2/NEMO

```bash
source "$HOME/SU2/SU2_install/etc/su2/activate.sh"
SU2_CFD case.cfg
```

For Mutation++ NEMO cases:

```text
REF_DIMENSIONALIZATION= DIMENSIONAL
```

## PySU2

```bash
su2-nemo-python your_script.py
```

## PATO

```bash
PATOx
```

The launcher activates the pinned PATO Conda/OpenFOAM-7 environment only for PATO execution.

## Persistent two-way coupling

```bash
su2-pato \
  --su2-case /path/to/su2/case \
  --pato-case /path/to/pato/case
```

The current validated persistent driver is case-specific to the AIR11 interface used during development: 139 SU2 wall vertices and 138 PATO faces. Its default `Q_SCALE` and `PATO_DT` are software-validation defaults, not general production values.

## Update

```bash
./scripts/update.sh --prefix "$HOME/SU2/SU2_install"
```

## Release check

```bash
./scripts/release_check.sh
```

The release check verifies NEMO source markers, both pinned gitlinks, persistent coupling files, and shell/Python syntax.
