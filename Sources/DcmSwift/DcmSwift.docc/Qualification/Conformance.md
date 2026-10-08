# DcmSwift DICOM Conformance Statement (working draft)

Edition: DICOM 2026d  
Implementation: DcmSwift 2.0 development branch  
Status: incomplete implementation statement; not a claim of full DICOM
conformance

All deliberately deferred gaps are tracked in the
[limitations register](DeferredLimitations.md); they are not implied to be
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
| Deflated Explicit VR Little Endian | <ul><li>Part 10 read/write using raw RFC 1951 Deflate</li><li>Decompressed size is bounded</li><li>Negotiated on DIMSE associations; network data sets inflated and deflated in memory</li></ul> |

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
| JPIP Referenced (.94, .95, .204, .205; PS3.5 8.4.1, A.6, A.7, A.11, A.12) | ✓ | | <ul><li><code>DICOMJPIPClient</code> requests each frame at full resolution and quality from the Pixel Data Provider URL, frame N as code stream N of a multi-frame image</li><li>JPP-streams and JPT-streams, and image/jp2, image/jph, and image/jphc responses (ISO/IEC 15444-9 Annex A)</li><li>Sessions continue the transfer when the server ends a response at a byte or response limit</li><li>A JPP-stream is rebuilt as a codestream in the RPCL progression, without SOP, TLM, PLM, PLT, and POC markers</li><li><code>resolve(_:)</code> turns the instance into JPEG 2000 or HTJ2K encapsulated Pixel Data</li><li>The deflated variants are inflated like Deflated Explicit VR Little Endian</li></ul> |
| JPEG XL (.110, .111, .112) | ✓ | ✓ | <ul><li>Decode through libjxl from raw codestreams or containers</li><li>Lossless, lossy, and reversible JPEG recompression streams yield native grayscale or interleaved RGB pixels; the original JPEG bitstream of a recompression frame can also be rebuilt</li><li>Unsigned integer samples up to 16 bits; image dimensions, channel count, and bit depth are checked against the DICOM attributes</li><li>Encode: unsigned MONOCHROME1/2 (1 to 16 bits) and RGB (8 to 16 bits), lossless (.110) or at a Butteraugli distance (.112); lossless recompression of 8-bit JPEG frames with their reconstruction data (.111)</li></ul> |

### Media and other representations

| Capability | Current status |
| --- | --- |
| Basic DICOMDIR | <ul><li>Legacy PATIENT/STUDY/SERIES/IMAGE and generic typed record-tree read/write</li><li>Lossless view of all current F.4-1 types</li><li>Validation of serialized Item offsets, complete reachability, all unconditional top-level F.5 keys, common Type 1C keys, File-set/File IDs, the consistency flag, and referenced Part 10 identities</li></ul> |
| PS3.12 media profiles | Not qualified; no media-profile conformance claim |
| DICOM JSON Model | PS3.18 Annex F, encode and decode (see below) |
| Native DICOM Model XML | PS3.19 A.1, encode and decode (see below) |

Known UIDs are not automatically supported. `TransferSyntaxCapability` is the
authoritative programmatic statement for structural I/O, Pixel Data
preservation, codec operations, and DIMSE negotiation.

The next file-core priorities are remaining semantic VR validation, broader
DICOMDIR Directory Record coverage, and PS3.12 media-profile qualification.
### Native DICOM Model (PS3.19 A.1)

| Rule | Behavior |
| --- | --- |
| Document | <ul><li>UTF-8, namespace <code>http://dicom.nema.org/PS3.19/models/NativeDICOM</code>, <code>xml:space="preserve"</code> as A.1.4 requires (the normative schema omits it)</li><li>Attributes in tag order, with <code>keyword</code> for dictionary attributes; Group Lengths left out</li></ul> |
| Values | <ul><li>Same value rules as DICOM JSON, through the PS3.18 F.3 mapping</li><li>Numbered Value, Item, and PersonName elements; empty Values as empty elements</li><li>Person Names split into FamilyName, GivenName, MiddleName, NamePrefix, NameSuffix</li><li>IS and DS as written</li></ul> |
| Private elements | <code>gggg00ee</code> tags with <code>privateCreator</code>; Private Creator elements implied, blocks reassigned in order of appearance on decoding |
| Decoding | Foundation <code>XMLParser</code> (FoundationXML on Linux); numbers may be out of order; CDATA accepted; repeated or invalid numbers, unknown namespaces, and malformed attributes rejected |

