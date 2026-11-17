# DcmConvert

`DcmConvert` is a small cross-platform demonstrator for rendering DICOM images
with DcmSwift and exporting them to ordinary image files.

## Build and basic use

```sh
swift build -c release --product DcmConvert
.build/release/DcmConvert INPUT OUTPUT --format FORMAT
```

`INPUT` may be one DICOM file or a directory. `OUTPUT` may be an exact image
path for a single input file, or a directory. Batch conversion always treats it
as a directory and preserves the relative input layout.

Supported `FORMAT` values are:

- `png`: lossless 8-bit grayscale or RGB PNG;
- `jpeg`: baseline JPEG, controlled by `--quality` (1–100, default 90);
- `tiff`: lossless, uncompressed 8-bit grayscale or RGB TIFF;
- `pnm`: lossless PGM for grayscale or PPM for RGB.

Rendered files contain pixels, not the complete DICOM data set. Patient,
study, acquisition, geometry, calibration, and other DICOM attributes are not
copied into these image formats. Keep the source DICOM instance.

## Files and frames

For a single-frame input and an output filename, that filename is used exactly:

```sh
DcmConvert image.dcm preview.png --format png
```

For a multi-frame input, all frames are exported by default with one-based,
zero-padded suffixes:

```text
series_0001.tiff
series_0002.tiff
series_0003.tiff
```

Use `--frame N` to export only the one-based frame `N`.

## Batch conversion

The default directory mode inspects files directly inside `INPUT`. Add
`--recursive` to include subdirectories:

```sh
DcmConvert /data/incoming /data/previews --format jpeg --quality 85 --recursive
```

Non-DICOM files are skipped. DICOM files that cannot be rendered are reported
as failures. `--verbose` prints each written or skipped path. Relative
subdirectories are preserved, so `INPUT/patient/study/image.dcm` becomes
`OUTPUT/patient/study/image.png` for a single-frame PNG conversion.

Existing output files cause a failure; pass `--overwrite` to replace them.

## Rendering choices

By default, DcmSwift uses the first applicable DICOM window, VOI LUT, or the
identity mapping. For an explicit grayscale window:

```sh
DcmConvert ct.dcm lung.png --format png \
  --window-center -600 --window-width 1500
```

Both window options are required together. `--minimum-maximum` instead maps the
actual minimum and maximum values in each frame and cannot be combined with an
explicit window.

## Exit status and summary

The command prints a final count of converted DICOM files, exported frames,
skipped non-DICOM files, and failures. It exits with status 1 when no DICOM file
was converted or when any requested conversion failed; otherwise it exits with
status 0.
