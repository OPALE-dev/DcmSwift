# DcmSwift 2.0 DICOM traceability matrix

Baseline: DICOM 2026d  
Scope: implemented behavior on the `codex/dcmswift-2.0` branch

This document distinguishes registry knowledge, structural support, semantic
interpretation, codec support, and independently tested interoperability. A
passing structural test is not evidence of IOD, media-profile, or clinical
conformance.

Each capability lists its normative source, the level claimed, the automated
tests that support the claim, and what remains to be qualified.

## Capabilities

### Public tag and UID registry

- **Normative source:** PS3.6.
- **Claimed level:** Known
- **Automated evidence:** `testRuntimeDictionaryComesFromDICOM2026d`
- **Remaining qualification:** Generate command-set registry from PS3.7

### Transfer Syntax capability separation

- **Normative source:** PS3.5 Annex A, PS3.6 UID registry.
- **Claimed level:** Known vs implemented capability
- **Automated evidence:** `testKnownTransferSyntaxIsNotAutomaticallyImplemented`, `testUnimplementedTransferSyntaxIsRejected`
- **Remaining qualification:** Independent toolkit matrix

### Implicit VR Little Endian

- **Normative source:** PS3.5 7 and Annex A.
- **Claimed level:** Structural read/write
- **Automated evidence:** round-trip corpus plus `testDIMSECommandSetUsesLittleEndianValues`
- **Remaining qualification:** Byte-exact external corpus comparison

### Explicit VR Little Endian

- **Normative source:** PS3.5 7 and Annex A.
- **Claimed level:** Structural read/write
- **Automated evidence:** round-trip corpus and core safety tests
- **Remaining qualification:** Byte-exact external corpus comparison

### Explicit VR Big Endian

- **Normative source:** PS3.5 Annex A, retired.
- **Claimed level:** Structural read/write
- **Automated evidence:** `testBigEndianTransferSyntaxExposesBigEndianEncoding`, `testPart10BigEndianDatasetStartsAfterCompleteFileMetaInformation`
- **Remaining qualification:** Independent toolkit comparison

### Deflated Explicit VR Little Endian

- **Normative source:** PS3.5 A.5.
- **Claimed level:**
  - Part 10 structural read/write
  - no DIMSE claim
- **Automated evidence:**
  - `testDeflatedExplicitVRLittleEndianPart10RoundTrip`
  - `testReadsIndependentPythonRawDeflateFixture`
  - `testDeflatedDataSetHonorsInflatedSizeLimit`
  - `testRawDeflateRejectsTruncationAndUnexpectedTrailingBytes`
- **Remaining qualification:** Streaming inflation/output and independent toolkit file exchange

### Modern and binary VR headers

- **Normative source:** PS3.5 6.2 and 7.1.
- **Claimed level:** Structural and multi-valued semantic support
- **Automated evidence:**
  - `testAttributeTagValueUsesTargetByteOrder`
  - `testModernTextVRUsesLongExplicitHeaderAndURIStaysASCII`
  - `testFloatingPointAndModernBinaryVRSetters`
  - `testMultiValuedBinaryVRsRoundTripWithTypedAccessors`
  - `testExplicitVRRejectsUnknownCodeAndNonZeroReservedBytes`
- **Remaining qualification:** Complete per-VR semantic validation

### Signed and unsigned numeric values

- **Normative source:** PS3.5 6.2.
- **Claimed level:** Scalar and multi-valued semantic support
- **Automated evidence:**
  - `testUnsignedVRValuesPreserveFullRange`
  - `testSignedIntegerSettersPreserveSign`
  - `testDataElementTranscodesNumericValueByteOrder`
  - `testDictionaryVMValidationHandlesRangesAndMultiples`
- **Remaining qualification:** Expand malformed-length and overflow matrix

### Part 10 File Meta Information

