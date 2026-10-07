# DcmSwift DICOM Conformance Statement (working draft)

Edition: DICOM 2026d  
Implementation: DcmSwift 2.0 development branch  
Status: incomplete implementation statement; not a claim of full DICOM
conformance

All deliberately deferred gaps are tracked in
`Documentation/DICOM_DEFERRED_LIMITATIONS.md`; they are not implied to be
covered by broader structural claims in this document.

## Implementation model

DcmSwift is a Swift library with command-line examples. It currently provides
an in-memory Data Set model, Part 10 file parsing/writing, partial encapsulated
Pixel Data preservation, and an experimental DICOM Upper Layer/DIMSE stack.

The PS3.6 registry bundled at runtime contains 5,303 data-element entries and
1,990 UID entries generated from the 2026d DocBook source. Command-set elements
are temporarily supplied by the legacy embedded registry because they are
defined by PS3.7 rather than the PS3.6 data-element registry.

## File and Data Set support

### Part 10 files and Transfer Syntaxes

| Capability | Current status |
| --- | --- |
| Part 10 preamble and `DICM` prefix | Read and write |
| File Meta Information | <ul><li>Read and write</li><li>Group length recalculated and SOP/Transfer Syntax identity consistency validated</li></ul> |
| Implicit VR Little Endian | Structural read and write |
| Explicit VR Little Endian | Structural read and write |
| Explicit VR Big Endian (retired) | Structural read and write for interoperability |
| Deflated Explicit VR Little Endian | <ul><li>Part 10 read/write using raw RFC 1951 Deflate</li><li>Decompressed size is bounded</li><li>DIMSE negotiation not claimed</li></ul> |

### Data elements

| Capability | Current status |
| --- | --- |
| Unknown/private elements | <ul><li>Unknown implicit values preserved as UN</li><li>Private creator blocks resolved within each Data Set scope</li></ul> |
| Defined/undefined-length sequences | <ul><li>Read and write</li><li>Item tags, boundaries, delimiters, nesting depth, and resource limits validated</li></ul> |
| Specific Character Set | <ul><li>All PS3.3 2026d Defined Terms (Tables C.12-2 to C.12-5), including ISO 2022 Code Extensions, GB18030-2022, and GBK</li><li>Nested inheritance and local override</li></ul> |
| Text and Person Name values | <ul><li>Typed multi-valued character-string read/write</li><li>PN alphabetic, ideographic, and phonetic groups with five named components</li><li>Interior empty Values, groups, and components preserved</li></ul> |
| Fixed-width numeric VR values | Scalar and multi-valued signed/unsigned integer and floating-point read/write with dictionary VM validation |
| Lazy Bulk Data | Opt-in file-backed references and bounded reads for defined-length binary VRs and encapsulated Pixel Data Items |

### Pixel Data

| Capability | Current status |
| --- | --- |
| Encapsulated Pixel Data | <ul><li>Frame assembly from the Extended Offset Table, the Basic Offset Table, or the Fragment layout (PS3.5 A.4, PS3.3 C.7.6.3.1.8)</li><li>JPEG 2000 Part 2 multi-frame images decoded by component collection, each starting a Fragment (PS3.5 A.4.4)</li><li>Built-in codecs are listed below; other syntaxes are preserved and decodable only through registered codecs</li></ul> |
| Native uncompressed Pixel Data | <ul><li>Stored values for 1 to 32 bits allocated, any High Bit, signed or unsigned, planar configurations, YBR_FULL_422 chroma, multi-frame (unpadded 1-bit frames), Float/Double Float Pixel Data, Big Endian</li><li>Rendering through the PS3.3 C.11 grayscale pipeline (Modality LUT or rescale, VOI LUT or LINEAR/LINEAR_EXACT/SIGMOID window, MONOCHROME1) with Functional Group precedence</li><li>RGB, YBR_FULL, YBR_FULL_422, and Palette Color (including segmented) to 8-bit RGB</li><li>Portable PNG export</li></ul> |

