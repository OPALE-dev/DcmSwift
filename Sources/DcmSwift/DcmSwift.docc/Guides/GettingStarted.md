# Getting Started

Add DcmSwift as a Swift Package Manager dependency, import the library, then
open a DICOM Part 10 file through ``DicomFile``.

## Package dependency

Use the repository URL and a release or revision appropriate for your project:

```swift
.package(url: "https://github.com/OPALE-dev/DcmSwift.git", from: "2.0.0")
```

Add `DcmSwift` to the dependencies of the target that uses it:

```swift
.target(
    name: "MyApplication",
    dependencies: ["DcmSwift"]
)
```

## Read a file

```swift
import DcmSwift

guard
    let file = DicomFile(forPath: "/path/to/image.dcm"),
    let dataset = file.dataset
else {
    fatalError("The file is not a readable DICOM instance")
}

print(dataset)
```

Parsing a file successfully is not a claim that its IOD is conformant. Consult
<doc:Conformance>, <doc:Traceability>, and <doc:DeferredLimitations> before
using validation results as qualification evidence.

## Build and test the repository

```sh
swift build -c release
swift test --parallel
```

Linux and Apple platforms are release targets. Optional interoperability
corpora are controlled by the environment described in the repository README.
