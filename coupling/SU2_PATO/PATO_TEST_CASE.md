# First dedicated PATO material-response case

The first working SU2_NEMO -> PATO material-response case is generated
outside the source tree from the pinned PATO 3.1 `PureConduction`
tutorial.

It is intentionally marked `TEST_ONLY`, because the current AIR11 load
package was exported from a non-converged SU2 development run.

Create the working case with:

```bash
tools/create_su2_pato_test_case.sh \
  ~/SU2_PATO_COUPLING/AIR11_M23p9_PARTIAL_CAT_IMPLICIT \
  ~/SU2_PATO_CASES/AIR11_TPS_TEST_ONLY
```

The generator copies the PATO tutorial, replaces only the `top` patch of
the material temperature field `Ta` with the direct
`basicWallHeatFluxTemperature` / `mode flux` boundary, copies the exact
SU2 test-load provenance, and creates a machine-readable TEST_ONLY
manifest.

No PATO solver is run by the generator. This separates:
1. case construction,
2. case syntax/setup validation,
3. solver smoke run,
4. later physical run using a converged SU2 load.

The current direct heat-flux case is for coupling verification only.
B-prime, pyrolysis/blowing feedback, wall-temperature feedback, and
recession feedback remain later coupling levels.