- **Normative source:** PS3.10 7.1.
- **Claimed level:** Structural read/write plus identity checks
- **Automated evidence:** `testFileMetaInformationIsExplicitLittleEndianAndRecalculated`, `testFileMetaValidationReportsMissingAndMismatchedIdentifiers`
- **Remaining qualification:** Application-profile validation

### Defined/undefined-length Sequences and Items

- **Normative source:** PS3.5 7.5.
- **Claimed level:** Structural read/write with boundary validation
- **Automated evidence:** `testUndefinedSequenceRequiresZeroLengthDelimiter`, `testDefinedSequenceRejectsNonItemContent`, resource-limit tests
- **Remaining qualification:** Fuzzing and external malformed corpus

### Encapsulated Pixel Data fragments

- **Normative source:** PS3.5 8 and Annex A.
- **Claimed level:** Fragment preservation only
- **Automated evidence:** `testReadLimitsCountPixelFragmentsSeparatelyFromOffsetTable`, `testDefaultWriterPreservesEncapsulatedTransferSyntaxUID`
- **Remaining qualification:** Extended Offset Table validation and codecs

### Private Creator block resolution

- **Normative source:** PS3.5 7.8.
- **Claimed level:** Structural resolution and byte preservation
- **Automated evidence:** `testImplicitVRPrivateCreatorResolvesPrivateBlock`, `testPrivateCreatorReservationsAreScopedPerSequenceItem`
- **Remaining qualification:** Safe creation/editing and optional private dictionaries

### Specific Character Set Defined Terms

- **Normative source:** PS3.3 C.12.1.1.2, PS3.5 6.1 and Annexes H, I, J, K.
- **Claimed level:** Semantic read/write of all Defined Terms, ISO 2022 Code Extensions, GB18030-2022, GBK
- **Automated evidence:**
  - `testAnnexH3JapanesePersonNameWithDefaultValue1`
  - `testAnnexH3JapanesePersonNameWithKatakanaValue1`
  - `testAnnexI2KoreanPersonName`
  - `testAnnexI3KoreanLongTextWithEscapeAtLineStart`
  - `testAnnexJ1ChinesePersonNameInUTF8`
  - `testAnnexJ2ChineseLongTextInUTF8`
  - `testAnnexJ3ChinesePersonNameInGB18030`
  - `testAnnexJ4ChineseLongTextInGB18030`
  - `testAnnexK2ChinesePersonNameWithGB2312`
  - `testAnnexK3ChineseLongTextWithGB2312`
  - `testDCMTKCharacterSetFilesMatchPydicom`
  - `testEverySingleByteRepertoireRoundTrips`
  - `testSingleByteCodeExtensionsSwitchG1AndRestoreValue1`
  - `testGB18030FourByteAndSupplementaryCodes`
  - `testCodeExtensionsRoundTripThroughPart10Encoding`
  - `testLatin1SpecificCharacterSetRoundTrips`
  - `testUTF8SpecificCharacterSetRoundTrips`
  - `testNestedCharacterSetOverrideDoesNotLeakToSiblingItem`
- **Remaining qualification:** PN model, per-VR repertoire validation, ISO 2022 write exchange with DCMTK

### Delimiters and malformed text

- **Normative source:** PS3.5 6.1.2.3, 6.1.2.5.3.
- **Claimed level:**
  - Single-byte 05/12 only
  - Value 1 restored at delimiters and Control Characters
  - invalid bytes and declarations rejected
- **Automated evidence:**
  - `testOnlySingleByte0512SeparatesValues`
  - `testRomajiYenSignAndOverlineFollowISOIR14`
  - `testValue1IsRestoredAfterControlCharactersAndDelimiters`
  - `testMalformedBytesAreNotDecoded`
  - `testSpecificCharacterSetDeclarations`
  - `testUnsupportedCharacterSetDoesNotFallBackToUTF8`
- **Remaining qualification:** `\nnn` display substitution

### Lazy Bulk Data

