# DcmSwift 2.0 DICOM implementation plan

This plan targets DICOM 2026d. It separates registry knowledge from actual
implementation so that no UID, transfer syntax, SOP class, media profile, or
service is advertised merely because it exists in the standard.

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

- generate the tag and UID registry from PS3.6 2026d;
- keep command-set tags from PS3.7 as a documented bootstrap until a PS3.7
  generator replaces them;
- expose transfer-syntax capabilities independently of UID discovery;
- publish a living Conformance Statement with explicit limitations;
- add a traceability matrix linking capabilities to normative parts and tests;
- define a corpus policy: synthetic edge cases, public DICOM samples, and
  round trips with independent toolkits.

The current implementation evidence and remaining gaps are tracked in
`Documentation/DICOM_TRACEABILITY.md`. Intentionally deferred limitations stay
listed in `Documentation/DICOM_DEFERRED_LIMITATIONS.md` until their evidence and
documentation release gates are complete.

Acceptance criteria:

- an unknown or unimplemented transfer syntax is never silently treated as
  Explicit VR Little Endian;
- public capability APIs never claim codec or DIMSE support without tests;
- the generated registry is reproducible from the pinned standard edition.

## Phase 1 — File and Data Set core (priority)

Implementation order for the remaining Phase 1 work:

1. keep the capability matrix, Conformance Statement, and tests synchronized;
2. complete binary and multi-valued VR handling plus VR/VM validation;
3. introduce lazy Bulk Data access;
4. implement Deflated Explicit VR Little Endian;
5. rebuild and qualify DICOMDIR and media-file handling;
6. implement the PS3.18 DICOM JSON model;
7. implement the PS3.18 Native DICOM Model XML representation.

Current progress in that order:

- capability/conformance documentation is synchronized through the Basic
  DICOMDIR milestone;
- binary multi-valued VR/VM handling, lazy Bulk Data, and Deflated Explicit VR
  Little Endian are implemented with malformed-input regression tests;
- native Pixel Data is decoded and rendered portably (grayscale pipeline,
  RGB, YBR, Palette Color, multi-frame, functional groups) and matches pydicom
  stored and Modality values on the interoperability corpus;
- JPEG Baseline and Extended frames decode at 8/12 bits, including progressive
  and retired Huffman syntaxes, and encode unsigned monochrome or RGB input
  through the IJG integer FDCT, quantization, chroma-subsampling, restart, and
  optimized-Huffman pipeline verified against libjpeg-turbo;
- every Specific Character Set Defined Term, including ISO 2022 Code
  Extensions, GB18030-2022, and GBK, reads and writes with platform-independent
  tables and PS3.5 Annex H-K vectors;
- Basic DICOMDIR PATIENT/STUDY/SERIES/IMAGE read/write now computes offsets
  from the serialized layout and validates the record graph, File-set/File IDs,
  and referenced Part 10 identities;
- a typed generic record-tree writer now shares the same offset and validation
  path, supports nested Sequences, and has round-trip coverage for RT DOSE and
  SR DOCUMENT records while preserving the legacy construction API; a synthetic
  all-types file additionally round-trips every current F.4-1 type with its
  unconditional top-level Type 1/2 keys, including the Content Identification
  Macro and top-level Scope of Inventory Sequence;
- parsed offset graphs expose a lossless public record tree and fail closed
  rather than returning a partial tree for malformed or orphaned graphs;
- unknown, retired, and misplaced record types are reported without blocking
  the load or hiding their lower-level records;
- Basic and Enhanced Coded Entry macro rules are validated recursively in
  Directory Record code sequences;
- SOP Instance Reference Macros in Referenced Image, Instance, and Waveform
  Sequences validate non-empty cardinality and both mandatory UIDs;
- Scope of Inventory validates its outer cardinality, locally determinable
  extended-matching dependencies, and present matching Sequence cardinalities;
- Icon Image Keys validate PS3.3 F.7 structure, restricted pixel attributes,
  native byte length, and palette attribute presence;
- every current PS3.3 2026d Table F.4-1 Directory Record Type now has an
  extensible public identifier and a lossless generic record view; unconditional
  top-level Type 1 and Type 2 keys are represented for every current F.5 record
  type and its included macros, and common Type 1C rules cover PRIVATE record
  UIDs, referenced-SOP
  identity tuples, extended character sets used by record keys, verified SR
  documents, Hanging Protocol Definition Items, Related General SOP Class UID,
  and selected keys conditioned by the referenced SOP Instance;
