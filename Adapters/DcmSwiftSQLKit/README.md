# DcmSwiftSQLKit

`DcmSwiftSQLKit` implements `DICOMArchiveIndex` on the SQLKit connection that
an application already owns. It adds no database driver to the core DcmSwift
package. SQLKit supports PostgreSQL, MySQL, and SQLite through their respective
drivers.

```swift
import DcmSwift
import DcmSwiftSQLKit
import SQLKit

let database: any SQLDatabase = /* application database */
let index = DICOMSQLKitArchiveIndex(database: database)
try await index.migrate() // once at application startup, before requests
let archive = DICOMArchive(index: index, store: DICOMFileInstanceStore(directory: folder))
```

The version-one migration creates a document table, schema marker, and indexes
for exact top-level SOP Instance, Study Instance, and Series Instance UID
queries. Other query conditions remain candidates for DcmSwift's exact matcher.
Document attributes and service metadata are stored as JSON text. Each document
is one row, so insert, save, and replacement are atomic. Replacement checks its
version inside a single SQL session and reports `conflict` on a stale version.
MySQL uses its connection-local `ROW_COUNT()` after the conditional update;
PostgreSQL and SQLite use a transaction and mutation token.

Only one application instance should run `migrate()` at a time; run it as part
of deployment migrations before starting archive workers. The adapter calls
`SQLDatabase.withSession` for multi-statement replacement and therefore needs
a driver that pins that session to one connection.

Run `swift test` in this directory to execute the archive conformance kit
against SQLiteKit. Set `DCMSWIFT_SQLKIT_POSTGRES_URL` and
`DCMSWIFT_SQLKIT_MYSQL_URL` to also run the integration suite against live
servers. That suite checks the conformance kit and cross-connection conflicts
on each dialect. Separate Linux CI jobs run all three drivers.
