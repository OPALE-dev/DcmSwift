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
- Person Name component groups and multi-valued character strings now have
  typed read/write APIs. The historical flat `value` and `string(forTag:)`
  accessors remain for source compatibility. Full per-VR length, repertoire,
  and lexical validation remains deferred.
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
- Reads are compared with pydicom through the DICOM JSON Model
  (`Scripts/crosscheck/pydicom_json.py`); DCMTK and GDCM comparisons, and
  comparisons of written files, remain to do.
- Fuzzing is in-process mutation fuzzing (`DcmSwiftFuzzTests`), not
  coverage-guided: libFuzzer is not available in the Apple toolchain.

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
  path is not offered. These are planned in Phase 3 of the implementation
  plan. YBR_ICT and YBR_RCT frames are returned as RGB by the JPEG 2000
  codec; YBR_PARTIAL_420 is only used by video syntaxes, which are out of
  scope.
- JPEG XL decodes and encodes through the vendored libjxl 0.12.0. A reliable,
  high-performance Swift implementation remains future work. Reliable,
  high-performance Swift implementations of JPEG 2000 and HTJ2K are also a
  later goal. RLE
  Lossless, Deflated Image Frame Compression, JPEG Lossless, JPEG
  Baseline/Extended, and JPEG-LS are implemented in Swift; JPEG 2000 and HTJ2K
  use the vendored OpenJPEG 2.5.4 (decoding, JPEG 2000 encoding) and OpenJPH
  0.32.0 (HTJ2K encoding). JPEG XL uses libjxl 0.12.0, with Brotli and skcms. OpenJPH is
  built without its SIMD variants, which
  need per-file compiler flags that SwiftPM does not allow. MPEG, AVC,
  and HEVC are outside the planned scope.
- JPEG XL limits:
  - the encoder takes unsigned 8 or 16-bit cells only (no signed, 24-bit, or
    YBR input) and labels lossy color frames RGB rather than XYB;
  - JPEG recompression keeps 8-bit Huffman JPEG with 4:4:4, 4:2:2, 4:2:0, or
    4:4:0 chroma; libjxl renders its pixels with its own IDCT and chroma
    upsampling, up to 16 levels from libjpeg-turbo at chroma edges;
  - signed or floating-point samples, alpha or other extra channels, animation,
    and non-identity orientation are rejected;
  - the tracked fixtures cover lossless 8/12-bit, RGB, lossy, raw/container,
    and reversible JPEG recompression streams, but no external DICOM JPEG XL
    corpus is currently qualified.
- JPEG 2000 limits:
  - JPIP Referenced (.94, .95, .204, .205): frames are retrieved at full
    resolution and quality only; codestreams with packed packet headers
    (PPM, PPT) are refused; JPIP over UDP is not supported (PS3.5 excludes
    it); no DICOM JPIP provider was available, so Kakadu's kdu_server, which
    numbers JPX code streams from 0, is the reference; the rendering and
    WADO-RS paths need `DICOMJPIPClient.resolve(_:)` first;
  - OpenJPEG 2.5.4 cannot decode codestreams whose components or tiles have
    different decomposition levels together with a multiple component
    transform ("Tiles don't all have the same dimension"), nor some
    subsampled ones; Kakadu decodes them;
  - the Part 2 encoder handles grayscale frames only and writes one wavelet
    collection per codestream (no array-based transforms); its PSNR target
    applies to the codestream components and is approximate;
  - OpenJPEG 2.5.4 cannot decode Part 2 multiple component transformations,
    so it decodes a rewritten codestream (Part 2 markers turned into COM,
    codestream components declared signed and wider) and the Annex J inverse
    runs in Swift; irreversible codestream components keep 8 fractional bits
    but are still clamped to their nominal SIZ range;
  - the samples of a Part 2 frame are taken from consecutive components (one
    per frame for grayscale), an ordering PS3.5 does not spell out for color;
  - multi-frame Part 2 images ignore offset tables: collections are found
    from codestreams starting Fragments, and frames cannot be read encoded;
  - Part 2 qualification uses the Kakadu 8.4.1 demonstration decoder, which
    is not redistributable and not run in CI; its `kdu_compress` crashes on
    dependency transforms and its decoder does not read MCC series split
    over several segments, so those fixtures carry hand-built segments and
    one is checked against its source; no
    external DICOM .92/.93 corpus is known;
  - subsampled components are rejected;
  - the pydicom JPEG 2000 and HTJ2K files (20 decodable files, including
    signed, 10 to 16-bit, YBR_RCT/YBR_ICT, and multi-frame images) were
    checked manually against pylibjpeg-openjpeg and the uncompressed
    originals, not in CI.
- JPEG-LS limits:
  - mapping tables (palettized JPEG-LS, LSE types 2 and 3) and oversize
    dimensions (LSE type 4) are rejected;
  - DICOM decoding rejects subsampled components, which the decoder itself
    supports for line interleaving;
  - the encoder uses default coding parameters and equal sampling;
  - the HP color transforms are decoded as CharLS does (lossless, 8 or 16-bit,
    interleaved); DICOM does not allow them, but old files may carry them;
  - decoding takes about 1.7 times as long as CharLS in release builds; SIMD
    and table-driven Golomb decoding remain.
- Retired JPEG Transfer Syntaxes must stay readable. The progressive Huffman
  syntaxes (.53, .55), the non-hierarchical arithmetic syntaxes
  (.52, .54, .56, .58), and the hierarchical syntaxes (.59 to .66) decode.
