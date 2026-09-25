# SU2 NEMO + PATO integration

## Pinned PATO

- Upstream release: PATO 3.1
- Upstream base commit: `33d895885ceb1b61e71e2d2f2cf5327339205570`
- Integration patch commit: `9fa38452230ae0e9cd45a5e07ef1b145a1cb2c18`
- Current post-release PATO pin: `7a19ba8b3ae1768cb7f21833ef6188bb34b39fe5`
- Integration branch: `su2-nemo-pato-3.1-compat`
- Fork: `https://github.com/singhbh943/pato.git`

## Architecture

PATO is maintained as a separate OpenFOAM-based external component inside
the SU2_NEMO repository. It is not linked directly into the SU2_CFD
executable.

- SU2 NEMO: external hypersonic / thermochemical nonequilibrium flow
- Mutation++ in SU2: gas thermochemistry and transport
- PATO: porous TPS, pyrolysis, heat transfer and material response
- PATO's bundled Mutation++ remains isolated from the SU2 Mutation++ build

## Host toolchain

The validated PATO build uses the isolated `su2-nemo-pato` Conda
environment with:

- PATO 3.1
- OpenFOAM 7
- PATO foam-extend package
- GCC/G++ 11.2
- GNU binutils 2.36.1
- `sysroot_linux-64=2.17`
- `kernel-headers_linux-64=3.10.0`

The sysroot/kernel pair is intentionally pinned because newer Conda
sysroots can contain RELR sections not understood by GNU ld 2.36.1.

## Source compatibility patch

PATO 3.1's bundled Mutation++ uses `assert(...)` from
`Thermodynamics.h` without directly including `<cassert>`. Modern GCC
exposes this missing include. The integration patch adds only:

```cpp
#include <cassert>
```

before the Eigen include.

## Commands

Create/repair the PATO environment:

```bash
./tools/install_pato_environment.sh
```

Build the pinned source:

```bash
./tools/build_pato.sh
```

Activate for interactive use:

```bash
source ./tools/activate_pato.sh
```

Verify the existing build:

```bash
./tools/verify_pato.sh
```

The existing SU2 NEMO numerical solver is not modified by this integration.