- **Normative source:** PS3.5 value fields, PS3.18/PS3.19 bulk-data model.
- **Claimed level:** Opt-in file-backed ranges and bounded reads for defined-length binary VRs and encapsulated Items
- **Automated evidence:**
  - `testFileBackedBulkDataRemainsLazyUntilRequested`
  - `testEncapsulatedPixelFragmentCanRemainFileBacked`
  - `testLazyBulkDataReportsMissingSourceBeforeWrite`
- **Remaining qualification:** Streaming output without full materialization

### Native Pixel Data and rendering

- **Normative source:** PS3.3 C.7.6.3, C.7.9.2, C.11.1, C.11.2, C.11.6; PS3.5 8.1.1.
- **Claimed level:** Stored values, grayscale pipeline, color conversions, PNG export
- **Automated evidence:**
  - `testStoredValuesIgnoreUnusedBitsAndSignExtend`
  - `testLegacyHighBitAboveBitsStored`
  - `testOneBitFramesAreNotPaddedAndMayStartInsideAByte`
  - `testThirtyTwoBitUnsignedValuesKeepTheirFullRange`
  - `testPlanarConfigurationOneIsReturnedPixelByPixel`
  - `testYBRFull422SharesChromaBetweenPixelPairs`
  - `testBigEndianPixelDataIsNormalized`
  - `testLinearWindowMatchesTheNormativeExamples`
  - `testSigmoidAndLinearExactFunctions`
  - `testLinearExactIdentityExampleThroughThePipeline`
  - `testRescaleThenWindowForCTValues`
  - `testIdentityVOIUsesThePossibleRangeAndMonochrome1IsInverted`
  - `testModalityLUTSequence`
  - `testVOILUTWithEightBitEntriesEncodedInSixteenBits`
  - `testFunctionalGroupsOverrideTopLevelValuesPerFrame`
  - `testFloatPixelDataUsesTheValueRange`
  - `testYBRFullConvertsWithCCIR601Coefficients`
  - `testPaletteColorClampsAndScalesSixteenBitEntries`
  - `testSegmentedPaletteSegmentsExpand`
  - `testInvalidImagesAreReported`
  - `testPNGEncodingIsValidAndLossless`
  - `testPNGDecodesWithImageIO`
  - `testToPNG`
  - `testExternalDICOMCorpusRenders`
- **Remaining qualification:** Overlays, padding, presentation states, ICC, encapsulated codecs

### Encapsulated frames and codecs

- **Normative source:** PS3.5 A.4, A.4.2, A.4.13, Annex G; PS3.3 C.7.6.3.1.8.
- **Claimed level:**
  - Frame assembly
  - RLE and Deflated Image Frame decode/encode
  - codec registry
- **Automated evidence:**
  - `testRLESegmentDecodingFollowsTheAnnexGPseudoCode`
  - `testHandEncodedRLEFrames`
  - `testRLEEncoderRunsFollowAnnexG`
  - `testRLERoundTripsEveryLayout`
  - `testBasicOffsetTableFromAnnexG6`
  - `testFramesSpanningFragmentsAndOffsetTableErrors`
  - `testExtendedOffsetTableExcludesFragmentPadding`
  - `testRLEImageRendersAfterAPart10RoundTrip`
  - `testDeflatedImageFrameCompressionRoundTrips`
  - `testRegisteredDecodersTakePrecedence`
  - `testExternalDICOMCorpusRenders`
- **Remaining qualification:**
  - JPEG family, JPEG 2000, HTJ2K, JPEG XL
  - transcoding API

### JPEG Lossless (Processes 14/15)

- **Normative source:** PS3.5 A.4.1; ITU-T T.81 Annexes C, D, F.1.2, F.2.2, H, K.2.
- **Claimed level:**
  - Huffman decode/encode
  - arithmetic decode
