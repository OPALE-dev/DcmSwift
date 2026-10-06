# DcmSwift DICOM Conformance Statement (working draft)

Edition: DICOM 2026d  
Implementation: DcmSwift 2.0 development branch  
Status: incomplete implementation statement; not a claim of full DICOM
conformance

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
| Encapsulated Pixel Data | Fragment structure preservation only; no codec claim |
| Native uncompressed Pixel Data | Byte access; full image interpretation is not yet claimed |
| Unknown/private elements | Unknown implicit values preserved as UN; private creator blocks resolved within each Data Set scope |
| Defined/undefined-length sequences | Read and write; Item tags, boundaries, delimiters, nesting depth, and resource limits validated |
| Specific Character Set | Default repertoire, ISO_IR 100, and ISO_IR 192, including nested inheritance and local override |
| Fixed-width numeric VR values | Scalar and multi-valued signed/unsigned integer and floating-point read/write with dictionary VM validation |
| Lazy Bulk Data | Opt-in file-backed references and bounded reads for defined-length binary VRs and encapsulated Pixel Data Items |
| DICOM JSON / Native DICOM Model XML | Existing convenience output is not PS3.18 conformant |
| DICOMDIR and media profiles | Existing implementation is not yet claimed conformant |

Known UIDs are not automatically supported. `TransferSyntaxCapability` is the
authoritative programmatic statement for structural I/O, Pixel Data
preservation, codec operations, and DIMSE negotiation.

The next file-core priorities are remaining semantic VR validation and
DICOMDIR. Deflated DIMSE negotiation remains separate network work.
PS3.18 JSON and XML representations follow those binary-format milestones.

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

Text decoding must follow Specific Character Set (0008,0005). Unsupported
repertoires and ISO 2022 code-extension combinations must remain observable as
unsupported; they must not be silently decoded as UTF-8. Character-set support
is qualified independently for reading and writing. Nested Data Sets inherit
the enclosing repertoire and may override it locally without affecting sibling
Items. ISO 2022 code extensions remain unsupported.

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