Built-in codecs, written in Swift except JPEG 2000, HTJ2K, and JPEG XL, which
use the vendored OpenJPEG 2.5.4, OpenJPH 0.32.0, and libjxl 0.12.0 (UIDs
abbreviate `1.2.840.10008.1.2.4`):

| Transfer Syntax | Decode | Encode | Details |
| --- | :-: | :-: | --- |
| RLE Lossless (PS3.5 Annex G) | ✓ | ✓ | Every layout |
| Deflated Image Frame Compression (A.4.13) | ✓ | ✓ | |
| JPEG Baseline and Extended (.50, .51) | ✓ | ✓ | <ul><li>Decode: sequential and progressive 8/12-bit streams with sampling factors, restart intervals, and libjpeg color detection; IJG integer IDCT, fancy upsampling, and YCbCr conversion, bit-exact with libjpeg-turbo</li><li>Encode: unsigned 8/12-bit monochrome and RGB, quality scaling, 4:4:4, 4:2:2, or 4:2:0 chroma, restart markers, optimized Huffman tables, IJG integer FDCT and quantization</li><li>Color frames are returned as RGB</li></ul> |
| Retired JPEG DCT (.52 to .56) | ✓ | | Progressive Huffman (.53, .55) and arithmetic (.52, .54, .56), as above |
| JPEG Lossless (.57, .70) | ✓ | ✓ | <ul><li>Decode: every predictor and point transform, interleaved or separate component scans, line-aligned restart intervals</li><li>Encode: 2 to 16-bit samples, any predictor and point transform, line-aligned restart intervals, optimized Huffman tables</li></ul> |
| Retired JPEG Lossless, arithmetic (.58) | ✓ | | Statistics areas shared per table (T.81 B.2.3) |
| Retired JPEG hierarchical (.59 to .66) | ✓ | | <ul><li>T.81 Annex J: Huffman and arithmetic, sequential, progressive, and lossless first and differential frames, with expansion</li><li>Within a stated tolerance of the ISO reference software</li></ul> |
| JPEG-LS Lossless and Near-Lossless (.80, .81) | ✓ | ✓ | <ul><li>Decode: every interleave mode, near-lossless coding, LSE preset parameters, restart intervals, HP color transforms</li><li>Encode: 2 to 16-bit frames with default parameters, any NEAR, any interleave mode, restart intervals; byte-identical to CharLS</li></ul> |
| JPEG 2000 Lossless and lossy (.90, .91) | ✓ | ✓ | <ul><li>Decode: raw codestreams and JP2 files, signed and unsigned samples up to 16 bits in 8 or 16-bit cells; frames using the multiple-component transform are returned as RGB</li><li>Encode: reversible 5/3 (YBR_RCT for color) or irreversible 9/7 with a compression ratio or PSNR target (YBR_ICT for color)</li><li>Subsampled components are rejected</li></ul> |
| JPEG 2000 Part 2 multi-component (.92, .93) | ✓ | ✓ | <ul><li>ISO/IEC 15444-2 Annex J: array-based decorrelation and dependency transforms, reversible or irreversible, 5-3 and 9-7 wavelet transforms across components, component collections and reordering, null components, several stages, MCT and MCC series over several segments, tile-part overrides</li><li>The components of each codestream are the samples of consecutive frames; YBR_RCT and YBR_ICT frames are returned as RGB</li><li>Other Part 2 extensions, which PS3.5 forbids, are rejected</li><li>Encode: grayscale 1 to 16-bit frames in collections of consecutive frames, decorrelated by a reversible 5-3 (lossless) or irreversible 9-7 wavelet across frames, with a compression ratio or approximate PSNR target</li></ul> |
| HTJ2K (.201, .202, .203) | ✓ | ✓ | <ul><li>Decode through OpenJPEG, as for JPEG 2000</li><li>Encode through OpenJPH: reversible (.201), reversible RPCL with TLM markers and a base resolution of at most 64 (.202), or irreversible with a quantization step (.203); YBR_RCT or YBR_ICT for color</li></ul> |
| JPEG XL (.110, .111, .112) | ✓ | | <ul><li>Decode through libjxl from raw codestreams or containers</li><li>Lossless, lossy, and reversible JPEG recompression streams yield native grayscale or interleaved RGB pixels</li><li>Unsigned integer samples up to 16 bits; image dimensions, channel count, and bit depth are checked against the DICOM attributes</li></ul> |