- **Automated evidence:**
  - `testLibjpegTurboStreamsDecodeExactly`
  - `testArithmeticLosslessIndependentSOF11Vector`
  - `testArithmeticLosslessComponentsShareStatisticsByTable`
  - `testInvalidLosslessStreamsAreRejected`
  - `testEncoderRoundTripsEveryPredictorAndLayout`
  - `testPointTransformDiscardsOnlyTheLowBits`
  - `testOptimizedHuffmanCodesNeverExceedSixteenBits`
  - `testEncoderRejectsUnsupportedLayouts`
  - `testExternalDICOMCorpusRenders`
- **Remaining qualification:**
  - Subsampled components
  - restart intervals inside lines
  - arithmetic encoding

### JPEG Baseline, Extended, and non-hierarchical progression

- **Normative source:** PS3.5 A.4.1; ITU-T T.81 Annexes A, B, C, D, F, G, K.1, K.2.
- **Claimed level:**
  - Huffman decode/encode
  - arithmetic SOF9/SOF10 decode
  - IJG integer pipeline bit-exact with libjpeg-turbo
- **Automated evidence:**
  - `testDecodingIsBitExactWithLibjpegTurbo`
  - `testArithmeticSequentialAndProgressiveFixtures`
  - `testArithmeticDCTMatchesLibjpegTurboWhenAvailable`
  - `testArithmeticDCTColorAndTwelveBitWhenAvailable`
  - `testEncapsulatedYBRImageRendersAsRGB`
  - `testEncoderRoundTripsSamplingModesAndRestartMarkers`
  - `testEncoderMatchesLibjpegTurboIntegerPipelineWhenAvailable`
  - `testExtendedEncoderRoundTripsTwelveBitMonochrome`
  - `testEncoderRejectsUnsupportedInputs`
  - `testInvalidStreamsAreRejected`
  - `testRetiredProgressiveHuffmanSyntaxesRemainReadable`
  - `testKnownTransferSyntaxIsNotAutomaticallyImplemented`
  - `testExternalDICOMCorpusRenders`
- **Remaining qualification:**
  - Arithmetic encoding
  - signed/YBR input
  - streaming coefficient storage
  - performance

### JPEG hierarchical (Processes 16-29)

- **Normative source:** PS3.5 A.4.1; ITU-T T.81 Annex J, B.3.2, B.3.3.
- **Claimed level:** Decode of every first and differential frame type with expansion
- **Automated evidence:**
  - `testDecodingMatchesTheISOReferenceWithinTolerance`
  - `testEveryHierarchicalSyntaxIsDecodable`
  - `testNonHierarchicalDecodersDelegateHierarchicalStreams`
  - `testSingleFrameStreamsUnderHierarchicalSyntaxesStillDecode`
  - `testMalformedStreamsAreRejectedWithoutCrashing`
- **Remaining qualification:**
  - Bit-exact match with the fixed-point reference
  - subsampled lossless frames
  - encoding

### JPEG-LS (Lossless and Near-Lossless)

- **Normative source:** PS3.5 A.4.3; ITU-T T.87.
- **Claimed level:**
  - Decode of every interleave mode, near-lossless coding, LSE preset parameters, restart intervals, HP color transforms
  - encode with default parameters
- **Automated evidence:**
  - `testDecodingMatchesTheSourceWithinNear`
  - `testEncodingReproducesCharLSByteForByte`
  - `testConformanceStreamsWithPresetParameters`
  - `testEncoderRoundTripsSignedAndNearLosslessFrames`
  - `testCapabilitiesAndRegistry`
  - `testMalformedStreamsAreRejectedWithoutCrashing`
  - `testFullConformanceSuiteWhenAvailable`
- **Remaining qualification:**
  - Mapping tables (palettes)
  - oversize dimensions (LSE type 4)
  - encoding with custom preset parameters or subsampling
  - SIMD performance

### Basic DICOMDIR and file-sets

