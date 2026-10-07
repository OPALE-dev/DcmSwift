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

| Capability | Current status |
| --- | --- |
| Part 10 preamble and `DICM` prefix | Read and write |
| File Meta Information | Read and write; group length recalculated and SOP/Transfer Syntax identity consistency validated |
| Implicit VR Little Endian | Structural read and write |
| Explicit VR Little Endian | Structural read and write |
| Explicit VR Big Endian (retired) | Structural read and write for interoperability |
| Deflated Explicit VR Little Endian | Part 10 read/write using raw RFC 1951 Deflate; decompressed size is bounded; DIMSE negotiation not claimed |
| Encapsulated Pixel Data | Frame assembly from the Extended Offset Table, the Basic Offset Table, or the Fragment layout (PS3.5 A.4, PS3.3 C.7.6.3.1.8); RLE Lossless (Annex G) and Deflated Image Frame Compression (A.4.13) decode and encode; JPEG Lossless Process 14 (.57 and .70) decodes with every predictor, point transform, interleaved or separate component scans, and line-aligned restart intervals, and encodes 2 to 16-bit samples with any predictor, point transform, line-aligned restart intervals, and optimized Huffman tables; retired arithmetic Lossless Process 15 (.58) decodes; JPEG Baseline/Extended (.50/.51), retired progressive Huffman (.53/.55), and retired non-hierarchical arithmetic DCT (.52/.54/.56) decode sequential and progressive 8/12-bit streams with sampling factors, restart intervals, and libjpeg color detection, reproducing the IJG integer IDCT, fancy upsampling, and YCbCr conversion; Baseline/Extended additionally encode unsigned 8/12-bit monochrome and RGB frames with quality scaling, 4:4:4, 4:2:2, or 4:2:0 chroma, restart markers, optimized Huffman tables, IJG integer FDCT/quantization, and edge/dummy-block behavior verified against libjpeg-turbo; decoded color frames are returned as RGB; other syntaxes are preserved and decodable only through registered codecs |
| Native uncompressed Pixel Data | Stored values for 1 to 32 bits allocated, any High Bit, signed or unsigned, planar configurations, YBR_FULL_422 chroma, multi-frame (unpadded 1-bit frames), Float/Double Float Pixel Data, Big Endian; rendering through the PS3.3 C.11 grayscale pipeline (Modality LUT or rescale, VOI LUT or LINEAR/LINEAR_EXACT/SIGMOID window, MONOCHROME1) with Functional Group precedence, and RGB, YBR_FULL, YBR_FULL_422, and Palette Color (including segmented) to 8-bit RGB; portable PNG export |
| Unknown/private elements | Unknown implicit values preserved as UN; private creator blocks resolved within each Data Set scope |
| Defined/undefined-length sequences | Read and write; Item tags, boundaries, delimiters, nesting depth, and resource limits validated |
| Specific Character Set | All PS3.3 2026d Defined Terms (Tables C.12-2 to C.12-5), including ISO 2022 Code Extensions, GB18030-2022, and GBK; nested inheritance and local override |
| Fixed-width numeric VR values | Scalar and multi-valued signed/unsigned integer and floating-point read/write with dictionary VM validation |
| Lazy Bulk Data | Opt-in file-backed references and bounded reads for defined-length binary VRs and encapsulated Pixel Data Items |
| DICOM JSON / Native DICOM Model XML | Existing convenience output is not PS3.18 conformant |
| Basic DICOMDIR | Legacy PATIENT/STUDY/SERIES/IMAGE and generic typed record-tree read/write; lossless view of all current F.4-1 types; serialized Item offsets, complete reachability, all unconditional top-level F.5 keys, common Type 1C keys, File-set/File IDs, consistency flag, and referenced Part 10 identities can be validated |
| PS3.12 media profiles | Not qualified; no media-profile conformance claim |

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
