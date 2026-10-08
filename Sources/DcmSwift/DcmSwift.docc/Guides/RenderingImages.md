# Rendering Images

Decode Pixel Data, apply the grayscale or color pipeline, and export images on
every platform.

## Render a frame

``DICOMImageRenderer`` interprets Pixel Data and produces 8-bit gray or RGB
pixels:

```swift
let file = DicomFile(forPath: path)!
let renderer = try DICOMImageRenderer(dataset: file.dataset)

let ct = try renderer.render(frame: 0)   // first window, VOI LUT, or identity
let bone = try renderer.render(options: DICOMRenderingOptions(
    voi: .window(DICOMWindow(center: 400, width: 1800))))

try bone.pngData().write(to: outputURL)
let hounsfield = try renderer.modalityValues(frame: 0)
```

| Feature | Support |
| --- | --- |
| Grayscale pipeline | Modality LUT or rescale, then VOI LUT or a LINEAR, LINEAR_EXACT, or SIGMOID window; MONOCHROME1 |
| Color | RGB, YBR_FULL, YBR_FULL_422, Palette Color (including segmented) |
| Samples | 1 to 32 bits, float and double, Big Endian |
| Frames | Multi-frame images; window and VOI LUT values come from the Per-Frame or Shared Functional Groups before the top-level attributes |

Overlays, shutters, Pixel Padding, Presentation States, and ICC profiles are
not applied yet; see <doc:DeferredLimitations>.

## Export

A rendered image exports to portable formats on every platform:

| Method | Format |
| --- | --- |
| `pngData()` | 8-bit grayscale or RGB PNG |
| `jpegData(quality:)` | Baseline JPEG, quality 1 to 100 |
| `tiffData()` | Uncompressed TIFF |
| `pnmData()` | PGM for grayscale, PPM for RGB |

Only the `CGImage`, `NSImage`, and `UIImage` conveniences of ``DicomImage`` are
Apple-specific. <doc:DcmConvert> wraps this API in a command-line tool.

## Stored values and codecs

``DICOMNativePixelData`` exposes stored values frame by frame without loading
file-backed Bulk Data.

Instances in a JPIP Referenced Transfer Syntax hold a Pixel Data Provider
URL instead of Pixel Data. ``DICOMJPIPClient`` retrieves their frames over
JPIP; `resolve(_:)` returns the same instance with JPEG 2000 or HTJ2K
encapsulated Pixel Data, which renders like any other:

```swift
let resolved = try await DICOMJPIPClient().resolve(file.dataset)
let image = try DICOMImageRenderer(dataset: resolved).render(frame: 0)
```

Encapsulated Pixel Data is decoded frame by frame by the codec registered for
its Transfer Syntax. Frames are located through the Extended or Basic Offset
Table, or from the Fragment layout. Every codec listed in <doc:Conformance> is
built in; applications can register others with
`DICOMCodecRegistry.register(_:)`. A Transfer Syntax without a codec reports
`DICOMPixelDataError.encapsulatedPixelData`.