### DICOM JSON Model (PS3.18 Annex F)

| Rule | Behavior |
| --- | --- |
| Structure | <ul><li>Attributes keyed by uppercase tag, in plain lexicographic order</li><li>Group Length attributes left out; File Meta Information on request</li><li>Several data sets as one top-level array</li></ul> |
| Values | <ul><li>Empty attributes without Value; empty Values as <code>null</code>; empty Items as <code>{}</code></li><li>PN by component group; AT as eight hexadecimal digits</li><li>IS and DS as numbers, or as their trimmed strings on request; non-finite FL/FD as the strings NaN, Infinity, -Infinity (JSON has no such numbers)</li></ul> |
| Binary data | <ul><li>InlineBinary in Little Endian, or a BulkDataURI chosen by the caller</li><li>Encapsulated Pixel Data as its Items, without the Sequence Delimitation Item</li><li>Decoding loads BulkDataURI values through a caller-supplied loader</li></ul> |
| UN | Written with the dictionary VR when it is unambiguous (PS3.5 6.2.2): Values decoded, Sequences read as Implicit VR Little Endian, Private Creators as LO; unknown private elements stay UN |
| Decoding | Strings encoded in the object's Specific Character Set, padded to even lengths; mixing Value, InlineBinary, and BulkDataURI, wrong types, and delimiter characters in multi-valued strings are rejected |

### Reading files other toolkits read

| Case | Behavior |
| --- | --- |
| Preamble | Any 128 bytes before <code>DICM</code> (PS3.10 7.1), e.g. a TIFF header |
| Implicit VR data set labelled Explicit VR | Detected on the first data set element and read as Implicit VR, with a warning |
| Undefined-length UN, or unknown element in Implicit VR | Read as a Sequence in Implicit VR Little Endian (PS3.5 6.2.2) |
| Ambiguous VRs in Implicit VR | OB/OW as OW (encapsulated Pixel Data as OB); US/SS from Pixel Representation |
| Deflated data set | A trailing gzip CRC-32 and size that match the inflated data are accepted |
| Trailing bytes | Fewer than a tag's four bytes end the data set; an unreadable element is an error, never a loop |
| Truncated files | Rejected, where pydicom returns the part it could read |

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

The network stack (`Sources/DcmSwift/Network`) is built on SwiftNIO with
`NIOAsyncChannel`; the PS3.8 state machine is a value type tested without
sockets.

### Upper Layer (PS3.8)

| Area | Behavior |
| --- | --- |
| PDUs | <ul><li>All seven PDU types and every item and sub-item of PS3.8 9.3 and PS3.7 D.3.3</li><li>Unknown User Information sub-items preserved</li><li>Byte-exact with pynetdicom 3.0.4 encodings</li></ul> |
| Framing and limits | <ul><li>PDU lengths checked from the header, before buffering</li><li>Maximum Length Received enforced on both sides</li><li>Bounded A-ASSOCIATE PDUs and command sets</li></ul> |
| State machine | <ul><li>States Sta1 to Sta13, events and actions of Table 9-10</li><li>All 494 cells tested</li><li>ARTIM (PS3.8 9.1.5), plus an idle timeout</li></ul> |
| Negotiation | <ul><li>Odd, unique presentation-context IDs; per-context results</li><li>SCP/SCU Role Selection (D.3.3.4)</li><li>Asynchronous Operations Window (D.3.3.3), never above the proposal</li><li>User Identity (D.3.3.7), accepted through a hook</li><li>Called and calling AE title policies, association limit (transient rejection)</li></ul> |
| Messages | <ul><li>Command and data fragmentation within the peer's maximum length, fragments of one message contiguous</li><li>Reassembly with ordering checks; data sets above a memory limit spilled to a temporary file</li></ul> |
| Release and abort | <ul><li>Release waits for operations in progress</li><li>Abort on protocol errors, timeouts, errors in the requestor's scope, and task cancellation</li></ul> |

### DIMSE-C services (PS3.7 9, PS3.4)

