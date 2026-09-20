# SU2 NEMO -> PATO one-way coupling

This directory implements the first coupling level between the validated
SU2 NEMO external-flow solver and PATO 3.1 material response.

## Phase 1 interface

The validated SU2 surface VTU contains wall coordinates plus:

- `Pressure`
- `Temperature_tr`
- `Temperature_ve`
- `Heat_Flux`
- `MassFrac_0` ... `MassFrac_10`

The first coupling path uses the PATO
`basicWallHeatFluxTemperature` boundary condition directly:

```text
SU2 soln_surface.vtu
        |
        v
export_su2_wall.py
        |
        v
wall_loads.csv
        |
        v
write_pato_heatflux.py
        |
        v
PATO Ta patch using:
    type basicWallHeatFluxTemperature;
    mode flux;
    q ...
```

This avoids inventing a conversion from SU2 heat flux into the B-prime
variables `rhoeUeCH` and `h_r`.

## Why B-prime is deferred

PATO's B-prime model combines convective heating, recovery enthalpy,
blowing correction, pyrolysis/char advection and radiation. Those
quantities are not equivalent to a single already-computed SU2
`Heat_Flux` value. A B-prime coupling will therefore be a later,
separately validated interface.

## Heat-flux sign

The direct PATO BC uses:

```text
refGrad = q / kappa
```

for `mode flux` (ignoring optional radiation). The writer therefore
requires an explicit sign policy:

- `same`
- `flip`
- `positive-magnitude`

The initial stagnation-point material-response test should use
`positive-magnitude`, which transfers the SU2 heating magnitude without
assuming that the two solver meshes use the same outward-normal
orientation.

Before spatial sign-preserving coupling, verify the material patch
normal orientation and then use `same` or `flip`.

## Example

```bash
python3 coupling/SU2_PATO/export_su2_wall.py \
    ~/SU2_PRODUCTION/AIR11_M23p9_PARTIAL_CAT_IMPLICIT/soln_surface.vtu \
    ~/SU2_PATO_COUPLING/AIR11/wall_loads.csv

python3 coupling/SU2_PATO/validate_interface.py \
    ~/SU2_PATO_COUPLING/AIR11/wall_loads.csv

python3 coupling/SU2_PATO/write_pato_heatflux.py \
    ~/SU2_PATO_COUPLING/AIR11/wall_loads.csv \
    ~/SU2_PATO_COUPLING/AIR11/Ta.top.snippet \
    --selection max-abs \
    --sign positive-magnitude \
    --initial-temperature 550
```

The generated snippet is intentionally not inserted into a PATO case
automatically. The next step is to build a dedicated, versioned
SU2-PATO material-response case and validate one transient run.

## Scope

This phase does not:

- modify SU2 numerical source;
- rebuild SU2;
- rebuild PATO;
- convert SU2 heat flux into B-prime quantities;
- map arbitrary SU2 points to arbitrary PATO surface faces;
- implement two-way wall-temperature feedback;
- implement blowing/recession feedback.
