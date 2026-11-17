# DcmSeg

Print Segmentations and Parametric Maps, or make a binary Segmentation:

```sh
DcmSeg show segmentation.dcm
DcmSeg make --source ct1.dcm --source ct2.dcm --box liver:10,10,40,40:0,1 --output seg.dcm
```

See the [complete guide](../DcmSwift/DcmSwift.docc/Commands/DcmSeg.md).