### Media and other representations

| Capability | Current status |
| --- | --- |
| Basic DICOMDIR | <ul><li>Legacy PATIENT/STUDY/SERIES/IMAGE and generic typed record-tree read/write</li><li>Lossless view of all current F.4-1 types</li><li>Validation of serialized Item offsets, complete reachability, all unconditional top-level F.5 keys, common Type 1C keys, File-set/File IDs, the consistency flag, and referenced Part 10 identities</li></ul> |
| PS3.12 media profiles | Not qualified; no media-profile conformance claim |
| DICOM JSON / Native DICOM Model XML | Existing convenience output is not PS3.18 conformant |

Known UIDs are not automatically supported. `TransferSyntaxCapability` is the
authoritative programmatic statement for structural I/O, Pixel Data
preservation, codec operations, and DIMSE negotiation.

The next file-core priorities are remaining semantic VR validation, broader
DICOMDIR Directory Record coverage, and PS3.12 media-profile qualification.
Deflated DIMSE negotiation remains separate network work.
PS3.18 JSON and XML representations follow those binary-format milestones.

The Basic DICOMDIR implementation uses Explicit VR Little Endian, defined
length Directory Record Sequence Items, and offsets that reference Item Tags.
It rejects dangling, cyclic, duplicate, or orphan graph references, invalid
PS3.3 Table F.4-1 record relationships, and Referenced File IDs outside the
PS3.10 one-to-eight component syntax. PRIVATE records require their defining
UID and retired record types remain observable. Unknown, retired, and
misplaced Directory Record Types are reported by structure validation but do
not prevent loading: their records and lower-level entities stay in the parsed
hierarchy, while graph-integrity errors still fail closed. Retired types,
including HL7 STRUC DOC, only produce warnings and do not constrain the types
below them. A public read-only tree view
reconstructs reachable records from the encoded offsets and returns no partial
tree for malformed or orphaned graphs. Explicit
file-set integrity validation checks unique contained targets and their SOP
Class, SOP Instance, and Transfer Syntax identities. It does not yet claim
complete conditional and nested macro qualification for every Directory Record
type, File-set update semantics, descriptor content decoding, remaining
record-specific conditional F.5 keys, or any specific media storage application
profile.
Unconditional top-level Type 1 and Type 2 keys are represented for every
current F.5 record type, including attributes from the Content Identification
and Scope of Inventory Macros. Common Type 1C validation covers PRIVATE record UIDs,
referenced-SOP identity tuples, extended character sets in record keys, present
non-empty conditional keys, verified SR documents, and Hanging Protocol
Definition Items. File-set integrity validation additionally enforces Related
General SOP Class UID and selected F.5 conditions mirrored by the referenced
SOP Instance. Deeper IOD/module-dependent conditions remain deferred. The
optional File-set Descriptor File ID and
character-set declaration are preserved, and the descriptor target can be
checked for containment and
existence.

