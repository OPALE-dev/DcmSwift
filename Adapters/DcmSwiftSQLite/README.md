# DcmSwiftSQLite

A standalone SQLite implementation of `DICOMArchiveIndex`, packaged apart
from DcmSwift so applications that do not use SQLite do not depend on it.
It works with a file database or `:memory:` and creates its schema on open.

```swift
import DcmSwift
import DcmSwiftSQLite

let index: DICOMArchiveIndex = try DICOMSQLiteArchiveIndex(path: "archive.sqlite")
let archive = DICOMArchive(index: index, store: DICOMFileInstanceStore(directory: folder))
```

The primary key is `(collection, id)`. `insert`, `save`, and `replace` use
SQLite transactions; `replace` updates only the version it read and throws
`DICOMArchiveError.conflict` if another connection changed the document.
Top-level UID equality conditions use an index. All other query conditions
return candidate rows for DcmSwift's exact `DICOMQueryMatcher`.

Run its conformance and cross-connection tests with `swift test` in this
directory. SQLite must be available to the compiler (`libsqlite3-dev` on
Linux). DcmSwift itself remains free of a database dependency.
