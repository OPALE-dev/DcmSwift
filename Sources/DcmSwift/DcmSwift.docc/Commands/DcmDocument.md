# DcmDocument

Wrap PDF, CDA, STL, OBJ, and MTL documents in DICOM instances, or extract
them.

```sh
DcmDocument wrap report.pdf report.dcm --title "Discharge letter" --context image.dcm
DcmDocument extract report.dcm report.pdf
```

| Command | Effect |
| --- | --- |
| `wrap` | Writes an instance of the Encapsulated PDF, CDA, STL, OBJ, or MTL IOD, chosen by the extension (`.pdf`, `.xml` or `.cda`, `.stl`, `.obj`, `.mtl`); `--context` copies the patient and study of another file; `--title` sets Document Title |
| `extract` | Writes the document, without the padding of the Value |

STL files must be binary: the Encapsulated STL IOD does not allow ASCII STL.
