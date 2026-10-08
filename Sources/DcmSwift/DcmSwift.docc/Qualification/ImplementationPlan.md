# DcmSwift 2.0 DICOM implementation plan

This plan targets DICOM 2026d. It separates registry knowledge from actual
implementation so that no UID, transfer syntax, SOP class, media profile, or
service is advertised merely because it exists in the standard.

Status legend: `[x]` done, `[ ]` to do (partial work is noted), and
~~struck through~~ for items moved out of scope.

## Capability levels

Every supported feature must state its level explicitly:

1. **Known**: present in the normative registry.
2. **Structurally readable/writable**: the encoded structure can be parsed or
   emitted without interpreting its complete meaning.
3. **Semantically interpreted**: values, multiplicity, character repertoire,
   and relevant constraints are understood.
4. **Payload codec support**: compressed pixel or waveform payloads can be
   decoded and/or encoded.
5. **Interoperable service support**: the feature is exercised against an
   independent implementation and documented in the Conformance Statement.

## Phase 0 — Measurable conformance baseline

Deliverables:

- [x] generate the tag and UID registry from PS3.6 2026d;
- [x] generate current command-set tags from PS3.7 Table E.1-1, retaining the
  retired legacy fields only as a documented fallback;
- [x] expose transfer-syntax capabilities independently of UID discovery;
- [x] publish a living Conformance Statement with explicit limitations;
- [x] add a traceability matrix linking capabilities to normative parts and tests;
- [x] define a corpus policy: synthetic edge cases, public DICOM samples, and
  round trips with independent toolkits.

The current implementation evidence and remaining gaps are tracked in the
[traceability matrix](Traceability.md). Intentionally deferred limitations stay
listed in the [limitations register](DeferredLimitations.md) until their evidence and
documentation release gates are complete.

Acceptance criteria:

- [x] an unknown or unimplemented transfer syntax is never silently treated as
  Explicit VR Little Endian;
- [x] public capability APIs never claim codec or DIMSE support without tests;
- [x] the generated registry is reproducible from the pinned standard edition
  (`Scripts/generate-dicom-dictionary.py`).

## Phase 1 — File and Data Set core (priority)

Implementation order for the remaining Phase 1 work:

1. [x] keep the capability matrix, Conformance Statement, and tests synchronized
   (ongoing with every change);
2. [x] complete binary and multi-valued VR handling plus VR/VM and per-VR
   lexical validation;
3. [x] introduce lazy Bulk Data access;
4. [x] implement Deflated Explicit VR Little Endian;
5. [ ] rebuild and qualify DICOMDIR and media-file handling (DICOMDIR rebuilt;
   PS3.12 media-profile qualification remains);
6. [x] implement the PS3.18 DICOM JSON model;
7. [x] implement the PS3.18 Native DICOM Model XML representation.

Progress so far:

- [x] capability/conformance documentation is synchronized through the Basic
  DICOMDIR milestone;
- [x] binary multi-valued VR/VM handling, lazy Bulk Data, and Deflated Explicit VR
  Little Endian are implemented with malformed-input regression tests;
- [x] native Pixel Data is decoded and rendered portably (grayscale pipeline,
  RGB, YBR, Palette Color, multi-frame, functional groups) and matches pydicom
  stored and Modality values on the interoperability corpus;
- [x] JPEG Baseline and Extended frames decode at 8/12 bits, including progressive
  and retired Huffman syntaxes, and encode unsigned monochrome or RGB input
  through the IJG integer FDCT, quantization, chroma-subsampling, restart, and
  optimized-Huffman pipeline verified against libjpeg-turbo;
- [x] retired non-hierarchical JPEG arithmetic syntaxes .52, .54, .56, and .58
  decode through the T.81 QM state machine, including sequential/progressive
  DCT and predictive lossless processes;
- [x] JPEG 2000 (.90, .91) and HTJ2K (.201 to .203) decode through the vendored
  OpenJPEG 2.5.4; JPEG 2000 encodes with OpenJPEG and HTJ2K with the vendored
  OpenJPH 0.32.0;
