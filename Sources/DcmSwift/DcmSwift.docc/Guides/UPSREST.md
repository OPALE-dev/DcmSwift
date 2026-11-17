# Worklist Service (UPS-RS)

Manage the DIMSE UPS worklist over HTTP and receive notifications over
WebSocket (PS3.18 2026d, chapter 11 and 8.10).

## Start the service

```sh
DcmServer --aet UPSSCP --port 11112 --ups-directory ./ups \
  --http-port 8080 --http-base-path /dicomweb
```

No composite-instance storage directory is required. Add
`--storage-directory ./archive` to also serve Studies (QIDO-RS, WADO-RS,
STOW-RS) on the same HTTP listener. `--ups-notify AET=host:port` optionally
adds DIMSE Event destinations. HTTP and DIMSE use the **same** UPS objects,
Transaction UIDs, subscriptions and deletion locks.

The built-in WebSocket transport requires macOS 13 or iOS 16 or later,
or Linux. Earlier Apple deployment targets retain the existing HTTP
transport; an embedding host can provide its own notification transport
using `DICOMUPSEventHub`. No package-wide deployment minimum is raised.

`--http-public-origin https://pacs.example.test` supplies the externally
visible authority when a reverse proxy terminates TLS. The base path is
appended to this authority. Subscription responses then contain `wss:`
notification URLs. Native HTTPS uses the existing TLS server options.

## Create and perform work

When Accept is absent, the response defaults to DICOM JSON. The `accept`
query parameter and Accept header can select multipart Native XML.

Supply `application/dicom+json` as an array containing **one** DICOM JSON
dataset, or `multipart/related; type="application/dicom+xml"` with one
Native DICOM Model XML part. The creation dataset has the same mandatory
attributes as DIMSE N-CREATE; see <doc:UnifiedProcedureStep>.

```sh
curl -X POST 'http://localhost:8080/dicomweb/workitems?workitem=2.25.123' \
  -H 'Content-Type: application/dicom+json' \
  --data-binary @scheduled.json
curl 'http://localhost:8080/dicomweb/workitems/2.25.123' \
  -H 'Accept: application/dicom+json'
```

Create returns 201 and a Location URL; creating the same UID twice returns
409. A UID may instead be supplied in SOP Instance UID in the creation
payload. A missing UID or conflicting URI/payload UIDs are rejected. Retrieve
never exposes the Transaction UID.

| Request | Purpose |
| --- | --- |
| `PUT /workitems/{uid}/state?requester={ae}` | Claim, complete or cancel; payload contains Procedure Step State and Transaction UID |
| `POST /workitems/{uid}?transactionuid={uid}` | Update an owned workitem; payload contains the changed attributes |
| `POST /workitems/{uid}/cancelrequest?requester={ae}` | Request that the performer cancel; optional cancellation reason/contact dataset |
| `GET /workitems?ProcedureStepState=SCHEDULED` | Find workitems |

A cancel request on an IN PROGRESS instance acknowledges the request with
202; the performing owner decides whether to cancel. A final-state request
checks the same nested final attributes as DIMSE. A missing or incorrect
ownership token returns 400. State conflicts return 409, missing workitems
404, malformed datasets 400, unsupported request media 415, oversized
requests 413 and unacceptable response media 406. Repeating a final-state
request returns 200 with a Warning header.

Search accepts keyword or hexadecimal matching keys, nested sequence
paths, `includefield`, `offset`, and `limit`. It includes required UPS return
attributes without requiring `includefield`. `includefield=all` includes all
stored attributes except Transaction UID. Empty searches return the JSON
array `[]` with status 200. Result counts are capped by `maximumResults`;
a Warning header indicates additional matches. Fuzzy, multiple-value and
empty-value matching extensions are explicitly rejected when requested.
Representations use UTF-8; character set transcoding and negotiation are not
implemented. Bulk Data references are rejected in Worklist payloads.

## Subscribe and reconnect

First open a WebSocket Notification Connection at:

```text
ws://localhost:8080/dicomweb/subscribers/WATCHER
```

Send an Origin header. The optional `dicom` subprotocol is accepted when
offered. Then create a subscription:

```sh
curl -X POST \
  'http://localhost:8080/dicomweb/workitems/2.25.123/subscribers/WATCHER?deletionlock=true'
```

The response is 201 with the notification URL in Content-Location.
Subscribing before opening the connection returns 404. The receiving AE
is scoped by the path, and must be a non-empty DICOM AE Title of at most
16 ASCII bytes. The host must authorize access to AE titles and workitems;
a path value is an identifier, not an authentication credential.

Each event is a WebSocket **text** message containing one DICOM JSON
object, with Affected SOP Class UID, Message ID, Affected SOP Instance UID,
and Event Type ID. The event envelope uses the UPS Event SOP Class UID
specified by PS3.18, whereas DIMSE commands use UPS Push. Event attributes
are the same data projected by the DIMSE UPS service.

The connection supports ping/pong and the closing handshake. Client
application messages are rejected with close code 1003; unmasked client
frames are rejected with 1002. Incoming frames are bounded to 64 KiB. Each connection
buffers at most 64 pending reports; a slow consumer is disconnected when
that buffer fills. This does not remove its persisted subscriptions or
release its deletion locks.

On disconnection, reopen the same subscriber URL. Existing subscriptions
resume delivery of subsequent events; past events are not replayed. Each
connection is independent, including concurrent connections for one AE.

Use the Global Subscription UID `1.2.840.10008.5.1.4.34.5` instead of a
workitem UID to subscribe to all workitems. For a filtered global selection,
use `1.2.840.10008.5.1.4.34.5.1` and a percent-encoded `filter` list such as
`filter=ScheduledProcedureStepPriority%3DHIGH`. Filter criteria are
comma-separated attribute/value pairs and use the core UPS matcher.

- `DELETE /workitems/{uid}/subscribers/{ae}` unsubscribes from one workitem.
- DELETE on a global subscription removes all of that AE's subscriptions
  and deletion locks.
- `POST /workitems/{global-uid}/subscribers/{ae}/suspend` stops subscribing
  to new workitems and preserves existing specific subscriptions.

Final instances are retained indefinitely. Subscription fan-out uses one
owning UPS service per index, as described in <doc:UnifiedProcedureStep>.

## Embed and verify

Pass `DICOMUPSRESTService(steps: ups)` as the `worklist` parameter of
`DICOMwebOriginServer`. The transport uses `ups.eventHub`; the same `ups`
can also be registered with `DICOMServer` for DIMSE. OPTIONS advertises
workitem and notification resources alongside the Studies Service.
See <doc:UPSRESTArchitecture> for the integration contract.

```sh
swift test --filter DcmSwiftUPS
python3 Scripts/interop/ups_rs.py http://127.0.0.1:8080/dicomweb 11112
```

The independent peer requires pynetdicom, pydicom and websockets. It checks
HTTP creation, DIMSE visibility and claiming, HTTP ownership errors,
WebSocket events and control frames, XML retrieval, assignment events, reconnect without
resubscription, filtered subscriptions, suspension and error responses.

## Local qualification (2026-10-21)

| Check | Result |
| --- | --- |
| macOS full SwiftPM suite | 406 passed |
| UPS/UPS-RS tests, macOS | 22 passed (16 DIMSE, 6 REST) |
| UPS/UPS-RS tests, Linux aarch64 / Swift 6.2.4 | 22 passed on a fresh-container SwiftPM rerun |
| UPS/UPS-RS tests, iOS 26.2 Simulator / iPhone 17 Pro | 22 passed |
| macOS release build | Passed |
| Independent peer: urllib, websockets 17.3, pynetdicom 3.0.4, pydicom 3.0.2 | HTTP/XML retrieval, DIMSE claim, Event types 1/2/3/5, reconnect, filtered subscriptions, ping/pong and invalid-frame rejection passed |
| Controlled shutdown | WebSocket GOING DOWN report received; an idle HTTP negotiation closed and the server exited successfully |

One initial Linux SwiftPM run stalled and was interrupted. Direct XCTest
runs (separate and combined groups) and a fresh-container SwiftPM rerun
passed all 22 tests; the cause of the initial stall was not established.
These are local results. CI and qualification against dcm4chee-arc have not
been run for this tranche.
