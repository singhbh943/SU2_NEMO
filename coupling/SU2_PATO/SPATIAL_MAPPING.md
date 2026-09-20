# Spatial SU2 NEMO -> PATO mapping

## Purpose

The first one-way PATO case used one maximum-wall-heating value. This
stage transfers the complete SU2 wall heat-flux distribution to a
multi-face PATO material surface.

## Why VTU point order is not used

`soln_surface.vtu` stores wall line-cell connectivity separately from
point data. Spatial coupling therefore reconstructs the wall chain from
VTK `connectivity`, `offsets`, and `types` rather than assuming that VTK
point IDs are already ordered by wall arclength.

`extract_su2_wall_profile.py` writes a topology-ordered profile with
cumulative arclength `s`.

## Conservative face mapping

`map_su2_profile_to_pato_faces.py` treats each source field as
piecewise-linear in wall arclength. For every PATO target face it computes
the exact interval average.

For heat flux,

```text
q_face = (1 / Delta_s) integral_face q(s) ds
```

so

```text
sum(q_face Delta_s)
```

matches the source piecewise-linear integral to numerical roundoff.

## PATO boundary

The PATO `basicWallHeatFluxTemperature` boundary accepts `q` as a
`scalarField`. Therefore a `nonuniform List<scalar>` can be supplied
directly with one value per material-surface face.

This is preferable for the direct heat-flux coupling level to routing
the already-computed SU2 heat flux through PATO's separate
`boundaryMapping` fixed-value field machinery.

## TEST_ONLY strip

The initial spatial validation case uses a straight material strip:
- x = SU2 cumulative wall arclength;
- y = material depth;
- z = thin extruded width;
- `top` = spatially heated PATO surface.

The current AIR11 source run is non-converged, therefore the generated
case is explicitly `TEST_ONLY` and is not a physical TPS result.

The future production workflow uses the same topology and conservative
mapping code only after the SU2 convergence gate passes.

## Spatial PATO execution smoke

The first spatial TEST_ONLY case was successfully executed with the
source-built PATOx using OpenFOAM 7.

Validated execution facts:

- PATO `top` patch contains 138 faces;
- OpenFOAM patch-face order is low-x to high-x;
- the 138-value nonuniform `q` list matches the mapped face CSV exactly;
- PATOx accepts the spatial `basicWallHeatFluxTemperature` field;
- `Ta` is solved at `1e-12 s` and `2e-12 s`;
- the final `Ta` field is written successfully.

The source aerodynamic solution remains non-converged, so this validates
software execution and spatial data alignment only. It is not a physical
TPS result.

The next coupling level is thermal two-way feedback:

```text
SU2 q_w(s)
   -> PATO material response
   -> PATO T_w(s)
   -> SU2 isothermal wall temperature
   -> recomputed aerodynamic q_w(s)
```

That feedback must preserve the same topology/arclength orientation and
must not use a non-converged SU2 load as a production state.