- [x] JPEG-LS Lossless and Near-Lossless (.80, .81) decode and encode in Swift,
  pass the T.87 conformance suite, and encode byte for byte like CharLS;
- [x] retired hierarchical JPEG syntaxes .59 to .66 decode per T.81 Annex J
  (DHP/EXP, differential DCT and lossless frames, bilinear expansion), within
  a stated tolerance of the ISO reference implementation;
- [x] every Specific Character Set Defined Term, including ISO 2022 Code
  Extensions, GB18030-2022, and GBK, reads and writes with platform-independent
  tables and PS3.5 Annex H-K vectors;
- [x] Basic DICOMDIR PATIENT/STUDY/SERIES/IMAGE read/write now computes offsets
  from the serialized layout and validates the record graph, File-set/File IDs,
  and referenced Part 10 identities;
- [x] a typed generic record-tree writer now shares the same offset and validation
  path, supports nested Sequences, and has round-trip coverage for RT DOSE and
  SR DOCUMENT records while preserving the legacy construction API; a synthetic
  all-types file additionally round-trips every current F.4-1 type with its
  unconditional top-level Type 1/2 keys, including the Content Identification
  Macro and top-level Scope of Inventory Sequence;
- [x] parsed offset graphs expose a lossless public record tree and fail closed
  rather than returning a partial tree for malformed or orphaned graphs;
- [x] unknown, retired, and misplaced record types are reported without blocking
  the load or hiding their lower-level records;
- [x] Basic and Enhanced Coded Entry macro rules are validated recursively in
  Directory Record code sequences;
- [x] SOP Instance Reference Macros in Referenced Image, Instance, and Waveform
  Sequences validate non-empty cardinality and both mandatory UIDs;
- [x] Scope of Inventory validates its outer cardinality, locally determinable
  extended-matching dependencies, and present matching Sequence cardinalities;
- [x] Icon Image Keys validate PS3.3 F.7 structure, restricted pixel attributes,
  native byte length, and palette attribute presence;
- [x] every current PS3.3 2026d Table F.4-1 Directory Record Type now has an
  extensible public identifier and a lossless generic record view; unconditional
  top-level Type 1 and Type 2 keys are represented for every current F.5 record
  type and its included macros, and common Type 1C rules cover PRIVATE record
  UIDs, referenced-SOP
  identity tuples, extended character sets used by record keys, verified SR
  documents, Hanging Protocol Definition Items, Related General SOP Class UID,
  and selected keys conditioned by the referenced SOP Instance;
- [ ] broader Directory Record coverage and PS3.12 media-profile qualification
  remain separate media work; JSON and XML are already implemented.

JSON and XML work deliberately follows the binary core so that alternate
representations are built on a stable, lossless Data Set model.

### 1.1 Binary safety and VR completeness

- [x] bounds-check every tag, length, item, fragment, and delimiter;
- [x] support every current VR header form and numeric signedness;
- [x] support scalar and multi-valued binary VRs, including AT, OL, OV, SV, UV;
- [x] preserve unknown and private elements losslessly;
- [x] reject impossible lengths and integer overflows deterministically.

### 1.2 Character repertoires

- [x] implement the default repertoire, ISO_IR 100, and ISO_IR 192 first;
- [x] make unsupported ISO 2022/code-extension declarations explicit failures,
  never implicit UTF-8 fallbacks;
- [x] propagate Specific Character Set into nested Data Sets;
- [x] cover Person Name component groups and multi-valued text with structured,
  typed read/write APIs while retaining the historical flat string API;
- [x] add ISO 2022 repertoires incrementally with conformance vectors (every
  PS3.3 2026d Defined Term, with PS3.5 Annex H-K and DCMTK vectors).

### 1.3 File Meta Information and transfer syntaxes

