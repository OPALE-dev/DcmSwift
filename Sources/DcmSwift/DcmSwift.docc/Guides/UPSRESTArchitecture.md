# UPS-RS architecture

The Worklist Service implements PS3.18 2026d chapter 11 and Notification
Connections from 8.10. The DIMSE UPS service remains the single owner of
instances, state transitions, Transaction UID checks and subscriptions.
HTTP maps representations and status codes onto that service; it does not
maintain a separate worklist or duplicate the state machine.

## Contract

| Resource | Method | Operation |
| --- | --- | --- |
| `/workitems` | POST | Create, optional `workitem` UID parameter |
| `/workitems` | GET | Search, matching keys, includefield, offset and limit |
| `/workitems/{uid}` | GET / POST | Retrieve / update (`transactionuid` parameter) |
| `/workitems/{uid}/state` | PUT | Change state with a DICOM dataset |
| `/workitems/{uid}/cancelrequest` | POST | Request cancellation, optional requester AE |
| `/workitems/{uid}/subscribers/{ae}` | POST / DELETE | Subscribe / unsubscribe |
| `/workitems/{global-uid}/subscribers/{ae}/suspend` | POST | Suspend global subscription |
| `/subscribers/{ae}` | WebSocket GET | Notification Connection |

The resources share the configured DICOMweb base path. JSON arrays of
DICOM datasets and multipart Native DICOM XML are the HTTP representations.
WebSocket events are text messages containing one DICOM JSON object,
including event command attributes; no bulk-data representation is used.

Subscriptions and deletion locks persist in the same archive index used
by DIMSE. WebSocket connections are transient and scoped to a receiving
AE. Disconnecting does not unsubscribe or release deletion locks; reconnect
restores notification delivery for existing subscriptions. There is no
replay queue. Slow consumers must be disconnected rather than allowing
unbounded event buffering. The host controls AE authorization and public
HTTP/WS origins, including TLS termination by a reverse proxy.

## Delivery and qualification

Implementation order: HTTP mapping and shared event fan-out, typed NIO
WebSocket upgrade, CLI integration, unit and real-network qualification,
then conformance and progress updates. Tests must cover malformed requests,
media negotiation, state/lock errors, cross-transport instance visibility,
filtered/global subscriptions, disconnect/reconnect, WebSocket control
frames, and coexistence with the Studies Service. Local results and CI
results are reported separately. This document defines the contract; it
is not itself evidence that an operation is implemented or qualified.