| Service | SCU | SCP |
| --- | --- | --- |
| Verification | <code>echo()</code> | Always served |
| Storage | <ul><li><code>store(_:)</code> from a file (streamed), a data set, or encoded bytes</li><li>Sent as encoded, or converted between uncompressed syntaxes</li></ul> | <ul><li><code>DICOMStorageService</code></li><li>Every storage SOP class of PS3.4 B.5, retired ones included</li><li>Every transfer syntax that encodes a data set, kept as received; the requestor's order of preference is followed</li></ul> |
| Query | <code>find(_:)</code>: an <code>AsyncSequence</code> of matches; stopping early sends C-CANCEL | <ul><li><code>DICOMQueryService</code>, Patient Root, Study Root, Patient/Study Only (retired)</li><li><code>DICOMQueryMatching</code>: PS3.4 C.2.2.2 matching</li></ul> |
| Retrieve | <ul><li><code>move(_:destination:)</code>, <code>get(_:)</code>, with progress</li><li>Task cancellation sends C-CANCEL</li></ul> | <ul><li><code>DICOMRetrieveService</code>, with Composite Instance Root</li><li>C-MOVE through a new association to the destination, C-GET on the same association</li><li>Sub-operation counts and Failed SOP Instance UID List</li></ul> |

### DIMSE-N services (PS3.7 10) and Storage Commitment (PS3.4 J)

| Service | SCU | SCP |
| --- | --- | --- |
| DIMSE-N | <ul><li><code>nGet</code>, <code>nSet</code>, <code>nAction</code>, <code>nCreate</code>, <code>nDelete</code></li><li><code>nEventReport</code> from the side that is SCP of the SOP class</li><li>Meta SOP Classes through the <code>abstractSyntax</code> parameter</li></ul> | <ul><li><code>DICOMNormalizedService</code> per SOP Class UID, on server and client associations</li><li>Errors become Processing Failure (0110H); unknown actions and events No Such Action/Event Type</li><li>N-EVENT-REPORT also accepted from a requestor that did not negotiate the SCP role</li></ul> |
| Storage Commitment Push Model | <ul><li><code>requestStorageCommitment</code> (N-ACTION, Action Type 1, well-known instance)</li><li><code>storageCommitmentResult</code> and <code>commit</code> wait for the result on the association</li><li><code>DICOMStorageCommitmentReceiver</code> for results on new associations</li></ul> | <ul><li><code>DICOMStorageCommitmentService</code></li><li>N-ACTION answered at once; result by N-EVENT-REPORT, Event Type 1 or 2 with Failure Reasons</li><li>Same association while open, else a new one under the same AE title proposing the SCP role (J.3.3.2)</li></ul> |

Statuses are modelled per service (`DICOMStatus` with categories), and a
service error answers with a failure status without ending the association.
`TransferSyntaxCapability.canNegotiateForDIMSE` is true for every transfer
syntax that encodes a data set.

### DICOMweb Studies Service (PS3.18 10)

DcmSwift is a user agent (`DICOMwebClient`) and a native origin server
(`DICOMwebOriginServer`, served over HTTP/1.1 or HTTPS by `DICOMwebServer`).