- [x] always encode group 0002 as Explicit VR Little Endian;
- [x] calculate File Meta Information Group Length at serialization time;
- [x] validate SOP Class/Instance consistency between meta information and Data Set;
- [x] enforce transfer-syntax read/write capabilities;
- [x] add Deflated Explicit VR Little Endian;
- [x] preserve encapsulated fragments and extended offset tables;
- [x] validate Extended Offset Table and its lengths against the fragments;
- add codecs behind optional capability providers (`DICOMCodecRegistry`)
  without coupling the core parser to them:
  - [x] RLE Lossless and Deflated Image Frame Compression;
  - [x] JPEG Baseline, Extended, Lossless, and every retired JPEG process,
    including hierarchical;
  - [x] JPEG-LS;
  - [x] JPEG 2000 and HTJ2K (vendored OpenJPEG and OpenJPH);
  - [x] JPEG XL decode (vendored libjxl, .110 to .112);
  - [x] JPEG XL encode (.110, .112) and JPEG recompression (.111) both ways;
  - [x] JPEG 2000 Part 2 multi-component transforms (.92, .93) decode, by
    component collection;
  - [x] JPEG 2000 Part 2 encode (grayscale, wavelet across frames);
  - ~~MPEG, AVC, and HEVC~~ (out of scope).

### 1.4 Sequences, bulk data, and private data

- [x] cover defined and undefined lengths for sequences and items;
- [x] validate delimiters and nesting depth and impose configurable resource limits;
- [x] expose bulk data lazily to avoid mandatory full-file loading;
- [x] implement private creator block resolution and retain unknown private values;
- [x] preserve original bytes when semantic decoding is unavailable, including
  unknown/private UN values, non-decodable text, and nested values;

### 1.5 DICOM JSON, Native DICOM Model XML, and media files

- [x] add the PS3.18 DICOM JSON Model, including Value, InlineBinary,
  BulkDataURI, PN objects, and nulls;
- [x] add the PS3.19 Native DICOM Model XML;
- [x] rebuild DICOMDIR around PS3.10/PS3.12 record offset rules;
- [x] validate File-set IDs and referenced file IDs;
- [ ] qualify supported PS3.12 media profiles.

The media-file work in this section precedes JSON and XML in the current
implementation order.

### 1.6 Validation and interoperability

- [x] validate VR, VM, retired status, UID syntax, dates/times, and required file
  meta attributes without confusing dictionary validity with IOD validity;
- ~~add IOD/module validation from PS3.3 as a separate layer~~ (moved to Phase 4);
- [x] test byte-exact round trips for native transfer syntaxes on the local and
  public pydicom corpora, with intentional normalization reported separately;
- [ ] compare reads and writes with at least DCMTK and pydicom/GDCM (reads are
  compared with pydicom through DICOM JSON; pixel data and character sets are
  checked against pydicom and DCMTK vectors);
- [x] fuzz the parser and retain every crash or corruption case as a regression.

Phase 1 is complete only when malformed input cannot crash the parser, supported
native transfer syntaxes round-trip without semantic loss, supported character
sets round-trip, and the Conformance Statement matches automated capability
tests.

## Phase 2 — DICOM Upper Layer and DIMSE (priority after the file core)

- [x] implement and test all A-ASSOCIATE negotiation items, role selection,
  asynchronous operations, extended negotiation, identity, rejection, release,
  and abort paths;
- [x] enforce odd presentation-context IDs, maximum PDU length, PDV fragmentation,
  command/data ordering, and timeouts;
- [x] implement C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET and C-CANCEL as SCU/SCP;
- [x] move the command-line tools to the new stack and remove the legacy one;
- [x] add Storage Commitment and the DIMSE-N services (generic SCU/SCP, service
  contracts per SOP class);
- [x] model status codes per service rather than as a single generic success flag;
- [ ] test fragmentation and association state transitions with independent peers;
- [x] add TLS with explicit certificate and hostname validation policies
  (PS3.15 B.12 with the B.13 algorithm restrictions).

## Phase 3 — Image rendering and presentation (after the network)

Goal: render every image as a conformant display application would, following
the PS3.4 Annex N pixel transformation sequence, and qualify the result against
an independent renderer (DCMTK `dcmp2pgm`, and IHE Consistent Presentation of
Images test material).

