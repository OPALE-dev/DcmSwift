# DICOMweb

Search, retrieve, and store instances over HTTP with the Studies Service of
PS3.18: QIDO-RS, WADO-RS, and STOW-RS.

## Client

``DICOMwebClient`` talks to any origin server, built on AsyncHTTPClient:

```swift
let client = DICOMwebClient(baseURI: "https://pacs.example.org/dicom-web",
                            headers: [("Authorization", "Bearer \(token)")])

// QIDO-RS
var query = DICOMwebSearchQuery()
query.match("PatientName", "DOE*")
query.limit = 20
let studies = try await client.search(.study, query: query)

// WADO-RS: instances in Explicit VR Little Endian, or as stored with "*"
for try await instance in client.instances(study: studyUID, transferSyntax: "*") {
    try instance.data.write(to: folder.appendingPathComponent("\(UUID()).dcm"))
}
let metadata = try await client.metadata(study: studyUID)
let frames = try await client.frames([1], study: studyUID, series: seriesUID, instance: instanceUID)
let jpeg = try await client.rendered(.target(study: studyUID, series: seriesUID, instance: instanceUID,
                                             kind: .rendered), parameters: ["viewport": "512,512"])

// STOW-RS, streamed from disk
let response = try await client.store(files: urls)
print(response.stored.count, response.failed.count)
```

Search results report further pages in `remaining`; metadata keeps Bulk Data
URIs in `DataElement.bulkDataURI` instead of loading them.

## Server

``DICOMwebOriginServer`` answers requests independently of the transport, from
three services shared with DIMSE implementations:

| Service | Transaction |
| --- | --- |
| ``DICOMwebSearchService`` | Search (QIDO-RS): matches of a C-FIND identifier |
| ``DICOMwebRetrieveService`` | Retrieve (WADO-RS): the instances of a study, series, or instance |
| ``DICOMwebStoreService`` | Store (STOW-RS): one received instance |

``DICOMwebServer`` serves it over HTTP/1.1 or HTTPS. ``DICOMDirectoryArchive``
implements every service over a folder, for DIMSE and DICOMweb alike:

```swift
let services = DICOMDirectoryArchiveServices(archive: DICOMDirectoryArchive(directory: folder))
let origin = DICOMwebOriginServer(configuration: .init(basePath: "/dicomweb"),
                                  search: services, retrieve: services, store: services)
let server = try DICOMwebServer(origin: origin, network: .init(port: 8080))
try await server.run()
```

<doc:DcmServer> serves the same directory over DIMSE and DICOMweb with
`--http-port`.

## Resources and representations

| Resource | Representations |
| --- | --- |
| Instances of a study, series, or instance | `multipart/related; type="application/dicom"` in Explicit VR Little Endian or, with `transfer-syntax=*` or the stored UID, as stored; `application/dicom` for one instance |
| Metadata | `application/dicom+json` or `multipart/related; type="application/dicom+xml"`, Pixel Data as a Bulk Data URI to the Pixel Data resource |
| Frames and Pixel Data | Uncompressed `application/octet-stream`, or the stored compressed frames (`image/jls`, `image/jp2`, `image/dicom-rle`, …) |
| Rendered and thumbnail | `image/jpeg` or `image/png`, single or multipart; Structured Reports as `text/html` or `text/plain` |
| Search results | `application/dicom+json` or `multipart/related; type="application/dicom+xml"` |
| Store response | The Store Instances Response Module in JSON or XML |
| Capabilities | A WADL description from OPTIONS on the Base URI |

The conformance details, and what is not supported yet, are in
<doc:Conformance> and <doc:DeferredLimitations>.
