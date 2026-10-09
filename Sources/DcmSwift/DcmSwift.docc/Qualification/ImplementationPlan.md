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
- [x] build the archive services (storage, Query/Retrieve, Storage Commitment)
  on the pluggable archive storage of Phase 5 (`DICOMArchiveIndex`,
  `DICOMInstanceStore`), so that a database can replace the in-memory index;
- [ ] test fragmentation and association state transitions with independent peers;
- [x] add TLS with explicit certificate and hostname validation policies
  (PS3.15 B.12 with the B.13 algorithm restrictions).

## Order of the remaining work

Effort is relative, implementation and qualification together, measured
against Phase 4 work:

| Effort | Meaning | Phase 4 example |
| :-: | --- | --- |
| S | One area, few attributes, an existing generic layer to build on | Encapsulated documents |
| M | A model with its own rules or geometry, one oracle | Waveforms, Segmentations |
| L | Several cooperating parts or a demanding oracle, byte-level interoperability | Digital signatures |
| XL | A subsystem: state machines, many object types, or several standards at once | IOD validation |

Phases 0, 1, 2, and 4 are done except for the qualification items still open
in them. The remaining phases follow their dependencies, not their numbers:

| Order | Phase | Depends on | Why this place |
| :-: | --- | --- | --- |
| 1 | Phase 5 — Workflow services | Phase 2 (DIMSE-N), Phase 4 (DICOMweb) | Runs a department; the generic DIMSE-N layer only lacks the service rules |
| 2 | Phase 3 — Rendering and presentation | Phase 1 (codecs) | Every viewer needs it; Presentation States feed Phase 7 and 9 |
| 3 | Phase 6 — Object models and data | Phase 1, Phase 4 builder | Volumes are needed by Phase 8 and by the volume resources of Phase 9 |
| 4 | Phase 7 — Report templates | Phase 4 (SR, terminology) | Builds on the SR content tree; CDA and AIM need the templates |
| 5 | Phase 8 — Advanced imaging objects | Phase 3, Phase 6 | Whole slide imaging and annotations need tiles, volumes, and rendering |
| 6 | Phase 11 — Archive adapters | Phase 5 (pluggable archive storage) | A database-backed archive, such as a small PACS or a Vapor application, before the completeness phases |
| 7 | Phase 9 — Network and web completeness | Phases 3, 5, 6, 8 | Query/Retrieve of the objects of Phase 8, rendered volume resources |
| 8 | Phase 10 — Security, media, and legacy services | — | Completeness; no other phase depends on it |

## Phase 3 — Image rendering and presentation (after Phase 5)

Goal: render every image as a conformant display application would, following
the PS3.4 Annex N pixel transformation sequence, and qualify the result against
an independent renderer (DCMTK `dcmp2pgm`, and IHE Consistent Presentation of
Images test material).