| Status | Area | Scope | Normative source |
| :-: | --- | --- | --- |
| ☐ | Grayscale pipeline completion | <ul><li>Pixel Padding Value and Range</li><li>Presentation LUT and P-Values</li><li>High bit depth output (10 to 16 bits)</li></ul> | PS3.3 C.7.5.1.1.2, C.11.4, C.11.6; PS3.4 N.2 |
| ☐ | Display calibration | Grayscale Standard Display Function mapping from P-Values | PS3.14 |
| ☐ | Overlays and shutters | <ul><li>Overlay Planes (60xx), including multi-frame overlays</li><li>Display Shutter and Bitmap Display Shutter</li></ul> | PS3.3 C.9.2, C.7.6.11, C.7.6.15 |
| ☐ | Presentation States | <ul><li>Grayscale Softcopy Presentation State: VOI, spatial transformation, displayed area, graphic and text annotations, compound graphics</li><li>Color, Pseudo-color, and Blending Presentation States</li><li>Variable Modality LUT Presentation State</li></ul> | PS3.3 C.11.10 to C.11.15; PS3.4 Annex N |
| ☐ | Color management | <ul><li>ICC profiles to PCS-Values</li><li>Supplemental and Enhanced Palette Color LUTs</li></ul> | PS3.3 C.11.15, C.7.6.19, C.7.6.23; PS3.4 N.2.1 |
| ☐ | Quantitative data | Real World Value Mapping | PS3.3 C.7.6.16.2.11 |
| ✓ | Rendered image export | Portable 8-bit PNG, quality-controlled JPEG, uncompressed TIFF, and lossless PGM/PPM for independent medical-imaging/tooling exchange, exposed by the single-file and batch `DcmConvert` demonstrator; high-bit-depth export follows grayscale pipeline completion, and rendered exports are not DICOM replacements | PS3.4 Annex N; TIFF 6.0; ISO/IEC 10918-1 |
| ☐ | Performance | Vectorized rendering and multi-frame (cine) streaming | — |

## Phase 4 — Web, security, and advanced objects

- [x] DICOMweb Studies Service: QIDO-RS, WADO-RS, STOW-RS, media types,
  multipart streaming, rendered retrieval, and standard error payloads, as
  user agent and origin server, checked against dicomweb-client and Orthanc;
  other PS3.18 services and the items of the limitations register remain;
- [x] JPIP Referenced Pixel Data (.94, .95, and HTJ2K .204, .205; PS3.5 A.6,
  A.7, A.11, A.12, 8.4.1): the Pixel Data Provider URL (0028,7FE0) is resolved
  with a JPIP client (ISO/IEC 15444-9) and the rebuilt codestreams are decoded
  with the JPEG 2000 codecs, checked against Kakadu's kdu_server;
- [ ] security and audit (TLS profiles done in Phase 2): ATNA audit events,
  digital signatures, encrypted attributes, and de-identification profiles;
- [ ] semantic APIs for Structured Reports, segmentations,
  radiotherapy, waveforms, encapsulated documents, and parametric maps;
- [x] declarative IOD/module validation from PS3.3, separate from dictionary and
  lexical validity: `DICOMIODValidator`, `DcmValidate`, and a receive policy,
  with the conditions that test attributes, checked against dicom-validator;
- [x] terminology/context-group handling from PS3.16 with version provenance:
  Coding Schemes, DCM codes, and Context Groups of 2026d, identical to NEMA's
  FHIR value sets; Templates follow with the Structured Report API.

## Release gates

Each minor release must include:

- capability and conformance-document updates in the same commit as behavior;
- normative references and automated tests for every new claim;
- no regression in malformed-input, round-trip, and interoperability suites;
- successful package build and platform-independent tests on both Apple and
  Linux toolchains;
- a migration note for any source or behavior change;
- a reproducible dependency and generated-registry update.

Closed GitHub PR #6 is intentionally excluded until it is explicitly brought
back into scope. Any branch or PR integration must pass these same gates and be
split from unrelated modernization work.
