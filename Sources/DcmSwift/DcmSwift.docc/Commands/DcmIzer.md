# DcmIzer

Demonstrate the creation of a DICOM file from a JPEG, PNG, or TIFF image.

```sh
DcmIzer photograph.png output.dcm
```

The current image backend uses AppKit and JPEG 2000 on macOS. The generated
data set contains demonstration metadata and is not a production secondary
capture workflow. Replace the placeholder patient and instance attributes and
validate the applicable IOD before clinical use.