| Status | Area | Effort | Scope | Normative source |
| :-: | --- | :-: | --- | --- |
| ☐ | Grayscale pipeline completion | M | <ul><li>Pixel Padding Value and Range</li><li>Presentation LUT and P-Values</li><li>High bit depth output (10 to 16 bits)</li></ul> | PS3.3 C.7.5.1.1.2, C.11.4, C.11.6; PS3.4 N.2 |
| ☐ | Display calibration | S | Grayscale Standard Display Function mapping from P-Values | PS3.14 |
| ☐ | Overlays and shutters | M | <ul><li>Overlay Planes (60xx), including multi-frame overlays</li><li>Display Shutter and Bitmap Display Shutter</li></ul> | PS3.3 C.9.2, C.7.6.11, C.7.6.15 |
| ☐ | Presentation States | XL | <ul><li>Grayscale Softcopy Presentation State: VOI, spatial transformation, displayed area, graphic and text annotations, compound graphics</li><li>Color, Pseudo-color, and Blending Presentation States</li><li>Variable Modality LUT Presentation State</li><li>Volumetric Presentation States (planar MPR first; after the volumes of Phase 6)</li></ul> | PS3.3 C.11.10 to C.11.15; PS3.4 N, FF |
| ☐ | Color management | L | <ul><li>ICC profiles to PCS-Values</li><li>Supplemental and Enhanced Palette Color LUTs</li></ul> | PS3.3 C.11.15, C.7.6.19, C.7.6.23; PS3.4 N.2.1 |
| ☐ | Quantitative data | S | Real World Value Mapping | PS3.3 C.7.6.16.2.11 |
| ✓ | Rendered image export | — | Portable 8-bit PNG, quality-controlled JPEG, uncompressed TIFF, and lossless PGM/PPM for independent medical-imaging/tooling exchange, exposed by the single-file and batch `DcmConvert` demonstrator; high-bit-depth export follows grayscale pipeline completion, and rendered exports are not DICOM replacements | PS3.4 Annex N; TIFF 6.0; ISO/IEC 10918-1 |
| ☐ | Performance | L | Vectorized rendering and multi-frame (cine) streaming | — |

## Phase 4 — Web, security, and advanced objects

- [x] DICOMweb Studies Service: QIDO-RS, WADO-RS, STOW-RS, media types,
  multipart streaming, rendered retrieval, and standard error payloads, as
  user agent and origin server, checked against dicomweb-client and Orthanc;
  other PS3.18 services and the items of the limitations register remain;
- [x] JPIP Referenced Pixel Data (.94, .95, and HTJ2K .204, .205; PS3.5 A.6,
  A.7, A.11, A.12, 8.4.1): the Pixel Data Provider URL (0028,7FE0) is resolved
  with a JPIP client (ISO/IEC 15444-9) and the rebuilt codestreams are decoded
  with the JPEG 2000 codecs, checked against Kakadu's kdu_server;
- [x] security and audit (TLS profiles done in Phase 2): de-identification
  done (Basic Profile and options, checked against dicom-anonymizer); audit
  trail done (messages of A.5.3 over syslog TLS and UDP, checked against the
  A.5.1 schema); digital signatures done (Base RSA profile, exchanged with
  DCMTK dcmsign); encrypted attributes done (CMS envelopes exchanged with
  openssl);
- [x] semantic APIs: encapsulated documents done (PDF, CDA, STL, OBJ, MTL,
  exchanged with DCMTK), waveforms read (checked against pydicom), and
  radiotherapy read (checked against dicompyler-core), Segmentations read and
  made and Parametric Maps read (checked against highdicom), and Structured
  Reports read and written with TID 1500 (checked against highdicom,
  dsrdump, and pydicom);
- [x] declarative IOD/module validation from PS3.3, separate from dictionary and
  lexical validity: `DICOMIODValidator`, `DcmValidate`, and a receive policy,
  with the conditions that test attributes, checked against dicom-validator;
- [x] terminology/context-group handling from PS3.16 with version provenance:
  Coding Schemes, DCM codes, and Context Groups of 2026d, identical to NEMA's
  FHIR value sets; Templates follow with the Structured Report API.

## Phase 5 — Workflow services (next)

Goal: the services that drive acquisition and reading, as SCU and SCP, with
their state rules, qualified against pynetdicom, DCMTK, and dcm4che. Every
service that keeps state is built on the pluggable archive storage: its data
live in a `DICOMArchiveIndex` collection, so that applications can put them in
the database of their choice through an adapter package.

Order decided on 2026-10-09: Modality Worklist and MPPS, then the archive
protocols (before UPS, so that UPS is written on them), then the small
services, then UPS, then its RESTful version.