The generic writer has synthetic round-trip coverage for all 35 current F.4-1
types populated with their unconditional top-level Type 1/2 keys, including
those introduced by included macros. This is not a claim that every conditional
or nested included-macro rule or referenced-IOD condition is qualified.
Basic and Enhanced Coded Entry attributes are recursively validated in code
sequences, including code-value choice, meaning, scheme, Context Group, and
extension provenance conditions. SOP Instance Reference Macros explicitly
included by F.5 Presentation and Waveform Presentation records require a
non-empty referencing Sequence and both Type 1 UIDs in each Item. Scope of Inventory validation covers the
outer Sequence cardinality, RELATIONAL and TIMEZONE_ADJUST dependencies, and
the cardinality of present matching Sequences. Conditions that depend on
knowing which matching operations were applied remain outside this claim.
Optional Icon Image Keys enforce the F.7 single-Item and restricted Image Pixel
rules, including required attributes, monochrome or palette encoding, bit/high
bit/unsigned representation constraints, native Pixel Data length, and presence
of palette descriptors and data. Palette LUT content consistency and external
viewer qualification remain deferred.

## Network support

The network implementation is experimental and is not yet advertised as a
conformant Application Entity. C-ECHO has the most complete path. C-STORE and
C-FIND contain partial SCU/SCP building blocks. C-MOVE, C-GET, C-CANCEL,
Storage Commitment, role selection, extended negotiation, robust
fragmentation/reassembly, and a complete association-state test matrix are not
implemented or not qualified.

No network transfer syntax is considered negotiable unless its capability has
`canNegotiateForDIMSE == true`. This flag does not by itself claim that every
DIMSE service is implemented.

## Character sets

Text decoding follows Specific Character Set (0008,0005). Every Defined Term of
PS3.3 2026d C.12.1.1.2 is supported for reading and writing:

- single-byte repertoires ISO_IR 100, 101, 109, 110, 144, 127, 126, 138, 148,
  203, 13 (JIS X 0201 romaji and katakana), and 166 (TIS 620);
- ISO 2022 Code Extensions with the same single-byte sets and the multi-byte
  sets ISO-IR 87 (JIS X 0208), 159 (JIS X 0212), 149 (KS X 1001), and 58
  (GB 2312), following the PS3.5 6.1.2.5 restrictions: G0 in GL, G1 in GR, no
  shifts, and Value 1 active at the start of each value, line, page, and
  Person Name component;
- ISO_IR 192 (UTF-8, minimal encodings only), GB18030 (2022 edition), and GBK.

Only a single-byte 05/12 separates values, so multi-byte characters containing
5CH are never split; under ISO_IR 13 that byte is YEN SIGN inside ST, LT, and UT.
Decoding uses tables generated by `Scripts/generate-character-set-tables.py`
and bundled with the package, so macOS, iOS, and Linux behave identically. The
writer designates a character set just before its first use in each line,
value, or component and restores the Value 1 sets before every delimiter and
Control Character. The reader also accepts escape sequences for DICOM-defined
sets that the declaration does not list.

Unknown or invalid declarations (an unknown Defined Term, a multi-byte set as
Value 1, Code Extensions combined with ISO_IR 192, GB18030, or GBK) remain
observable as unsupported and are never decoded as UTF-8. Bytes that the
declared repertoire cannot represent make the value undecodable rather than
partially decoded. Nested Data Sets inherit the enclosing repertoire and may
override it locally without affecting sibling Items.

Qualification uses the PS3.5 Annex H, I, J, and K examples byte for byte and
the DCMTK character-set test files, whose decoding matches pydicom 3.0.2.

## Security

No TLS profile, application authentication, ATNA audit trail, digital signature,
encrypted-attribute, or de-identification-profile conformance is currently
claimed. Applications embedding DcmSwift are responsible for access control,
transport security, persistence, and audit until these capabilities are
implemented and documented.

## Validation boundaries

Dictionary lookup and binary parsing do not establish IOD conformance. Full
PS3.3 module/IOD validation, PS3.16 context-group validation, and application
profile validation remain separate future layers. A successfully parsed file
must therefore not be reported as clinically or semantically conformant solely
on that basis.

## Qualification policy

A capability moves from planned to supported only when it has normative test
vectors, malformed-input tests, round-trip tests where applicable, and an
interoperability result against an independent DICOM implementation. This
document and the executable capability registry must change together.