- **Normative source:** PS3.3 Annex F, PS3.10 8.
- **Claimed level:**
  - Legacy PATIENT/STUDY/SERIES/IMAGE plus typed generic record-tree read/write
  - fail-closed public tree reconstruction from serialized offsets
  - synthetic round-trip of all 35 current F.4-1 types with unconditional top-level Type 1/2 keys from F.5 and included macros
  - lossless view, graph, hierarchy, common Type 1C keys, recursive Basic/Enhanced Coded Entry and SOP Instance Reference checks, Scope of Inventory structure and locally determinable dependencies, F.7 Icon Image structure/pixel constraints, verified SR and Hanging Protocol conditions, Related General SOP Class UID, and selected referenced-instance conditions
  - unknown/retired/misplaced record types load and stay traversable
- **Automated evidence:**
  - `testWriteDicomDir`
  - `testGenericDirectoryRecordTreeWritesAdditionalRecordTypes`
  - `testGenericDirectoryRecordTreeRejectsInvalidDefinitions`
  - `testGenericWriterRoundTripsEveryCurrentDirectoryRecordType`
  - `testDirectoryRecordIncludedMacroTopLevelKeys`
  - `testScopeOfInventoryMacroValidation`
  - `testDirectoryRecordCodeSequenceMacroValidation`
  - `testSOPInstanceReferenceMacroValidation`
  - `testIconImageKeyValidation`
  - `testDirectoryRecordTypeRegistryAndLosslessGenericView`
  - `testDirectoryRecordKeyValidationCoversBasicAndRTRecords`
  - `testDirectoryRecordConditionalKeyValidation`
  - `testDirectoryRecordSelfContainedConditionalRules`
  - `testReferencedInstanceConditionalDirectoryKeys`
  - `testReferencedSRConceptModifierRequiresDirectoryContentSequence`
  - `testDirectoryStructureValidationRejectsSemanticGraphErrors`
  - `testUnknownAndRetiredDirectoryRecordTypesRemainTraversable`
- **Remaining qualification:** Complete semantic per-type writer qualification, deeper IOD/module-dependent F.5 conditions and conditional/nested included macros, palette LUT semantics, external-tool exchange, update semantics, descriptor content decoding, PS3.11/PS3.12 profiles and formats

### DICOM JSON

- **Normative source:** PS3.18 Annex F.
- **Claimed level:** Not conformant
- **Automated evidence:** none
- **Remaining qualification:** Value, PN, SQ, null, InlineBinary, BulkDataURI

### Native DICOM Model XML

- **Normative source:** PS3.19 Annex A, used by PS3.18.
- **Claimed level:** Not conformant
- **Automated evidence:** none
- **Remaining qualification:** Namespace, values, PN, SQ, bulk data, escaping

### DICOM Upper Layer association

- **Normative source:** PS3.8.
- **Claimed level:** Experimental
- **Automated evidence:** limited User Information tests
- **Remaining qualification:** Full state/negotiation/fragmentation and peer tests

### DIMSE services

- **Normative source:** PS3.7.
- **Claimed level:** Experimental/partial
- **Automated evidence:** command-set endian test plus legacy service tests
- **Remaining qualification:** Complete service/status/cancel matrix

### TLS and DICOM security profiles

- **Normative source:** PS3.15.
- **Claimed level:** Not implemented
- **Automated evidence:** none
- **Remaining qualification:** Transport, identity, audit, signatures, encryption

### IOD and module validation

- **Normative source:** PS3.3.
- **Claimed level:** Not implemented
- **Automated evidence:** none
- **Remaining qualification:** Separate declarative validation layer

### Context Groups and terminology

- **Normative source:** PS3.16.
- **Claimed level:** Not implemented
- **Automated evidence:** none
- **Remaining qualification:** Versioned terminology layer

## Corpus policy

Qualification uses three complementary categories:

1. synthetic boundary and malformed-input fixtures retained as unit tests;
2. byte-preserving round trips over the repository's existing sample corpus;
3. independent comparison with DCMTK and pydicom or GDCM.

The first two categories currently exist. The independent comparison suite and
fuzzing corpus remain release gates and must not be inferred from the current
test count.