| Transaction | Origin server | User agent |
| --- | --- | --- |
| Search (QIDO-RS, 10.6) | <ul><li>All six search resources, hierarchical and relational</li><li><code>application/dicom+json</code> (default) and <code>multipart/related; type="application/dicom+xml"</code></li><li>Attribute matching through the C-FIND rules of PS3.4 C.2.2.2, UID lists, sequence attributes, <code>includefield</code></li><li><code>limit</code> and <code>offset</code>, at most 1000 matches per response by default, with the 299 Warning of further results</li><li>Fuzzy, empty-value, and multiple-value matching are not supported: the request is answered with the 299 Warnings of 8.3.4</li><li>Retrieve URL added to every match</li></ul> | <code>search(_:study:series:query:)</code> |
| Retrieve (WADO-RS, 10.4) | <ul><li>Study, series, and instance resources as <code>multipart/related; type="application/dicom"</code>, and <code>application/dicom</code> for one instance</li><li>Selected Transfer Syntax per part (8.7.8): as stored with <code>*</code> or its UID, otherwise Explicit VR Little Endian; lossless encapsulated syntaxes are decompressed, possibly lossy ones are returned as stored (8.7.3.4)</li><li>Metadata in JSON or XML, Pixel Data referenced by a Bulk Data URI to the Pixel Data resource</li><li>Frames and Pixel Data, uncompressed (<code>application/octet-stream</code>) or as the stored compressed frames (Table 8.7.3-5)</li><li>Rendered and thumbnail resources in <code>image/jpeg</code> and <code>image/png</code>, with the <code>window</code>, <code>viewport</code>, and <code>quality</code> parameters; Structured Reports in <code>text/html</code> and <code>text/plain</code></li></ul> | <code>instances</code>, <code>metadata</code>, <code>frames</code>, <code>rendered</code> |
| Store (STOW-RS, 10.5) | <ul><li><code>/studies</code> and <code>/studies/{study}</code> with <code>multipart/related; type="application/dicom"</code>, parts streamed to disk</li><li>The data set identifies each instance when its File Meta Information disagrees or lacks the Media Storage UIDs</li><li>Store Instances Response Module (Annex I) in JSON or XML; 200, 202, or 409</li><li>Implementation-specific Failure Reason C409H: Study Instance UID differs from the Target Resource</li></ul> | <code>store(files:study:)</code> streams files; <code>store(_:study:)</code> sends data sets |
| Retrieve Capabilities (8.9) | OPTIONS on the Base URI returns a WADL description of the supported resources (Annex H) | <code>capabilities()</code> |

| Common behavior | Support |
| --- | --- |
| Content negotiation (8.7) | <ul><li>Accept header and <code>accept</code> Query Parameter with qvalues, wildcards, and <code>transfer-syntax</code> parameters</li><li>406 without an Accept header or acceptable type; 400 when DICOM and rendered-only media types are mixed</li><li>Default Transfer Syntax per media type (Tables 8.7.3-2, 8.7.3-4, 8.7.3-5)</li></ul> |
| Errors (8.5, 8.6.3) | Status Reports in <code>text/html</code>; 404, 405 with Allow, 406, 413, 415, 501 |
| Transport | HTTP/1.1 with keep-alive; request payloads read as they are consumed; responses streamed with Content-Length or chunked coding; TLS with the configuration of the DIMSE profiles; a configurable public origin for Retrieve URLs behind a proxy |

Not supported yet: other PS3.18 services (Worklist/UPS-RS, Non-Patient
Instance, Storage Commitment, MWL, MPPS), metadata with Bulk Data in STOW-RS,
the generic Bulk Data resources, rendered GIF, MPR and 3D rendering,
annotations, ICC profiles, character set transcoding, HTTP Range, and access
control; see the limitations register.

### Tools

`DcmEcho`, `DcmStore`, `DcmFind`, and `DcmServer` use this stack; with
`--http-port`, `DcmServer` also serves its directory over DICOMweb. `DcmServer`
with a storage directory is a small archive: storage SCP, then C-FIND, C-MOVE,
C-GET, and Storage Commitment over the instances in that directory (README,
Network tools). It commits an instance whose file is present with the
referenced SOP class, and reports others as No Such SOP Instance (0112H) or
Class/Instance Conflict (0119H). `DcmStore --commit` waits for the result on
the association it stored on.

## Terminology (PS3.16)

`DICOMTerminology` holds the Content Mapping Resource of PS3.16 2026d,
generated from the DocBook by `Scripts/generate-dicom-terminology.py`.

| Content | Support |
| --- | --- |
| Coding Schemes (Table 8-1) | 66 schemes with their designator, UID, name, and organization |
| DICOM Controlled Terminology (Table D-1) | 5,164 DCM codes with their meaning and retirement |
| Context Groups (Annex B) | <ul><li>1,467 groups with keyword, extensibility, version, and UID</li><li>16,581 codes, with their Coding Scheme Version when PS3.16 gives one, and the included groups</li><li>Groups defined by a rule, such as all LOINC document names, keep their definition</li></ul> |
| Membership | A code belongs to a group when its scheme and value appear in the group or in a group it includes; extensible groups allow other codes; rule-based groups are undetermined |

