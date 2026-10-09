# Archive Storage

Keep an archive's index and instances in the database and storage of your
choice, without DcmSwift depending on any driver.

## Overview

The archive services (storage, Query/Retrieve, Storage Commitment, Modality
Worklist, Modality Performed Procedure Step, and DICOMweb) are built on two
protocols:

| Protocol | Holds | Provided |
| --- | --- | --- |
| ``DICOMArchiveIndex`` | Documents in collections: instances (indexed attributes and location), worklist items, procedure steps | <ul><li>``DICOMMemoryArchiveIndex``</li><li>``DICOMFileArchiveIndex``: one JSON file per document</li></ul> |
| ``DICOMInstanceStore`` | The bytes of composite instances | ``DICOMFileInstanceStore``: Part 10 files in a directory |

A database adapter is a separate package that depends on DcmSwift and
implements ``DICOMArchiveIndex``; an object-storage adapter implements
``DICOMInstanceStore``. Applications choose them, for example an adapter on
the SQLKit database a Vapor application already has.

```swift
// SQLKitArchiveIndex would come from an adapter package.
let index: DICOMArchiveIndex = SQLKitArchiveIndex(database: app.db as! SQLDatabase)
let archive = DICOMArchive(index: index, store: DICOMFileInstanceStore(directory: folder))
let worklist = DICOMModalityWorklist(index: index)
let steps = DICOMPerformedProcedureStepService(index: index)
let services = DICOMArchiveServices(archive: archive)
var normalized: [String: DICOMNormalizedService] = [:]
for sopClass in DICOMPerformedProcedureStepService.sopClasses { normalized[sopClass] = steps }
let server = try DICOMServer(
    configuration: configuration, storage: services, query: services, worklist: worklist,
    retrieve: services, storageCommitment: services, normalized: normalized,
    eventLoopGroup: app.eventLoopGroup)
```

### Documents

A ``DICOMArchiveDocument`` holds attributes in the DICOM JSON Model (PS3.18
F), keyed by 8 upper-case hexadecimal digits, with IS and DS values as
strings; service metadata, such as an instance's location; and a version.
An adapter stores them as it likes: a JSON column, extracted columns for the
attributes it indexes, or both.

Each method acts on one document atomically. ``DICOMArchiveIndex/replace(_:in:)``
succeeds only when the stored version is the one read, and stores the next
one; services that change state, such as procedure steps, rely on it so that
several servers can share an index.

### Queries

``DICOMArchiveIndex/documents(in:matching:)`` receives a ``DICOMQuery``: the
conditions of the C-FIND Identifier, on tag paths, already normalized:

| Constraint | Meaning | Index form |
| --- | --- | --- |
| `equals` | One of the values: UID lists, exact values | The stored values |
| `wildcard` | `*` and `?`, case-sensitive | `LIKE` with `%` and `_`, escaped |
| `personName` | Folded pattern, tried on each component group | ``DICOMQueryMatcher/foldedName(_:)`` of each group |
| `number` | DS and IS by value | A numeric column |
| `range` | Dates and times, in microseconds | The lower bound of ``DICOMQuery/normalizedRange(_:vr:)`` |
| `dateTime` | A DA and its TM sibling as one DT | The same, on the concatenated value |

The index returns every document that may match; the services then filter
them with ``DICOMQueryMatcher``. An adapter may therefore translate only the
conditions it indexes and ignore the others: results stay exact. It must
never be stricter than a condition.

### Conformance

The `DcmSwiftArchiveConformance` library checks an index without any test
framework: documents, versions and conflicts, collections, and queries whose
results must equal the matcher's.

```swift
import DcmSwiftArchiveConformance

func testConformance() async throws {
    try await DICOMArchiveConformance.check { try await makeEmptyIndex() }
}
```
