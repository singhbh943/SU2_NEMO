# Third-Party Notices

This repository is an SU2-derived source tree and contains pinned third-party submodules. This notice is informational and does not replace any component's actual license/legal files.

## SU2

Upstream: https://github.com/su2code/SU2

The repository retains SU2 license and attribution materials including `COPYING`, `LICENSE.md`, `AUTHORS.md`, and source-file notices.

## Mutation++

Pinned under:

```text
subprojects/Mutationpp
```

Pinned fork: https://github.com/singhbh943/Mutationpp

Upstream: https://github.com/mutationpp/Mutationpp

The pinned revision's own license/legal files must be preserved. Its repository metadata is not fully consistent about GPL/LGPL labeling, so this project does not attempt to reinterpret those terms.

## NASA PATO

Pinned under:

```text
externals/PATO
```

Pinned fork: https://github.com/singhbh943/pato

PATO contains its own legal documentation under `documentation/legal`, including NASA Open Source Agreement materials. Those materials must be preserved with source redistribution.

## OpenFOAM / foam-extend / Conda toolchain

PATO execution uses its compatible OpenFOAM-7 and foam-extend environment supplied through the PATO Conda environment. Those packages remain subject to their own licenses and notices and are not relicensed by this repository.

## SU2-PATO coupling

The persistent coupling implementation integrated under `coupling/SU2_PATO` is derived from the separately validated SU2-PATO-Coupling project. The v0.1.0 unified release line imports the validated runtime from commit:

```text
57ef14be32a4db4dedcfd8a2f6550299fe456ea0
```

## Redistribution

Preserve corresponding source, pinned submodule references, build scripts, and the relevant license/legal files for every redistributed component or runtime package.
