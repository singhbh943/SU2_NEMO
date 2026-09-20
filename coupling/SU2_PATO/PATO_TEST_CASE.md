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

## Execution-path smoke validation

The first generated `TEST_ONLY` case was successfully exercised with the
source-built PATOx using OpenFOAM 7. The isolated smoke case used two
timesteps of `1e-12 s`.

The execution path reached:

```text
blockMesh
  -> PATOx
  -> PureConduction EnergyModel
  -> Ta linear solve
  -> time = 1e-12 s
  -> time = 2e-12 s
```

This validates the software plumbing from the exported SU2 wall load to
the PATO temperature boundary and solver execution. It does **not**
validate physical TPS temperatures because the current SU2 load package
comes from a non-converged development solution.

OpenFOAM normally prints:

```text
sigFpe : Enabling floating point exception trapping (FOAM_SIGFPE).
```

at startup. This is not a floating-point crash. The permanent smoke
runner detects only actual fatal signatures such as `FOAM FATAL ERROR`,
`Segmentation fault`, or a real `Floating point exception (core dumped)`.

## Converged-load production gate

A permanent production gate is provided by:

```bash
tools/prepare_su2_pato_converged_load.sh \
    <su2_case_dir> \
    <convergence_log> \
    <output_dir> \
    [initial_wall_temperature_K]
```

The tool never runs SU2 or PATO. It refuses to produce a production load
package when the supplied SU2 log contains explicit non-convergence
evidence or when convergence cannot be positively verified.

Only after the convergence gate passes does it:

1. export `soln_surface.vtu`;
2. validate pressure, temperatures, heat flux and AIR11 mass fractions;
3. create the direct PATO `basicWallHeatFluxTemperature` point-load snippet;
4. record SHA256 hashes of the SU2 VTU, convergence log and exported CSV;
5. write `SU2_PATO_CONVERGED_LOAD_MANIFEST.json`.

The generated direct PATO load is explicitly scoped as a **1-D maximum
absolute wall-heat-flux point load**. Full spatial face-to-face mapping
is a later coupling stage.

The earlier `AIR11_TPS_TEST_ONLY` and smoke cases remain non-physical
development artifacts and are not promoted by this gate.