- broader Directory Record coverage and PS3.12 media-profile qualification are
  still required before starting the planned JSON and XML work.

JSON and XML work deliberately follows the binary core so that alternate
representations are built on a stable, lossless Data Set model.

### 1.1 Binary safety and VR completeness

- bounds-check every tag, length, item, fragment, and delimiter;
- support every current VR header form and numeric signedness;
- support scalar and multi-valued binary VRs, including AT, OL, OV, SV, UV;
- preserve unknown and private elements losslessly;
- reject impossible lengths and integer overflows deterministically.

### 1.2 Character repertoires

- implement the default repertoire, ISO_IR 100, and ISO_IR 192 first;
- make unsupported ISO 2022/code-extension declarations explicit failures,
  never implicit UTF-8 fallbacks;
- propagate Specific Character Set into nested Data Sets;
- cover Person Name component groups and multi-valued text;
- add ISO 2022 repertoires incrementally with conformance vectors (done for
  every PS3.3 2026d Defined Term, with PS3.5 Annex H-K and DCMTK vectors).

### 1.3 File Meta Information and transfer syntaxes

- always encode group 0002 as Explicit VR Little Endian;
- calculate File Meta Information Group Length at serialization time;
- validate SOP Class/Instance consistency between meta information and Data Set;
- enforce transfer-syntax read/write capabilities;
- add Deflated Explicit VR Little Endian;
- preserve encapsulated fragments and extended offset tables;
- add codecs behind optional capability providers (RLE, JPEG, JPEG-LS,
  JPEG 2000, HTJ2K, MPEG and HEVC) without coupling the core parser to them.

### 1.4 Sequences, bulk data, and private data

- cover defined and undefined lengths for sequences and items;
- validate delimiters and nesting depth and impose configurable resource limits;
- expose bulk data lazily to avoid mandatory full-file loading;
- implement private creator block resolution and retain unknown private values;
- preserve original bytes when semantic decoding is unavailable.

### 1.5 DICOM JSON, Native DICOM Model XML, and media files

- replace the current convenience JSON/XML output with PS3.18-conformant
  models, including Value, InlineBinary, BulkDataURI, PN objects, and nulls;
- rebuild DICOMDIR around PS3.10/PS3.12 record offset rules;
- validate File-set IDs, referenced file IDs, and supported media profiles.

The media-file work in this section precedes JSON and XML in the current
implementation order.

### 1.6 Validation and interoperability

- validate VR, VM, retired status, UID syntax, dates/times, and required file
  meta attributes without confusing dictionary validity with IOD validity;
- add IOD/module validation from PS3.3 as a separate layer;
- test byte-exact round trips for all native transfer syntaxes;
- compare reads and writes with at least DCMTK and pydicom/GDCM;
- fuzz the parser and retain every crash or corruption case as a regression.

Phase 1 is complete only when malformed input cannot crash the parser, supported
native transfer syntaxes round-trip without semantic loss, supported character
sets round-trip, and the Conformance Statement matches automated capability
tests.

## Phase 2 — DICOM Upper Layer and DIMSE (priority after the file core)

- implement and test all A-ASSOCIATE negotiation items, role selection,
  asynchronous operations, extended negotiation, identity, rejection, release,
  and abort paths;
- enforce odd presentation-context IDs, maximum PDU length, PDV fragmentation,
  command/data ordering, and timeouts;
- implement C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET and C-CANCEL as SCU/SCP;
- add Storage Commitment and selected DIMSE-N services only after their service
  contracts and persistence semantics are defined;
- model status codes per service rather than as a single generic success flag;
- test fragmentation and association state transitions with independent peers;
- add TLS with explicit certificate and hostname validation policies.

## Phase 3 — Web, security, and advanced objects

- DICOMweb: QIDO-RS, WADO-RS, STOW-RS, media types, multipart streaming,
  rendered retrieval, and standard error payloads;
- security and audit: TLS profiles, authentication hooks, ATNA audit events,
  digital signatures, encrypted attributes, and de-identification profiles;
- semantic APIs for Structured Reports, presentation states, segmentations,
  radiotherapy, waveforms, encapsulated documents, and parametric maps;
- terminology/context-group handling from PS3.16 with version provenance.

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
