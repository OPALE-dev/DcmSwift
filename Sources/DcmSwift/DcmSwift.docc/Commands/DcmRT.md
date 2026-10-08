# DcmRT

Print the ROIs of an RT Structure Set, the dose grid of an RT Dose, or the
beams of an RT Plan.

```sh
DcmRT rtstruct.dcm
DcmRT rtdose.dcm
DcmRT rtplan.dcm --json > plan.json
```

| Object | Printed | With `--json` |
| --- | --- | --- |
| RT Structure Set | Each ROI: number, name, interpreted type, contours | Colors and every contour point |
| RT Dose | Grid size, units, type, summation, maximum dose; DVHs | Grid geometry, every dose value, DVH bins |
| RT Plan | Prescription; each beam: radiation type, control points, meterset | Fraction groups, control points |
