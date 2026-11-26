# DcmSwiftSQLite

A SQLite implementation of `DICOMArchiveIndex`, in its own `DcmSwiftSQLite`
product: only the applications that add this product link SQLite. It works
with a file database or `:memory:` and creates its schema on open.

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

Its conformance and cross-connection tests are `DcmSwiftSQLiteTests`
(`swift test --filter DcmSwiftSQLiteTests`). SQLite must be available to the
compiler: it is in the SDK on Apple platforms, and `libsqlite3-dev` on Linux.
The `DcmSwift` product itself has no database dependency.