| Status | Area | Effort | Scope | Normative source | Oracle |
| :-: | --- | :-: | --- | --- | --- |
| ✓ | Modality Worklist | M | <ul><li>C-FIND on the Modality Worklist Information Model, SCU and SCP</li><li>Matching keys and return keys of K.6</li><li>A worklist provider in `DcmServer` and a query tool</li><li>Items in the archive index (since the pluggable storage)</li></ul> | PS3.4 K | DCMTK `wlmscpfs`, `findscu` (`Scripts/crosscheck/worklist_dcmtk.py`) |
| ✓ | Modality Performed Procedure Step | M | <ul><li>N-CREATE and N-SET with the IN PROGRESS, COMPLETED, and DISCONTINUED rules</li><li>Attribute requirements per operation (F.7.2)</li><li>MPPS Notification and Retrieve</li></ul> | PS3.4 F | pynetdicom (`Scripts/interop/mpps.py`) |
| ✓ | Pluggable archive storage | L | <ul><li>Protocols in the core, without any database dependency: an archive index (instances, worklist items, procedure steps, UPS) and an instance store for the bytes (files, object storage)</li><li>The services (storage, Query/Retrieve, Storage Commitment, MWL, MPPS, UPS, DICOMweb) built on them; the in-memory implementation is the reference</li><li>A neutral query model built from the Identifier: adapters translate what they can, and the core filters the candidates with <code>DICOMQueryMatcher</code>, so partial translations stay exact</li><li>A shared conformance test kit that every adapter runs</li><li>Before UPS, so that UPS is written on it</li></ul> | PS3.4 C, K, F, CC; PS3.18 | Conformance kit: same results as the in-memory archive and DCMTK |
| ✓ | Instance Availability Notification | S | N-CREATE SCU and SCP, sent by `DcmServer` after storage | PS3.4 R | pynetdicom (`Scripts/interop/ian.py`) |
| ✓ | Application Event Logging | S | Procedure event logging N-ACTION SCU and SCP | PS3.4 P | pynetdicom (`Scripts/interop/event_logging.py`) |
| ✓ | Robustness of existing services | S | <ul><li>Storage Commitment results queued and retried</li><li>C-MOVE SCP splitting more than 128 presentation contexts</li></ul> | PS3.4 J, C | pynetdicom |
| ☐ | Unified Procedure Step | XL | <ul><li>Push, Pull, Watch, Event, and Query SOP Classes</li><li>State machine, locking Transaction UID, cancellation requests</li><li>Subscriptions, global and filtered, with N-EVENT-REPORT delivery</li><li>Steps and subscriptions kept in the archive index; Transaction UID locking through document versions</li></ul> | PS3.4 CC | pynetdicom; dcm4che `upsscu` |
| ☐ | RESTful workflow | L | <ul><li>UPS-RS (the Worklist Service) with WebSocket event notifications</li><li>MWL-RS and MPPS-RS where PS3.18 defines them</li><li>Storage Commitment over HTTP</li></ul> | PS3.18 11, 12 | dcm4chee-arc; dicomweb-client |
| ☐ | Query/Retrieve extensions | L | <ul><li>Extended negotiation interpreted: relational queries, combined date and time, fuzzy semantic matching, timezone adjustment, enhanced multi-frame conversion</li><li>Composite Instance Root Retrieve and Retrieve Without Bulk Data</li><li>Relevant Patient Information Query</li></ul> | PS3.4 C, Y, Z, Q; PS3.7 D.3.3.5, D.3.3.6 | pynetdicom; DCMTK |

## Phase 6 — Object models and data