PS3.16 2026d gives some codes several meanings within one group: synonyms
such as Buttock and Gluteal region, but also apparent errors, such as MDC
2:15880 for both Bazett and Framingham in CID 3227. Both rows are kept, and
the first is the group's meaning, as in NEMA's value sets.

## IOD validation (PS3.3)

`DICOMIODValidator` validates data sets against the IODs of PS3.3 2026d,
generated with the SOP Class to IOD mapping of PS3.4 by
`Scripts/generate-dicom-iods.py`. It is a layer separate from parsing.

| Content | Support |
| --- | --- |
| Specification | <ul><li>183 SOP Classes, mapped to 171 IODs</li><li>678 module and macro tables: 7,672 attributes, 849 lists of Enumerated Values, 1,339 inclusions</li><li>The Functional Group Macros of 32 enhanced multi-frame IODs</li></ul> |
| Checked | <ul><li>Mandatory modules always; user-optional and conditional modules when one of their own attributes is present, and conditional modules when their condition holds</li><li>Type 1 present and not empty, Type 2 present, Type 1C not empty when present</li><li>Types 1C and 2C present when their condition holds</li><li>Sequence Items, at every depth, with the macros they include</li><li>Enumerated Values of single-valued attributes, hexadecimal ones such as 0001H included</li><li>Functional Group Macros in the Shared or every Per-Frame Functional Groups Sequence Item</li><li>Inclusions conditioned on a value, such as the Content Item macros of each Value Type</li></ul> |
| Conditions evaluated | <ul><li>Those that test attributes: present or absent, empty or not, non-zero, equal or not to one of several Values, Value N included, greater than a number, joined by "and" or by "or"</li><li>An attribute is looked up in the Item being checked, then at the top level</li><li>1,121 of the 1,894 conditions of Types 1C and 2C, 98 of the 499 conditions of modules and Functional Group Macros, and 10 of the 13 conditional inclusions</li></ul> |
| Not checked yet | <ul><li>Conditions in prose, such as "Required if contrast media was used", or that test something other than an attribute's presence or Value: the attribute is then checked only when present</li><li>"Shall not be present otherwise"</li><li>Defined Terms, Context Groups, and attributes not allowed by the IOD</li></ul> |
| Receive policy | `DICOMIODValidationPolicy`: off, warn (B007H), or reject (A900H), for C-STORE and STOW-RS; instances of SOP Classes without an IOD are not judged |

On the pydicom test files and the local corpus, DcmValidate reports nothing
that dicom-validator 0.9.0 does not, but for one gap of that tool: 194 files,
1,354 findings in common. dicom-validator also reports 63 findings that
depend on conditions DcmValidate does not evaluate, mostly Patient Position
(0018,5100), Type 2C. It never reports a missing Pixel Data, Type 1C,
"Required if Pixel Data Provider URL (0028,7FE0) is not present", which
DcmValidate reports for the 50 pydicom DICOMDIR test files without one.

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

### Secure Transport Connection Profiles (PS3.15 B.12, B.13)

`DICOMTLSConfiguration.client` and `.server` apply the BCP 195 RFC 8996, 9325
TLS Secure Transport Connection Profile (B.12) with the algorithm restrictions
of the Modified profile (B.13). The retired B.9 to B.11 profiles are not
offered.

| Requirement | Behavior |
| --- | --- |
| Protocol versions | <ul><li>TLS 1.2 and TLS 1.3; clients offer 1.3 first and servers prefer it</li><li>SSL, TLS 1.0, and TLS 1.1 refused</li></ul> |
| TLS 1.2 cipher suites | <ul><li>TLS_ECDHE_ECDSA/RSA_WITH_AES_256_GCM_SHA384</li><li>TLS_ECDHE_ECDSA/RSA_WITH_CHACHA20_POLY1305_SHA256</li><li>TLS_ECDHE_ECDSA/RSA_WITH_AES_128_GCM_SHA256</li><li>No CBC, RC4, NULL, static RSA or DH key exchange, MD5, or SHA-1</li></ul> |
| TLS 1.3 cipher suites | TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256, TLS_AES_128_GCM_SHA256 |
| Authentication | <ul><li>Clients verify the server chain and host name (DNS or IP subject alternative name); relaxing either is explicit</li><li>Servers support mutual authentication with <code>pemClientTrustRootsFile</code>; the verified client certificate reaches services as <code>DICOMServiceContext.peerCertificate</code></li></ul> |
| Key management | PEM certificate chains, private keys, and trust roots from files, or any NIOSSL source through <code>DICOMTLSConfiguration(configuration:)</code>, which applies no profile |
| Ports | Configured per server and remote node; 2762 (dicom-tls) is recommended. A TLS server accepts only TLS |
| Provider reasons | A handshake or integrity failure drops the connection and ends the association with <code>DICOMNetworkError.tls</code>, carrying the TLS error; TLS data received on a plain connection is reported the same way |

