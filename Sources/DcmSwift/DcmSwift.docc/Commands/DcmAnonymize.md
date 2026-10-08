# DcmAnonymize

De-identify DICOM files with the Basic Application Level Confidentiality
Profile of PS3.15 Annex E.

```sh
DcmAnonymize source.dcm anonymized.dcm
DcmAnonymize study/ anonymized/ --key study.key --retain-modified-dates
```

With a directory, every DICOM file under it is written under the destination
with the same relative path. Files de-identified with the same `--key` file get
the same replacement UIDs, so a study de-identified in several runs stays whole;
without it, a random secret is used for the run.

| Option | Profile option (PS3.15 E.3) |
| --- | --- |
| `--retain-safe-private` | Retain Safe Private: keeps the private attributes of Table E.3.10-1 |
| `--retain-uids` | Retain UIDs |
| `--retain-device-identity` | Retain Device Identity |
| `--retain-institution-identity` | Retain Institution Identity |
| `--retain-patient-characteristics` | Retain Patient Characteristics |
| `--retain-full-dates` | Retain Longitudinal Temporal Information with Full Dates |
| `--retain-modified-dates` | Retain Longitudinal Temporal Information with Modified Dates; `--date-shift` sets the days, derived from the key otherwise |

Pixel Data is not inspected: burned-in annotations remain, so the Clean Pixel
Data and Clean Recognizable Visual Features Options are not claimed. Always
retain the source until the output has been reviewed.
