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
- Add ISO 2022 code extensions and the remaining Specific Character Set
  repertoires with normative vectors. Unsupported declarations are currently
  rejected instead of silently decoded.
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
- Implement and qualify native Pixel Data interpretation across photometric
  interpretations, planar configurations, bit packing, multi-frame layouts,
  overlays, palettes, float/double pixels, and related functional groups.
- Add optional, independently qualified codecs for RLE, JPEG, JPEG-LS, JPEG
  2000, HTJ2K, MPEG, AVC and HEVC. Encapsulated fragments are currently
  preserved structurally; preservation is not a decode/encode claim.

## Deflated Explicit VR Little Endian

- Inflation and serialization currently operate on the complete Data Set in
  memory, subject to an inflation limit. Add bounded streaming inflate/deflate.
- Qualify files produced by, and consumed by, independent implementations.
- Deflated transfer syntax is not advertised for DIMSE negotiation; network
  negotiation and PDV streaming remain separate work.

## DICOMDIR, file-sets, and media profiles

- The qualified writer currently emits only the Basic Directory hierarchy
  PATIENT → STUDY → SERIES → IMAGE. Implement and test every applicable
  Directory Record type and its required/conditional keys from PS3.3.
- Preserve and expose unknown Directory Record types without losing their
  attributes or breaking hierarchy traversal.
- Implement File-set Descriptor File handling and validate its character set.
- Implement File-set update semantics, including consistency flag handling,
  inactive records, additions, deletions, and safe offset rewriting.
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

## Completion rule

The target is broad coverage of the standard, but claims remain capability
specific. This register is complete only when each applicable item is either
implemented and qualified or explicitly documented as out of product scope
with a reason. A passing parser test alone never closes an item.