| Status | Area | Effort | Scope | Normative source | Oracle |
| :-: | --- | :-: | --- | --- | --- |
| ☐ | Writing what is read | M | <ul><li>Waveforms (multiplex groups, channel definitions, all sample interpretations)</li><li>RT Dose (dose grid, scaling, frame offsets)</li><li>RT Structure Set (contours from polygons or masks)</li></ul> | PS3.3 C.10.9, C.8.8.3, C.8.8.5, C.8.8.6 | pydicom; dicompyler-core; dicom-validator |
| ☐ | Enhanced multi-frame volumes | L | <ul><li>Volume geometry from Functional Groups and Dimension Index</li><li>Enhanced CT, MR, PET, XA, US volumes; legacy-converted enhanced objects</li><li>Making Legacy Converted Enhanced images from a classic series</li></ul> | PS3.3 C.7.6.16, C.7.6.17, A.70 to A.72 | highdicom; DCMTK |
| ☐ | Spatial registration | M | Spatial Registration and Deformable Spatial Registration read and applied | PS3.3 C.20 | highdicom; ITK |
| ☐ | Surfaces | M | Surface Segmentation and Surface Scan meshes, point clouds | PS3.3 C.27, A.57, A.68 | highdicom or pydicom |
| ☐ | Transcoding | M | A Data Set level transcoding API between every transfer syntax with an encoder, keeping Pixel Data metadata consistent | PS3.5 8, 10 | DCMTK `dcmconv`, `dcmdjpeg` |

## Phase 7 — Report templates

| Status | Area | Effort | Scope | Normative source | Oracle |
| :-: | --- | :-: | --- | --- | --- |
| ☐ | Key Objects | S | Key Object Selection documents (TID 2010) read and made | PS3.16 TID 2010; PS3.3 A.35.4 | highdicom; DCMTK `dsrdump` |
| ☐ | Radiation dose | L | <ul><li>CT, projection X-ray, and radiopharmaceutical dose reports (TID 10011, 10001, 10021)</li><li>Patient Radiation Dose (TID 10030)</li></ul> | PS3.16 | PixelMed; DCMTK `dsrdump` |
| ☐ | Clinical reports | L | <ul><li>Basic Diagnostic Imaging Report (TID 2000)</li><li>CAD: mammography and chest (TID 4000, 4100)</li><li>Ultrasound: OB-GYN, vascular, echocardiography (TID 5000, 5100, 5200)</li></ul> | PS3.16 | DCMTK `dsrdump`; dicom3tools |
| ☐ | Template validation | XL | Template and Context Group constraints checked on SR content and coded attributes | PS3.16 Annex A, B | dicom3tools `dciodvfy` |
| ☐ | Other representations | L | <ul><li>SR to HL7 CDA imaging reports</li><li>The transformations of PS3.21 (AIM)</li></ul> | PS3.20; PS3.21 | Schematron and schemas of PS3.20 |

## Phase 8 — Advanced imaging objects

| Status | Area | Effort | Scope | Normative source | Oracle |
| :-: | --- | :-: | --- | --- | --- |
| ☐ | Whole slide imaging | L | <ul><li>TILED_FULL and TILED_SPARSE tiles, resolution pyramids, optical paths</li><li>Tile access by region and level; making pyramids</li></ul> | PS3.3 A.32.8, C.8.12.4 | wsidicom; highdicom |
| ☐ | Annotations | M | Microscopy Bulk Simple Annotations | PS3.3 A.87 | highdicom |
| ☐ | Display objects | M | <ul><li>Hanging Protocols</li><li>Color Palettes</li></ul> | PS3.3 A.38, A.58 | dicom-validator |
| ☐ | Ophthalmology | M | Ophthalmic Tomography, OCT-A, thickness maps, visual fields | PS3.3 A.39 to A.43, A.83 | dicom-validator; pydicom |
| ☐ | Other families | M | <ul><li>Tractography Results</li><li>Dermoscopy</li><li>Implant Templates</li><li>Defined and Performed Procedure Protocols</li><li>Inventory</li></ul> | PS3.3 | dicom-validator |

## Phase 9 — Network and web completeness

