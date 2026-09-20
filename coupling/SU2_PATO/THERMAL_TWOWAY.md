# Thermal two-way SU2 NEMO <-> PATO interface

## Coupling level

This stage closes the thermal feedback path:

```text
SU2 q_w(s)
   -> PATO material response
   -> PATO T_w(s)
   -> PySU2 per-vertex wall temperature
   -> SU2 NEMO aerodynamic recomputation
```

Blowing, pyrolysis-gas injection and recession are later coupling levels.

## Existing SU2 infrastructure

SU2 already provides:
- `MARKER_PYTHON_CUSTOM`;
- per-marker/per-vertex `CustomBoundaryTemperature` storage;
- `CDriverBase::SetMarkerCustomTemperature(...)`;
- multigrid propagation of the custom temperature;
- custom-temperature use in wall heat-flux postprocessing.

The NEMO isothermal residual/Jacobian path previously read only the static
`MARKER_ISOTHERMAL` temperature. The integration patch makes the standard
NEMO isothermal wall use `CustomBoundaryTemperature` when
`GetMarker_All_PyCustom(val_marker)` is true. Otherwise behavior is
unchanged.

For a coupled wall the SU2 configuration therefore retains its ordinary
isothermal definition and additionally marks the wall Python-customizable,
for example:

```text
MARKER_ISOTHERMAL = ( wall, 550.0 )
MARKER_PYTHON_CUSTOM = ( wall )
```

The configured 550 K value remains an initialization/fallback value.
The coupling driver supplies the actual per-vertex temperatures.

## PATO -> SU2 temperature mapping

PATO writes one temperature value per material-surface face. The current
spatial strip has 138 top faces, while the SU2 wall polyline has 139
vertices and 138 segments.

`map_pato_temperature_to_su2.py`:
1. reads the written nonuniform `top/value` from the PATO `Ta` field;
2. associates the values with the already-validated PATO face-center
   arclengths;
3. linearly interpolates temperature onto the topology-ordered SU2 wall
   vertices;
4. preserves coordinates and arclength in the return CSV.

At the two endpoints, where no PATO face center exists exactly at the
vertex, the nearest face temperature is used.

## Important vertex-ID rule

VTK point IDs are **not** assumed to equal PySU2 marker `iVertex` indices.
The future application driver must obtain SU2 marker coordinates from the
driver API and match/interpolate them against the topology-ordered wall
profile before calling:

```text
SetMarkerCustomTemperature(iMarker, iVertex, Twall)
```

This prevents a hidden ordering assumption in the two-way interface.

## Current test data

The existing spatial PATO smoke case is driven by a non-converged SU2
development load and uses the direct heat-flux TEST_ONLY setup. Its very
large written temperatures are therefore useful only for software mapping
tests and have no physical TPS interpretation.
