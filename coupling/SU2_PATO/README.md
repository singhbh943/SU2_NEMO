# Integrated SU2-PATO Two-Way Coupling

This directory contains the coupling layer installed with the unified SU2/NEMO/PATO distribution.

The persistent runtime exchanges:

1. PATO wall temperature → PySU2 custom wall temperature.
2. Persistent SU2 advancement.
3. PySU2 wall-normal heat-flux extraction.
4. Conservative SU2 wall-vertex → PATO face heat-flux mapping.
5. PATO material-response advancement.
6. PATO wall-face temperature → SU2 wall-vertex mapping.
7. Repeat without reconstructing the PySU2 driver.

The runtime imported for the unified v0.1.0 line comes from validated SU2-PATO-Coupling commit `57ef14be32a4db4dedcfd8a2f6550299fe456ea0`.

The current persistent implementation is specific to the validated AIR11 interface cardinalities: 139 SU2 wall vertices and 138 PATO faces. Validate geometry, face/vertex ordering, heat-flux sign, `Q_SCALE`, and `PATO_DT` before production use.

Installed command:

```bash
su2-pato --su2-case /path/to/su2/case --pato-case /path/to/pato/case
```