| Status | Area | Effort | Scope | Normative source | Oracle |
| :-: | --- | :-: | --- | --- | --- |
| ☐ | Query/Retrieve of non-patient objects | M | <ul><li>Hanging Protocol, Color Palette, Implant Template, Defined Procedure Protocol, Protocol Approval, and Inventory information models</li><li>Non-Patient Object Storage</li></ul> | PS3.4 U, X, BB, HH, II, JJ, GG | dcm4che |
| ☐ | Storage Management | M | Inventory creation and storage management operations | PS3.4 KK | dcm4che |
| ☐ | DICOMweb completeness | L | <ul><li>Non-Patient Instance service</li><li>Bulk Data resources and STOW-RS of metadata with Bulk Data</li><li>Rendered GIF, video, MPR and 3D volume resources</li><li>Charset negotiation, fuzzy and multiple-value matching, paging, HTTP Range</li></ul> | PS3.18 | dicomweb-client; Orthanc; dcm4chee-arc |
| ☐ | Independent peers | M | Fragmentation, state transitions, and live-association fuzzing against DCMTK and dcm4che (Phase 2 item) | PS3.8 | DCMTK; dcm4che |

## Phase 10 — Security, media, and legacy services

| Status | Area | Effort | Scope | Normative source | Oracle |
| :-: | --- | :-: | --- | --- | --- |
| ☐ | Security completeness | XL | <ul><li>Secure DICOM Files (Part 10 inside CMS)</li><li>User identity validation: JWT, SAML, Kerberos</li><li>Certificate revocation (CRL, OCSP) and trust checks for signatures</li><li>Creator and Authorization RSA signature profiles, certified timestamps</li><li>Audit message reception</li><li>Configuration profiles (LDAP, DHCP, DNS, NTP)</li></ul> | PS3.15; PS3.10 7.4 | openssl; DCMTK `dcmsign` |
| ☐ | Media | M | <ul><li>PS3.11 application profiles and PS3.12 media formats (Phase 1 item)</li><li>File-set updates: additions, replacements, deletions</li></ul> | PS3.11; PS3.12; PS3.3 F | DCMTK `dcmgpdir`, `dcmmkdir` |
| ☐ | Remaining services | L | <ul><li>Print Management (Basic Grayscale and Color Print)</li><li>Media Creation Management</li><li>Display System Management</li><li>Substance Administration and Product Characteristics queries</li><li>RT Machine Verification</li></ul> | PS3.4 H, S, EE, V, DD | DCMTK `dcmprscp`; pynetdicom |
| ☐ | Writing the remaining RT objects | L | RT Plan and Ion Plan | PS3.3 C.8.8 | dicompyler-core; pydicom |

## Phase 11 — Archive adapters (separate packages)

Database drivers never become dependencies of DcmSwift: each adapter is its
own package, which depends on DcmSwift and passes the conformance kit, so that
applications choose their stack (a Vapor application reuses its database).

| Status | Adapter | Effort | Scope | Oracle |
| :-: | --- | :-: | --- | --- |
| ☐ | SQLKit | L | <ul><li>PostgreSQL, MySQL, and SQLite through SQLKit, on the database a Vapor or Fluent application already has</li><li>Schema and migrations; the neutral query model translated to SQL</li></ul> | Conformance kit; dcm4chee-arc |
| ☐ | Standalone SQLite | M | For iOS and command-line use without SQLKit | Conformance kit |

## Out of scope

| Topic | Reason |
| --- | --- |
| MPEG-2, MPEG-4 AVC, HEVC transfer syntaxes | Video codecs carry patent licensing and need platform-specific decoders; the encapsulated stream stays readable and writable as is |
| PS3.22 real-time communication (SMPTE ST 2110) | A streaming transport, not a file or DIMSE feature; it needs dedicated media infrastructure |
| PS3.19 Application Hosting API | A SOAP hosting interface for plug-ins, rarely deployed; its Native DICOM Model is implemented |
| Retired service classes: Study Content Notification, Patient Management, Results Management, Queue Management, and the retired Print and Q/R SOP Classes | Retired from PS3.4; old files stay readable, but no current peer offers these services |
| Closed GitHub PR #6 | Excluded until explicitly brought back |

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
