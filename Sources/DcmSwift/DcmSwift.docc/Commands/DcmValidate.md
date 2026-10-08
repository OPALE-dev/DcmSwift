# DcmValidate

Validate DICOM files against the IODs of PS3.3.

```sh
DcmValidate image.dcm
DcmValidate study/ --recursive --quiet
```

For each file, DcmValidate finds the IOD of its SOP Class UID, then reports
the attributes that are missing or empty and the values outside the
Enumerated Values, each with its module and the PS3.3 table that defines it:

```text
image.dcm: 2 finding(s) against CT Image IOD Module Table
  Patient: (0010,0020) is missing (Type 2) [PS3.3 Table C.7-1]
  Image Pixel: (0028,0103) has the value "2", not one of the Enumerated Values 0000H, 0001H [PS3.3 Table C.7-11c]
```

| Option | Effect |
| --- | --- |
| `--recursive` | Also validates the files of subdirectories |
| `--quiet` | Prints only the files with findings |

The exit status is 1 when a file has findings or cannot be read. The rules
checked, and those not checked yet, are in <doc:Conformance>.
