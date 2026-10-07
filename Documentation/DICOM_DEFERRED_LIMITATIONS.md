# DcmSwift 2.0 deferred limitations register

Baseline: DICOM 2026d
Goal: complete, evidence-backed coverage of the applicable DICOM standard

This register records intentionally deferred work. An item stays here until
its implementation, normative tests, malformed-input tests, interoperability
evidence, and Conformance Statement have all been completed. “Structurally
readable” must never be promoted to semantic, codec, profile, or service
conformance without that evidence.

## Binary file and Data Set model

- Complete per-VR lexical and semantic validation, including maximum lengths,
  padding, character repertoires, ranges, and the detailed rules for AE, AS,
  CS, DA, DS, DT, IS, LO, LT, PN, SH, ST, TM, UC, UI, UR and UT.
- Complete context-dependent VR resolution beyond the currently covered cases.
- Model Person Name component groups and representations rather than exposing
  PN only as a flat string.
- Specific Character Set: undecodable bytes make the whole value unavailable
  as text; the PS3.5 6.1.2.3 `\nnn` display substitution is not offered. Text
  encoders do not yet validate per-VR repertoires (for example CS and AE).
  GB18030 four-byte codes that the 2022 edition remapped decode one-way to the
  new two-byte characters, so their former private-use characters are not
  encodable. Exchange of DcmSwift-encoded ISO 2022 text with DCMTK or devices
  has not been qualified beyond decoding their sample files.
- Validate Extended Offset Table and Extended Offset Table Lengths and their
  relationship to encapsulated Pixel Data fragments.
- Add byte-preserving editing guarantees for values whose semantics are not
  understood, including explicit tests for unusual private and retired data.
- Add independent DCMTK, pydicom, and/or GDCM byte-exchange qualification and
  a retained fuzzing corpus. The existing internal corpus is not independent
  interoperability evidence.

## Bulk Data and Pixel Data

- Lazy loading is opt-in; eager loading remains the default for compatibility.
- File-backed lazy access currently covers defined-length binary VR Value
  Fields and individual encapsulated Pixel Data Items. It does not yet provide
  a general streaming Data Set API.
- Serializing deferred values may materialize them in memory; implement bounded
  streaming output and test source-file changes during a write.
- Native Pixel Data rendering does not yet apply Overlay Planes (60xx),
  Pixel Padding Value and Range, Presentation States, Supplemental or Enhanced
  Palette Color LUTs, ICC profiles, Real World Value Mapping, or alpha
  palettes. Rendered output is 8 bits per channel; a high bit depth display
  path is not offered. YBR_PARTIAL_420, YBR_ICT, and YBR_RCT are only defined
  for encapsulated data and wait for the codecs.
- Implement JPEG baseline/extended and JPEG-LS in Swift, and JPEG 2000,
  HTJ2K, and JPEG XL through vendored reference implementations. RLE Lossless,
  Deflated Image Frame Compression, and the JPEG Lossless decoder are
  implemented. MPEG, AVC, and HEVC are outside the planned scope.
- JPEG Lossless decoding rejects subsampled components, restart intervals that
  start inside a line, and DNL markers; it has no encoder yet. Point transforms
  and restart intervals have no independent test stream yet.
- There is no Data Set level transcoding API yet: frames are encoded with
  the codec types directly.

## Deflated Explicit VR Little Endian

- Inflation and serialization currently operate on the complete Data Set in
  memory, subject to an inflation limit. Add bounded streaming inflate/deflate.
- Qualify files produced by, and consumed by, independent implementations.
- Deflated transfer syntax is not advertised for DIMSE negotiation; network
  negotiation and PDV streaming remain separate work.

## DICOMDIR, file-sets, and media profiles

- The legacy convenience writer emits the Basic Directory hierarchy PATIENT →
  STUDY → SERIES → IMAGE. A typed generic record-tree writer can emit additional
  current types and nested Sequences through the same offset and validation
  path. All 35 current F.4-1 types round-trip synthetically with their
  unconditional top-level Type 1/2 keys, including keys introduced by the
  Content Identification Macro and the top-level Scope of Inventory Sequence.
  Complete the conditional and nested included-macro semantics for every
  applicable type. Current
  type names and F.4-1 parent/child relationships are validated, and all current
  F.5 tables have their unconditional top-level Type 1 and Type 2 keys
  represented. Common Type 1C rules cover PRIVATE record UIDs, referenced-SOP
  identity tuples, extended character sets in record keys, verified SR
  documents, and Hanging Protocol Definition Items. Conditional requirements
  directly mirrored by a referenced SOP Instance are checked during file-set
  integrity validation. Deeper IOD/module-dependent conditions, complete
  included macro validation beyond the current recursive Basic/Enhanced Coded
  Entry checks, SOP Instance Reference UID checks, Scope of Inventory
  structural/dependency checks, and unconditional top-level macro attributes
  remains unfinished. In particular,
  Scope of Inventory cannot infer whether range, UID-list, empty-value, general,
  or other matching was applied when the corresponding Sequence is absent.
  Complete semantic per-type qualification also remains unfinished.
