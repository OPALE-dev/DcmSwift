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

A client that trusts its own authorities, or presents a client certificate,
runs within `withTLS`, which shuts its HTTP client down after; its chain is
checked by BoringSSL, as for DIMSE:

```swift
let tls = try DICOMTLSConfiguration.client(pemTrustRootsFile: "/etc/dicom/ca.pem")
let found = try await DICOMwebClient.withTLS(tls, baseURI: "https://pacs.example.org/dicom-web") { client in
    try await client.search(.study)
}
```

Search results report further pages in `remaining`; metadata keeps Bulk Data
URIs in `DataElement.bulkDataURI` instead of loading them.

### Tracing the exchanges

An `httpTrace`, given to a client or to the network configuration of a
server, receives each moment of every exchange as a
``DICOMwebHTTPTraceRecord``: the request head, the response head, each piece
of either payload as it passes, then the end, or the error that stopped it.
A debugging console rebuilds an exchange from the records of one `exchange`
identifier. Without a trace, no payload is copied.

```swift
let client = DICOMwebClient(baseURI: "https://pacs.example.org/dicom-web",
                            httpTrace: { record in console.append(record) })
```

A client traces the header fields it gives AsyncHTTPClient, which adds Host
and the framing fields; a server traces those it received and sent. A client
traces the end once the response payload has been read; a stream left
unfinished has none. WebSocket UPS event notifications are not traced.

## Server

``DICOMwebOriginServer`` answers requests independently of the transport, from
three services shared with DIMSE implementations:

| Service | Transaction |
| --- | --- |
| ``DICOMwebSearchService`` | Search (QIDO-RS): matches of a C-FIND identifier |
| ``DICOMwebRetrieveService`` | Retrieve (WADO-RS): the instances of a study, series, or instance |
| ``DICOMwebStoreService`` | Store (STOW-RS): one received instance |

``DICOMwebServer`` serves it over HTTP/1.1 or HTTPS. ``DICOMArchive``
implements every service over a folder, for DIMSE and DICOMweb alike:

```swift
let services = DICOMArchiveServices(archive: DICOMArchive(directory: folder))
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

## Large objects and streamed responses

Stored Part 10 datasets are decoded with deferred binary values for metadata and frames.
The lazy path is used only when the payload is exactly the file's dataset, with the same
transfer syntax, offset and length. Raw dataset slices, memory payloads and deflated
syntaxes keep the bounded byte decoder. `DICOMDataSetCoding.decode` also exposes this
choice for a `DICOMDataSetPayload`; existing byte-based calls retain their behavior.
A `BulkDataURI` can be encoded without reading the corresponding value.

Instance and frame response streams produce data only as their consumer advances.
The HTTP adapter awaits each write. File reads use chunks of at most one MiB; frames
are encoded or decoded one at a time on the bounded blocking pool, and encoded
file-backed fragments are not accumulated in the dataset. JPEG 2000 Part 2 component
collections remain decoded one collection at a time. A consumer must iterate or cancel
the stream rather than collect the entire response when it needs bounded memory.

Resource lookup, frame-number validation and content negotiation happen before the
response. A later file, truncation or codec failure terminates the stream; an HTTP 200
header alone does not establish receipt of the complete body. Multipart frame responses
may use chunked transfer and omit per-part lengths when the encoded length is not known.

A retrieve service can optionally implement ``DICOMwebDataSetRetrieveService`` to apply
metadata/clinical projections to a lazy dataset for metadata and frame resources, without
creating a second complete pixel file. The application remains responsible for its access,
identity, signature and integrity checks. Part 10 instance retrieval keeps using the
service's original `instances` method.
