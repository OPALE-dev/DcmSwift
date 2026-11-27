# Networking

Exchange DICOM data over the DICOM Upper Layer with DIMSE-C and DIMSE-N
services, optionally over TLS.

## Overview

The network API is asynchronous and built on SwiftNIO. An association lives
within the scope of `withAssociation`, which releases it at the end, or aborts
it when the body throws or its task is cancelled.

## Verification and storage

```swift
let client = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "DCMCLIENT"))
let remote = DICOMRemoteNode(aeTitle: "PACS", host: "pacs.example.org", port: 11112)
let file = try DICOMRetrieveItem(file: URL(fileURLWithPath: "/path/to/image.dcm"))

try await client.withAssociation(
    to: remote, presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.verification])
) { association in
    try await association.echo()
}

try await client.withAssociation(
    to: remote, presentationContexts: DICOMPresentationContextProposal.proposals(for: [file])
) { association in
    let status = try await association.store(file)   // streamed from disk
    print(status)
}
```

`proposals(for:)` proposes, for each SOP Class, its compressed Transfer
Syntaxes one per context and the uncompressed ones together, so the file is
sent as encoded or converted between uncompressed syntaxes.
`proposals(for:uncompressed:)` narrows the uncompressed ones: given
`[TransferSyntax.implicitVRLittleEndian]` alone, every uncompressed instance
is sent in Implicit VR Little Endian.

## Query and retrieve

```swift
let identifier = DataSet()
_ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
_ = identifier.set(value: "DOE*", forTagName: "PatientName")
_ = identifier.set(value: "", forTagName: "StudyInstanceUID")

try await client.withAssociation(
    to: remote, presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootFind])
) { association in
    for try await match in association.find(identifier) {
        print(match.string(forTag: "StudyInstanceUID") ?? "")
    }   // leaving the loop early sends C-CANCEL
}
```

`move(_:destination:)` and `get(_:)` retrieve in the same way; C-GET stores
the instances through the `storage` service given to `withAssociation`, on
contexts of the storage SOP classes that ask the SCP role:

```swift
let (contexts, roles) = DICOMPresentationContextProposal.getProposals(
    informationModel: DICOMSOPClass.studyRootGet, sopClasses: [ctImageStorage])
try await client.withAssociation(to: remote, presentationContexts: contexts,
                                 roleSelections: roles, storage: archive) { association in
    let result = try await association.get(identifier)
    print(result.progress.completed)
}
```

`getProposals` proposes each class with the uncompressed syntaxes, and with
each common compressed syntax alone, so that an SCP that does not transcode
sends an instance as it keeps it; within 128 contexts, the last classes lose
their compressed contexts first.

## Server

```swift
struct Archive: DICOMStorageService {
    func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
        try instance.write(to: URL(fileURLWithPath: "/data/\(instance.sopInstanceUID).dcm"))
        return .success
    }
}

let server = try DICOMServer(
    configuration: DICOMServerConfiguration(aeTitle: "DCMSERVER", port: 11112), storage: Archive())
try await server.run()   // until the task is cancelled
```

| Service protocol | Adds |
| --- | --- |
| ``DICOMStorageService`` | C-STORE |
| ``DICOMQueryService`` | C-FIND; ``DICOMQueryMatching`` implements the PS3.4 C.2.2.2 matching rules |
| ``DICOMRetrieveService`` | C-MOVE and C-GET |
| ``DICOMStorageCommitmentService`` | Storage Commitment Push Model SCP |
| ``DICOMNormalizedService`` | Other DIMSE-N SOP Classes, by SOP Class UID |

## Tracing PDUs

A client or server configuration takes a ``DICOMPDUTrace``: it receives each
PDU sent or received, as a ``DICOMPDUTraceRecord`` with its bytes as on the
wire, header included, its decoded ``DICOMPDU``, the time, the connection
and its addresses (PS3.8 9.3). DIMSE commands and data sets are the PDVs of
the P-DATA-TF PDUs. On a TLS connection, each record also carries the
``DICOMTLSSession`` once the handshake is done: the protocol version
negotiated and the certificate the peer presented. The trace is called on
the connection's event loop and must return quickly; without one, no PDU is
copied.

```swift
var configuration = DICOMClientConfiguration(aeTitle: "DCMCLIENT")
configuration.pduTrace = { record in
    print(record.direction, String(record.type, radix: 16), record.bytes.count)
}
```

``DICOMPDULayout`` tells where each field of a PDU lies in its bytes, as
PS3.8 9.3 and PS3.7 D.3.3 lay them out: the header, the AE titles, each item
and sub-item with its type, length and value, each presentation data value
with its message control header and fragment. Each ``DICOMPDUField`` has its
range, its kind and its value as text; the fields of an item are its
children. The first bytes of a PDU, or bytes that deviate, are laid out as
far as they go: the bytes after the last field are those the layout could
not account for. The passcode of a user identity is not repeated as a value.

```swift
for field in DICOMPDULayout.fields(of: record.bytes).flatMap(\.leaves) {
    print(field.range, field.name, field.value ?? "")
}
```

## TLS

Give the client a ``DICOMTLSConfiguration`` and mark the node `useTLS: true`;
give the server one in `DICOMServerConfiguration.tls`:

```swift
let tls = try DICOMTLSConfiguration.client(
    pemTrustRootsFile: "/etc/dicom/ca.pem",
    pemCertificateChainFile: "/etc/dicom/client.pem", pemPrivateKeyFile: "/etc/dicom/client-key.pem")
let secureClient = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "DCMCLIENT", tls: tls))
let secureRemote = DICOMRemoteNode(aeTitle: "PACS", host: "pacs.example.org", port: 2762, useTLS: true)
```

## Storage Commitment

```swift
try await client.withAssociation(
    to: remote,
    presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.storageCommitmentPushModel])
) { association in
    if let result = try await association.commit([file.reference], timeout: .seconds(30)) {
        print(result.committed, result.failed)   // nil: no result on this association in time
    }
}
```

An SCP implements ``DICOMStorageCommitmentService`` and passes it to
`DICOMServer(storageCommitment:)`. The server answers the N-ACTION, then sends
the result on the same association, or on a new one to `destination(for:)`
once the SCU has released. An SCU that receives results on new associations
runs a ``DICOMServer`` with a `storageCommitmentReceiver`.

## Other DIMSE-N services

Other DIMSE-N SOP Classes, such as Modality Performed Procedure Step or Print,
use `nCreate`, `nSet`, `nGet`, `nAction`, `nDelete`, and `nEventReport` on the
association, and ``DICOMNormalizedService`` implementations given to
`DICOMServer(normalized:)` by SOP Class UID.
