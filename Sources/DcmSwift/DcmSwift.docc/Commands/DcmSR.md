# DcmSR

Inspect a DICOM Structured Report, or make a TID 1500 Measurement Report.

```sh
DcmSR dump report.dcm
DcmSR html report.dcm report.html
DcmSR json report.dcm > tree.json
DcmSR measure --image ct1.dcm --observer "Doe^Jane" \
    --measurement "lesion1=118565006,SCT,Volume:12.5:cm3" --output report.dcm
```

| Command | Effect |
| --- | --- |
| `dump` | Prints the content tree |
| `html` | Renders the report as HTML |
| `json` | Prints the content tree as JSON: relationship, value type, concept name, value, children |
| `measure` | Writes a Comprehensive 3D SR Measurement Report (TID 1500) of the `--image` files: each `--measurement name=code,scheme,meaning:value:units` goes into the Measurement Group (TID 1501) tracked by `name`, with UCUM units |

Run `DcmSR help <command>` for each command's options.