C-MOVE destinations and Storage Commitment SCUs are reached with
`DICOMServerConfiguration.clientTLS` when their node uses TLS.

### De-identification (PS3.15 Annex E)

`DICOMDeidentifier` and `DcmAnonymize` de-identify with the Basic Application
Level Confidentiality Profile, from Tables E.1-1 and E.3.10-1 of PS3.15 2026d
read by `Scripts/generate-dicom-deidentification.py`.

| Requirement | Behavior |
| --- | --- |
| Attributes | <ul><li>The 657 rows of Table E.1-1, wherever the attributes appear, in Sequence Items too</li><li>Repeating groups: curves (50xx), overlay data and comments (60xx)</li><li>Group 0004 and group lengths removed</li></ul> |
| Actions | <ul><li>D: dummy value of the VR; Z: empty; X: removed; K: kept; U: UID replaced</li><li>X/Z, X/D, Z/D, X/Z/D, X/Z/U*: D for Type 1, Z for Type 2, X otherwise, from the Type in the IOD of the SOP Class (PS3.3)</li><li>A Sequence given a dummy keeps its Items, whose attributes are de-identified</li></ul> |
| UIDs | 2.25 UIDs from 128 bits of HMAC-SHA-256 of the original under a key: consistent for every instance de-identified with the same key, File Meta Information included |
| Private attributes | <ul><li>Removed</li><li>Retain Safe Private: the 479 attributes of Table E.3.10-1 kept, by Private Creator, with their Private Creator</li></ul> |
| Options | <ul><li>Retain Safe Private, UIDs, Device Identity, Institution Identity, Patient Characteristics, Longitudinal Full Dates, Longitudinal Modified Dates (dates shifted by a number of days)</li><li>Clean Descriptors, Structured Content, Graphics: through a cleaner the application provides; without it, the Basic Profile's action applies</li><li>When several selected options act on an attribute, K wins over C: PS3.15 does not order them</li></ul> |
| Records | Patient Identity Removed (0012,0062) YES; De-identification Method (0012,0063); De-identification Method Code Sequence (0012,0064) with the CID 7050 codes of the profile and options; Longitudinal Temporal Information Modified (0028,0303) |
| File Meta Information | Replaced with a description of DcmSwift, keeping the Transfer Syntax; the preamble is zeroed |
| Not claimed | <ul><li>Clean Pixel Data and Clean Recognizable Visual Features: Pixel Data is not inspected</li><li>The Encrypted Attributes Data Set</li></ul> |

The table matches the 2026c edition of Kitware's dicom-anonymizer except for
one attribute added in 2026d, (3004,007F). De-identified by both tools, the
pydicom test files and the local corpus (196 files, 3,908 attribute outcomes)
end the same, dicom-anonymizer resolving compound actions without the IOD.
De-identification adds no IOD finding on those files.

### Other security profiles

No audit trail (ATNA), digital signature, or encrypted-attribute conformance
is claimed. User Identity negotiation is
passed to an application hook (`DICOMServerConfiguration.authenticate`), which
decides on acceptance. Applications embedding DcmSwift remain responsible for
access control, persistence, and audit.

## Validation boundaries

Dictionary lookup and binary parsing do not establish IOD conformance, which
`DICOMIODValidator` checks separately and partially: conditions in prose,
PS3.16 Context Groups, and application profiles are not validated yet. A successfully parsed file
must therefore not be reported as clinically or semantically conformant solely
on that basis.

## Qualification policy

A capability moves from planned to supported only when it has normative test
vectors, malformed-input tests, round-trip tests where applicable, and an
interoperability result against an independent DICOM implementation. This
document and the executable capability registry must change together.
