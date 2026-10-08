# DcmAnonymize

Write an anonymized copy of a DICOM Part 10 file.

```sh
DcmAnonymize source.dcm anonymized.dcm
```

Always retain the source until the output has been reviewed. De-identification
is context dependent: applications remain responsible for checking private
attributes, burned-in annotations, pixel data, structured content, and any
site-specific identifiers before disclosure.
