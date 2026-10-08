# Changelog

All notable changes to DcmSwift are listed here, newest first. This file is
generated from the commit history with [git-cliff](https://git-cliff.org); do
not edit it by hand.

## [Unreleased]

### Added

- Add the DICOMweb Studies Service origin server
- Add DICOMweb media types, multipart payloads, search queries, and resources
- Add Dependabot, CodeQL, and Swift Package Index configuration
- Add the license, third-party notices, and community files
- Add status badges to the README
- Publish the DocC site to GitLab and GitHub Pages
- Add DcmConvert image conversion tool
- Add the Native DICOM Model XML (PS3.19 A.1)
- Add DIMSE-N services and Storage Commitment
- Model DICOM Upper Layer PDUs and the PS3.8 state machine
- Encode JPEG XL and rebuild recompressed JPEG
- Encode JPEG 2000 Part 2 multi-frame images
- Decode JPEG 2000 Part 2 multi-component images
- Model Person Name and multi-valued text
- Decode DICOM JPEG XL with vendored libjxl
- Encode HTJ2K with OpenJPH, and plan the rendering phase
- Decode JPEG 2000 and HTJ2K, and encode JPEG 2000, with OpenJPEG
- Decode and encode JPEG-LS in Swift
- Decode the hierarchical JPEG transfer syntaxes
- Decode arithmetic JPEG transfer syntaxes
- Encode JPEG Baseline and Extended frames
- Decode JPEG Baseline and Extended bit-exactly with libjpeg-turbo
- Encode JPEG Lossless (Process 14) in Swift
- Decode JPEG Lossless (Process 14) in Swift
- Decode encapsulated frames with RLE and Deflated codecs
- Support every DICOM Specific Character Set Defined Term
- Publish JUnit test reports from every CI job
- Add a generic DICOMDIR record tree writer
- Model PS3.3 directory record types
- Add gitlab CI config
- Add format option to DcmPrint binary (TEXT, JSON, XML)
- Support DICOM File-set Descriptor references
- Implement Deflated Explicit VR Little Endian files
- Add file-backed lazy Bulk Data values
- Support multi-valued binary VRs and dictionary VM rules
- Add DcmIzer target to play with dicomization of standard image formats

### Fixed

- Fix Logger to be Linux compliant
- Fix FoundationXML import
- Fix Image extension for Linux
- Fix FoundationXML import

### Changed

- Serve and consume DICOMweb over HTTP
- Generate the changelog with git-cliff
- Require Swift 6.1 tools in the Swift 5 language mode
- Stop tracking the agent handoff notes
- Rename DcmServer --destination-tlsca to --destination-tls-ca
- Run the GitLab test jobs on GitHub Actions too
- Reorganize the README around the DocC guides
- Update the handoff for the DocC documentation
- Move the documentation into a DocC catalog
- Export rendered frames as JPEG TIFF and Netpbm
- Validate DICOM values and preserve file bytes
- Make JSON and XML decoding strict on Linux too
- Split expressions that Swift 6.1 on Linux cannot type-check
- Finish TLS: the PS3.15 B.12 profile, typed failures, and loopback tests
- Move the network tools to the new stack and remove the old one
- Serve and request associations over SwiftNIO
- Negotiate associations and frame DIMSE messages
- Record the green delivery pipeline
- Refresh the Claude handoff after JPEG XL and PN
- Track the implementation plan as a checklist
- Present the coverage documents as themed tables
- Prepare the JPEG decoders for hierarchical frames
- Read the retired progressive Huffman JPEG syntaxes
- Recompute defined Sequence and Item lengths on write
- Render native Pixel Data portably
- Build iOS CI jobs in a per-job DerivedData
- Pin the 2026.10.07 interoperability corpus checksum
- Run the interoperability corpus in CI on every platform
- Declare iOS support and qualify Apple platforms in CI
- Keep unknown and retired DICOMDIR records traversable
- Expose parsed DICOMDIR record trees
- Validate PS3.3 DICOMDIR icon images
- Validate DICOMDIR SOP instance reference macros
- Validate the DICOMDIR Scope of Inventory macro
- Validate unconditional DICOMDIR macro attributes
- Validate coded entry macros in DICOMDIR records
- Qualify all current DICOMDIR record types
- Validate referenced-instance DICOMDIR conditions
- Enforce self-contained PS3.3 record conditions
- Validate common PS3.3 directory record conditions
- DICOMDIR PS3.3 WIP
- Separate synthetic tests from interoperability corpus
- Record the remaining Swift 6 concurrency gate
- Make RT helper tests report real coverage
- Make the test suite portable to Linux CI
- Validate PS3.3 directory record relationships
- Make DcmIzer main Linux compliant
- Make DicomImage Linux compliant
- Update CI config
- Update CI config
- DcmPrint now prints prettyfied XML and JSON
- Validate DICOMDIR graphs and referenced file identities
- Rebuild Basic DICOMDIR serialization and traversal
- Defer encapsulated Pixel Data fragments
- Reject malformed Explicit VR headers
- Prioritize the binary DICOM roadmap
- Scope character sets across nested datasets
- Resolve private creator blocks within dataset scope
- Validate sequence item boundaries and delimiters
- Bound untrusted DICOM parsing resources
- Validate Part 10 identity consistency and refresh the README
- Complete modern scalar VR encoding paths
- Preserve encapsulated syntaxes and isolate round-trip tests
- Enforce transfer syntax support and correct Part 10 metadata
- Define the DcmSwift 2.0 conformance target and add character sets
- Harden DICOM core and add a 2026d capability baseline
- The current way DICOM is parsed is not ideal for this kind of task

### Removed

- Remove the obsolete test.sh and docs/ ignore rule

### Documentation

- Document the DICOMweb Studies Service
- Document every parameter of the public API comments

### Tests

- Fuzz the parser and decoders, add the DICOM JSON Model, compare with pydicom

## [1.0.0] - 2022-01-07

### Changed

- Update README + minor fixes
- Update test suite resources files

## [0.1] - 2021-12-21

### Added

- Add script to upload resources file for testing
- Add item type documentation
- Add Assoc documentation
- Add Assoc documentation
- Add DicomClient documentation
- Add DicomServer documentation
- Add QueryRetrieveLevel documentation
- Add DataSet documentation
- Add PixelDataAccess documentation
- Add DicomImage documentation
- Add DicomDir documentation
- Add DicomInputStream documentation
- Add StructureSet documentation
- Add Anonimyzer documentation
- Add OffsetInputStream documentation
- Add DicomFile documentation
- Add DicomOutputStream documentation
- Add DicomInputStream documentation
- Add PixelData documentation
- Add DataTag documentation
- Add DataElement documentation
- Add RT documentation
- Add RT documentation : exemples, parameters, returns
- Implement C-ECHO-SCP service using FSM
- Start acceptor side implementation (DicomServer)
- Add StructureSet class for helpers
- Add Plan for RTPlan helpers
- Init RTDose class, with dcmtk as template : https://support.dcmtk.org/docs/classDRTDose.html#aab575ebb9e190a17ae45c1a9abb9ee68
- Add formatPath method, add 4 arrays in class properties
- Add browse method and started to fill images array
- Add createDirectoryRecordSequence method, and add method in dataset
- Start transition to SwiftNIO channel
- Add missing fixes
- Add recursive load of SR items, basic codes and measurements
- Add SR related classes
- Add DicomDir class
- Add format() method to AgeString + unit test
- Add vr and length offsets

### Fixed

- Fix things related to PDU negociation + start C-FIND-SCP
- Fix little issue with implicit C-STORE-RSP
- Fix storescu with DCM4CHEE (test file was broken)
- Fix DcmStore main
- Fix test (wrong argument order)
- Fix CStoreRQ
- Fix fragmented PDU messages
- Fix CStoreRQ which now works
- Fix accepted transfer syntax for C-FIND
- Fix read with ByteToMessageDecoder and improve PDU message decoding
- Fix bug in DcmStore
- Fix Dataset magicbyte again and ECHO succeeded
- Fix dataset transfert syntax for implicit no-preamble DICOM file
- Fix DICOM RT file reading and add test assets for RT and SR
- Fix CStore + add target CFIND
- Fix C-STORE-RQ Dataset byte order + little refactor on DataValue

### Changed

- Make all tests succeeded
- Refactor service classes
- C-FIND-SCU now handle multiple Query Retrieve Levels
- Refactor and reorganize SCU services
- Refactor DicomRT constructor
- Disconnect associations properly
- Let DicomClient C-DIMSE methods throw exceptions
- Update README
- Polish logs
- Reduce warnings
- Better error handling when assoc get rejected
- C-STORE-SCU now working (with HOROS only for now)
- Make C-FIND SCU works with fragmented RSP
- Better DicomService class
- FSM works for C-ECHO-SCU
- Rewrite DicomAssociation using finite state machine pattern (DICOM Upper Layer Protocol for TCP/IP State Machine P08 S9.2)
- Experiment new PDU decoding techniques
- RTPlan helpers done
- Refactor RTDose to Dose
- getDoseImages + refactor
- RTDose : get dose image done
- testGetDose pass
- Clean
- Refactor RTDose and DicomRT
- Refactor test for getUnscaledDose
- Convert image to PNG
- last changes
- add para in dataset's string method, improve dicomdir class
- add values to directory record sequence
- properties structure changed from [:[]] to [:[:]]
- refactor and add values to createDirectoryRecordSequence
- addValue methods
- 3 new testing classes + modifications DicomDir
- Improve studies dictionnaries
- unitary tests dicomdir and [:[]] for studies
- Modifications DICOMDIR class
- C-STORE-SCP proof-of-work, more work needed on file meta info
- Try to fix PDU decoding done wrong
- Better message logging
- Refactor PDUEncoder/decoder for shorter wode
- ECHO server is working again
- Adopt PDUData class in CEcho and CFind
- Introduce PDUData class to encode/decode PDU data in a cleaner way
- Mostly refactoring
- Update README
- Some good progress but still dataset reading issues
- More completion fo better completion
- Complete refactoring for SwiftNIO, only ECHO works for now
- Better channelRead() impl
- Refactor completion for ECHO command
- Echo almost works with NIO
- Clean some logs
- Update README and try Gitlab CI (remove)
- Update README and try Gitlab CI
- Update README
- Minor fix
- Minor fix
- Enable all working unit tests
- Clean
- Trying to fix CFIND
- Better HTML formatting for DICOM SR output
- Use sub-commands in DcmSR
- DICOM SR to HTML basic support
- Better catch of DICOM preamble (or not)
- Modified validate method of UID + related unit test
- Make DataSet empty constructor public again

### Removed

- Remove test resources from source code

### Documentation

- Documentation for RT module
- Comments and copyright
- Documentation
- Documentation + better error handling
- Comment + Clean
- Comments
- Comment and refactor
- Comment and refactor
- Comment and refactor
- Comment and refactor
- Comment and refactor
- Comments and refactor
- Comments and refacor

### Tests

- Tests + Documentation
- Test getUnscaledDose pass
- Test isValid, getImageWidth, getImageHeight for RTDose

## [0.0.1] - 2021-06-25

### Added

- Init AgeString with string + unit tests for AgeString
- Add validate for AgeString
- Add support for AgeString with precision
- Add ArgumentParser support to DcmPrint
- Add swift-argument-parser support to DcmAnonymize
- Add some todos
- Add minimal support form DICOM age string format in DicomAge class
- Add exception support to readDataset() method for cleaner error return
- Implement DicomInputSream
- Add file size deviation indicator to test output
- Added popup button to filter logs by log level
- Added Logger Window; TODO: sorting columns; Issue: columns of AE not sorted ?
- Support C-ECHO
- Support assoc-rq and echo-rq
- Add value format in Magix View menu
- Added file size limit to logger
- Added choose file option; TODO : save file path manually in the settings
- Add better progression support to DicomClient store method
- Add log level + name of file is name of target by default
- Add preferences to magX, with tabs
- Added some documentation to Logger
- Add Logger to replace SwiftyBeaucver
- Add C-Store message support
- Add PDU support
- Add MagiX target
- Add gitignore (fix)
- Add gitignore
- Add CocoaPods and better unit tests

### Fixed

- Fix writing of explicit items with DicomOutputStream
- Fix sequence with implicit VR elements
- Fix read dataset in big endian
- Fix read explicit VR
- Fix items with explicit length in sequence of undefined length
- Fix read some multiframe JPEGBaseline by GE, still some work to do
- Fix font color in binary console with dark mode
- Fix all warning in DcmSift
- Fix a few multithread issues
- Fix write of PixelSequence
- Fix logs
- Fix assoc close in Dicom Client
- Fix saving the size file limit; TODO : save in user defaults. dropped the cleaning of logs by period
- Fix send operation progress in sidebar
- Fix sidebar remove item
- Fix return date in DataElement (DCMSwift)
- Fix merge conflicts
- Fix assoc workflow
- Fix signing
- Fix test
- Fix some function calls
- Fix CFind

### Changed

- Release beta 0.1
- Revive the Networking related stuff
- Move Transfer Syntax related constants to TransferSyntax class (2)
- Move Transfer Syntax related constants to TransferSyntax class
- Divagations...
- Move Anonymizer class to DcmSwift in a new Tools directory
- Move Anonymizer class to DcmSwift in a new Tools directory
- Refactor VR
- Better preamble reading + Anonymizer refactor
- Little refactoring
- Round some corners
- Pass all the test: DICOM file round-trip is working again, using streams instead Data
- Almost fixed DicomOutputStream
- Switch to Swift 5.3 and add test files to DcmSwiftTests target
- Switch to Swift 5.3 and add test files to DcmSwiftTests target
- Use DicomInputStream to load dataset from network command
- Update README
- Switch to SPM and make DcmSwift a standard library package for Swift
- Prepare DicomOutputStream to write datasets
- DicomFile.isDicomFile() now also uses DicomInputStream class (with lower memory footprint)
- Finally use DicomInputStream (using InputStream) in DicomFile class
- Minor fixes
- DicomInputStream is finally working
- Problem with implicit elements
- Revert DataSet changes, add better value formatiing to DicomiX
- Partially use DicomInputStream to read DICOM files
- Mostly refactoring and commenting (2)
- Mostly refactoring and commenting
- Reduce warnings and add some comments
- Improve split views and associated controls synchronization and validation
- Better unit tests with custom invocations
- Convert project to Swift 5
- Server tests
- Searching for better Pixel Sequence data representation
- Cleans
- Scroll to bottom automatically done
- Search done (not pretty)
- Refresh + Erase logs toolbar buttons; TODO: search logs
- Sort columns in Magix
- Moved setPreferences to AppDelegate + UserDefault default values in AppDelegate.init()
- Clear merge errors
- Big pref update: Storages, Listener, Advanced + Storage model + IOD and file copy
- MagiX: Listener pref panel
- Make DICOM server works
- Revert "dicom_server"
- dicom_server
- Rename menu and close #3
- Better management of dA,TM,DT in DataSet class
- Some documentation for logger
- path of file log is displayed in file field in preferences
- Default : save in Documents; added attribute filePath:URL?
- Settings for log level, type of output done : console and file; TODO : file destination to set + make popup button working + find a solution for clearing logs (based on time, or size)
- Logger preferences panel
- Edit remote on double click
- User can remove or add remote in MagiX
- Multi-thread C-STORE operation in MagiX
- Ascending sort for magX ID
- Some documentation
- Replace SwiftyBeauver by Logger class. Add console and file destination !
- Fields displays date in readable format
- Update gitignore
- Done refactoring + tests. Ideally, it would have been better to make DA, TM and DT sub classes of Date, to avoid the 12 conditions for the description of a date range
- Implementation of DateTime; next : refactor some redundant code
- Date reviewed
- Time with FRAC done
- Working on StoreSCU
- Better DicomDate documentation
- Better DicomDate documentation
- Little fix and typo
- STart supporting multiple presentation contexts
- Big refactor and add many constants
- Mostly document DicomDate file and start using it in MagiX for C-FIND query date range parameters
- Review all the MagiX design and features
- New slit view UI
- Update README
- Read/write DICOM files
- First commit
- Initial Commit

### Removed

- Remove ByteOrder and VRMethod anum from DicomConstants
- Remove conditions for remote
- Remove framework SwiftyBeaver

### Tests

- Tests fixed for description of date (local problem)
- Tests done right

<!-- generated by git-cliff -->