- Icon Image validation covers F.7 structure and restricted pixel metadata,
  native Pixel Data length, and palette attribute presence. It does not yet
  validate palette LUT descriptor/data consistency, displayed colors, or
  exchange with independent File-set readers.
- Unknown and retired Directory Record types are preserved, traversed, and
  reported without blocking the load. Placement rules for retired types are
  not modeled from historical editions of Table F.4-1, and unknown types are
  not round-tripped by the typed generic writer, which only emits current
  F.4-1 types. Qualify the behavior against externally generated legacy media.
- Decode File-set Descriptor content according to its declared character set;
  the ID, declaration, containment, and existence are currently preserved and
  validated without interpreting the non-DICOM text file.
- Implement File-set update semantics for additions, replacements, deletions,
  and safe offset rewriting. Current PS3.3 requires FileSetConsistencyFlag to
  be 0000H and RecordInUseFlag to be FFFFH; their former inconsistent/inactive
  values are retired and intentionally rejected.
- Decide and document whether file-set integrity validation must be mandatory
  during writing. It is currently an explicit validation step so callers can
  construct the DICOMDIR before copying all referenced files into place.
- Qualify undefined-length and externally generated Directory Record Sequences,
  non-preorder physical record layouts, retired inactive records, empty
  directories, symlink escapes, malformed cycles, and orphan records with a
  retained external corpus.
- Implement and qualify the applicable PS3.12 media formats and PS3.11 media
  storage application profiles. Current Basic DICOMDIR support is not a
  PS3.12 or application-profile conformance claim.
- Exchange generated file-sets with independent tools and representative
  devices before claiming interoperability.

## Alternate representations

- Replace convenience JSON output with the PS3.18 DICOM JSON Model, including
  Value, PN objects, SQ items, JSON null, number/string rules, InlineBinary,
  BulkDataURI, empty values, ordering, and round trips.
- Implement the Native DICOM Model XML representation with the PS3.19
  namespace, attributes, PN, SQ, InlineBinary, BulkData, escaping, empty values,
  and round trips as used by PS3.18.
- Define lossless conversion boundaries between binary, JSON, and XML rather
  than assuming every representation preserves every original byte choice.

## Semantic conformance beyond encoding

- Build PS3.3 IOD/module validation as a separate layer with SOP Class and
  conditional-attribute logic. Dictionary VR/VM validation is not IOD
  validation.
- Add PS3.16 Context Group and terminology support with edition and version
  provenance.
- Qualify Structured Reports, waveforms, presentation states, segmentations,
  parametric maps, encapsulated documents, radiotherapy objects, and other
  information objects individually.

## Network, web, and security

- Complete PS3.8 association state, negotiation items, roles, asynchronous
  operations, identity, fragmentation/reassembly, maximum PDU enforcement,
  release, abort, timeouts, and independent-peer tests.
- Complete PS3.7 C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET, C-CANCEL and required
  DIMSE-N services as explicit SCU/SCP capabilities with service-specific
  status handling.
- Implement PS3.18 DICOMweb services and media types: QIDO-RS, WADO-RS,
  STOW-RS, UPS-RS where in scope, multipart streaming, rendered retrieval,
  bulk data, and standard error responses.
- Implement the selected PS3.15 security profiles: TLS policy, certificate and
  hostname validation, authentication hooks, ATNA audit, digital signatures,
  encrypted attributes, and de-identification profiles.

## Cross-platform implementation

- Image rendering and PNG export are portable. Encapsulated frames can only be
  displayed through the Apple system decoders until DcmSwift has codecs.
- GitLab CI currently qualifies the official Swift 6.1 Linux image, plus macOS
  and an iOS Simulator (newest installed runtime) on the `swift` macOS runner.
  Physical iOS devices, the minimum declared iOS 13 runtime, and other Apple
  platforms are not exercised. Additional
  Linux distributions, architectures, Swift releases, and libc variants are
  not yet part of the tested platform matrix.
- The package still uses Swift tools/language compatibility mode 5.9. Strict
  Swift 6 concurrency checking currently reports NIO pipeline `Sendable`
  diagnostics that would become errors in Swift 6 language mode; that migration
  remains a separate release gate.
- The large interoperability corpus is intentionally not versioned in git.
  GitLab CI downloads a pinned, checksummed archive from the private Generic
  Package Registry and fails, rather than skips, when it is unavailable. The
  corpus is internal to OPALE and remains no substitute for exchange with
  independent DICOM toolkits.

## Completion rule

The target is broad coverage of the standard, but claims remain capability
specific. This register is complete only when each applicable item is either
implemented and qualified or explicitly documented as out of product scope
with a reason. A passing parser test alone never closes an item.
