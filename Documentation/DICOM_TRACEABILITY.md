# DcmSwift 2.0 DICOM traceability matrix

Baseline: DICOM 2026d  
Scope: implemented behavior on the `codex/dcmswift-2.0` branch

This matrix distinguishes registry knowledge, structural support, semantic
interpretation, codec support, and independently tested interoperability. A
passing structural test is not evidence of IOD, media-profile, or clinical
conformance.

| Capability | Normative source | Claimed level | Automated evidence | Remaining qualification |
| --- | --- | --- | --- | --- |
| Public tag and UID registry | PS3.6 | Known | `testRuntimeDictionaryComesFromDICOM2026d` | Generate command-set registry from PS3.7 |
| Transfer Syntax capability separation | PS3.5 Annex A, PS3.6 UID registry | Known vs implemented capability | `testKnownTransferSyntaxIsNotAutomaticallyImplemented`, `testUnimplementedTransferSyntaxIsRejected` | Independent toolkit matrix |
| Implicit VR Little Endian | PS3.5 7 and Annex A | Structural read/write | round-trip corpus plus `testDIMSECommandSetUsesLittleEndianValues` | Byte-exact external corpus comparison |
| Explicit VR Little Endian | PS3.5 7 and Annex A | Structural read/write | round-trip corpus and core safety tests | Byte-exact external corpus comparison |
| Explicit VR Big Endian | PS3.5 Annex A, retired | Structural read/write | `testBigEndianTransferSyntaxExposesBigEndianEncoding`, `testPart10BigEndianDatasetStartsAfterCompleteFileMetaInformation` | Independent toolkit comparison |
| Deflated Explicit VR Little Endian | PS3.5 A.5 | Part 10 structural read/write; no DIMSE claim | `testDeflatedExplicitVRLittleEndianPart10RoundTrip`, `testReadsIndependentPythonRawDeflateFixture`, `testDeflatedDataSetHonorsInflatedSizeLimit`, `testRawDeflateRejectsTruncationAndUnexpectedTrailingBytes` | Streaming inflation/output and independent toolkit file exchange |
| Modern and binary VR headers | PS3.5 6.2 and 7.1 | Structural and multi-valued semantic support | `testAttributeTagValueUsesTargetByteOrder`, `testModernTextVRUsesLongExplicitHeaderAndURIStaysASCII`, `testFloatingPointAndModernBinaryVRSetters`, `testMultiValuedBinaryVRsRoundTripWithTypedAccessors`, `testExplicitVRRejectsUnknownCodeAndNonZeroReservedBytes` | Complete per-VR semantic validation |
| Signed and unsigned numeric values | PS3.5 6.2 | Scalar and multi-valued semantic support | `testUnsignedVRValuesPreserveFullRange`, `testSignedIntegerSettersPreserveSign`, `testDataElementTranscodesNumericValueByteOrder`, `testDictionaryVMValidationHandlesRangesAndMultiples` | Expand malformed-length and overflow matrix |
| Part 10 File Meta Information | PS3.10 7.1 | Structural read/write plus identity checks | `testFileMetaInformationIsExplicitLittleEndianAndRecalculated`, `testFileMetaValidationReportsMissingAndMismatchedIdentifiers` | Application-profile validation |
| Defined/undefined-length Sequences and Items | PS3.5 7.5 | Structural read/write with boundary validation | `testUndefinedSequenceRequiresZeroLengthDelimiter`, `testDefinedSequenceRejectsNonItemContent`, resource-limit tests | Fuzzing and external malformed corpus |
| Encapsulated Pixel Data fragments | PS3.5 8 and Annex A | Fragment preservation only | `testReadLimitsCountPixelFragmentsSeparatelyFromOffsetTable`, `testDefaultWriterPreservesEncapsulatedTransferSyntaxUID` | Extended Offset Table validation and codecs |
| Private Creator block resolution | PS3.5 7.8 | Structural resolution and byte preservation | `testImplicitVRPrivateCreatorResolvesPrivateBlock`, `testPrivateCreatorReservationsAreScopedPerSequenceItem` | Safe creation/editing and optional private dictionaries |
| Default, ISO_IR 100, ISO_IR 192 repertoires | PS3.5 6.1 and 6.2 | Semantic read/write for supported repertoires | `testLatin1SpecificCharacterSetRoundTrips`, `testUTF8SpecificCharacterSetRoundTrips`, `testNestedCharacterSetOverrideDoesNotLeakToSiblingItem` | PN model, ISO 2022, wider repertoire corpus |
| Unsupported character repertoires | PS3.5 6.1 | Explicitly unsupported | `testUnsupportedCharacterSetDoesNotFallBackToUTF8` | Add repertoires with normative vectors |
| Lazy Bulk Data | PS3.5 value fields, PS3.18/PS3.19 bulk-data model | Opt-in file-backed ranges and bounded reads for defined-length binary VRs and encapsulated Items | `testFileBackedBulkDataRemainsLazyUntilRequested`, `testEncapsulatedPixelFragmentCanRemainFileBacked`, `testLazyBulkDataReportsMissingSourceBeforeWrite` | Streaming output without full materialization |
| Basic DICOMDIR and file-sets | PS3.3 Annex F, PS3.10 8 | Structural PATIENT/STUDY/SERIES/IMAGE read/write; graph, File-set/File IDs, and referenced Part 10 identities validated | `testWriteDicomDir`, `testWriteDicomDirRejectsInvalidFileIDs`, `testDirectoryStructureValidationRejectsSemanticGraphErrors` | External-tool exchange, remaining record types, update semantics, File-set Descriptor, PS3.11/PS3.12 profiles and formats |
| DICOM JSON | PS3.18 Annex F | Not conformant | none | Value, PN, SQ, null, InlineBinary, BulkDataURI |
| Native DICOM Model XML | PS3.19 Annex A, used by PS3.18 | Not conformant | none | Namespace, values, PN, SQ, bulk data, escaping |
| DICOM Upper Layer association | PS3.8 | Experimental | limited User Information tests | Full state/negotiation/fragmentation and peer tests |
| DIMSE services | PS3.7 | Experimental/partial | command-set endian test plus legacy service tests | Complete service/status/cancel matrix |
| TLS and DICOM security profiles | PS3.15 | Not implemented | none | Transport, identity, audit, signatures, encryption |
| IOD and module validation | PS3.3 | Not implemented | none | Separate declarative validation layer |
| Context Groups and terminology | PS3.16 | Not implemented | none | Versioned terminology layer |

## Corpus policy

Qualification uses three complementary categories:

1. synthetic boundary and malformed-input fixtures retained as unit tests;
2. byte-preserving round trips over the repository's existing sample corpus;
3. independent comparison with DCMTK and pydicom or GDCM.

The first two categories currently exist. The independent comparison suite and
fuzzing corpus remain release gates and must not be inferred from the current
test count.