- Hierarchical JPEG is qualified against the ISO reference (Thomas Richter's
  libjpeg) within a stated tolerance, not bit-exactly: the reference computes
  in fixed point with extra fraction bits, so its IDCT, color conversion, and
  two-dimensional upsampling differ by a few levels from the IJG algorithms
  and from the two successive truncations of T.81 J.1.1.2, which DcmSwift
  follows. A DCT first frame followed by a lossless differential frame is
  lossless only with the encoder's own IDCT, which T.81 does not specify
  (A.3.3); such streams decode within one level of the original. Lossless
  hierarchical frames with subsampled components are rejected.
- JPEG Baseline/Extended encoding currently accepts unsigned MONOCHROME1/2 and
  RGB frames only. Encoding and decoding remain below SIMD-library throughput;
  streaming coefficient storage, entropy acceleration, and SIMD work remain.
  Decoded YCbCr frames are always converted to RGB.
- JPEG Lossless decoding rejects subsampled components, restart intervals that
  start inside a line, and DNL markers. Encoded streams were verified with
  libjpeg-turbo 3.2.0, including restart intervals and point transforms.
  pylibjpeg-libjpeg decodes point-transformed streams differently from T.81
  H.1.2.1 (it predicts the first sample from 2^(P-1) instead of 2^(P-Pt-1)), so
  point transforms may not interoperate with readers built on it.
- JPEG arithmetic decoding is implemented in Swift from T.81 Annex D/F/G/H.
  SOF9/SOF10 have fixed and live libjpeg-turbo oracles; SOF11 is checked
  against streams from the ISO reference encoder, since libjpeg-turbo omits
  that combination. As T.81 B.2.3 requires, components that share a DC table
  share its statistics area.
- There is no Data Set level transcoding API yet: frames are encoded with
  the codec types directly.

## Deflated Explicit VR Little Endian

- Inflation and serialization currently operate on the complete Data Set in
  memory, subject to an inflation limit. Add bounded streaming inflate/deflate.
- Qualify files produced by, and consumed by, independent implementations.
- On the network, deflated data sets are inflated and deflated in memory;
  streaming PDVs through Deflate remains to do.

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

- DICOM JSON: private elements keep VR UN unless sent with a VR (no vendor
  dictionaries); the legacy `toJSON()` convenience output remains, distinct from
  `DICOMJSON`.
- Native DICOM Model: trailing empty Person Name components cannot be written
  (XML has one element per non-empty component), BulkData `uuid` references
  are kept as URIs, and the legacy `toXML()` output remains alongside
  `DICOMXML`.
- Define lossless conversion boundaries between binary, JSON, and XML rather
  than assuming every representation preserves every original byte choice.

## Semantic conformance beyond encoding

- IOD validation (PS3.3) evaluates only the conditions that test attributes
  (about three in five), does not apply Defined Terms and Context Groups, and
  does not report attributes the IOD does not allow.
- PS3.16: the Templates (TID) of Annex A are not modelled yet; they come
  with the Structured Report API. Context Groups are not yet applied to the
  attributes and Content Items that reference them, which belongs to IOD
  validation.
- Qualify Structured Reports, waveforms, presentation states, segmentations,
  parametric maps, encapsulated documents, radiotherapy objects, and other
  information objects individually.

## Network, web, and security

- Network qualification so far is pynetdicom 3.0.4 in both directions and the
  loopback tests; DCMTK and dcm4che peers, and fuzzing of live associations,
  remain to do.
- Extended Negotiation (D.3.3.5) and SOP Class Common Extended Negotiation
  (D.3.3.6) items are carried but no service interprets them.
- C-MOVE and the tools propose at most 128 presentation contexts per
  association: `DcmStore` splits its files into several associations, the
  C-MOVE SCP does not yet.
- The `DcmServer` archive keeps its index in memory and matches the
  attributes of PS3.4 C.6 key tables only; it is a tool, not a PACS.
- DIMSE-N is generic: no SOP-class-specific behavior (MPPS state rules,
  Print Management, UPS) is built in yet. Storage Commitment's optional
  Storage Media File-Set attributes are carried but not interpreted, and
  duplicate Transaction UIDs are left to the service.
- A Storage Commitment result that cannot be delivered (no destination, or
  the SCU unreachable) is logged, not queued for a later retry.
- DICOMweb (PS3.18): the Studies Service is implemented. Still missing:
  - the Worklist (UPS-RS), Non-Patient Instance, Storage Commitment, MWL, and
    MPPS services, and WebSocket notifications;
  - STOW-RS of metadata with separate Bulk Data, and of compressed images
    supplied as image/jpeg or other Bulk Data media types (10.5.2);
  - the study, series, and instance Bulk Data resources: metadata references
    only Pixel Data, through the Pixel Data resource, and keeps other binary
    values inline;
  - rendered image/gif (required for REST origin servers), video, and the
    MPR and 3D volume resources; burned-in annotations and ICC profiles are
    answered with 299 Warnings;
  - character set transcoding (Accept-Charset, the charset parameter), fuzzy,
    empty-value, and multiple-value matching, Prior Record Key paging, HTTP
    Range, HTTP/2, and authentication or access control;
  - the search matches only the attributes the archive indexes; others are
    returned empty.
- TLS: BoringSSL has no CCM suites, so a server does not offer every suite B.13
  lists (TLS_ECDHE_ECDSA_WITH_AES_*_CCM*, TLS_AES_128_CCM*_SHA256), nor the
  optional Camellia and DHE ones. Certificate key sizes and signature hashes
  are not checked beyond BoringSSL's own rules, and revocation (CRL, OCSP) is
  not checked.
- Security profiles still to implement: ATNA audit, digital signatures, and
  encrypted attributes, including the Encrypted Attributes Data Set of
  de-identification.
- De-identification does not inspect Pixel Data (burned-in annotations) nor
  clean free text by itself: the Clean options need a cleaner from the
  application.

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
