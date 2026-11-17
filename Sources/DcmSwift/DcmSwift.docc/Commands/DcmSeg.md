# DcmSeg

Print Segmentations and Parametric Maps, or make a binary Segmentation.

```sh
DcmSeg show segmentation.dcm
DcmSeg show adc-map.dcm --json > values.json
DcmSeg make --source ct1.dcm --source ct2.dcm --source ct3.dcm --box tumor:10,10,40,40:0,2 --output seg.dcm
```

| Command | Effect |
| --- | --- |
| `show` | A Segmentation's type, size, and segments with their frames; a Parametric Map's size, frames, and units; `--json` adds every frame's mask or values |
| `make` | A BINARY Segmentation of the `--source` images: each `--box label:x0,y0,x1,y1:first,last` is a segment covering columns x0 to x1 − 1 and rows y0 to y1 − 1 of the source images first to last, counted from 0 |

Applications make Segmentations of any mask with `DICOMSegmentation.binary`.
