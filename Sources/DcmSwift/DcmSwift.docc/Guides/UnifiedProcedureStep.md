# Unified Procedure Step

Create, perform, monitor, and query work items with the DIMSE UPS services
of PS3.4 Annex CC (DICOM 2026d).

## Run a worklist server

```sh
DcmServer --aet UPSSCP --port 11112 \
  --ups-directory ./ups \
  --ups-notify WATCHER=127.0.0.1:11113
```

The directory contains UPS documents and subscriptions, including deletion
locks. Restarting the server preserves them. Repeat `--ups-notify` for each
receiving AE. An unknown receiving AE is refused with C308; subscriptions
are refused with C315 when no notification destinations are configured.
Creation and querying remain available without notification destinations.

The server supports UPS Push, Pull, Watch, Event, and Query presentation
contexts. DIMSE-N commands use the **UPS Push SOP Class UID**, including
commands carried on Pull, Watch, and Event contexts. C-FIND uses the
negotiated Pull, Watch, or Query SOP Class UID.

## Perform a work item

1. N-CREATE a SCHEDULED UPS using Push. Supply the Type 1 and Type 2
   attributes in CC.2.5-3. Transaction UID, progress, and performed procedure
   sequences must be empty. The SCP supplies the SOP identifiers,
   modification time, and a default Worklist Label when empty.
2. Subscribe through Watch, with Deletion Lock TRUE when final information
   must remain available.
3. Use Pull N-ACTION 1 to change to IN PROGRESS, supplying a newly generated
   Transaction UID. Keep that UID: subsequent N-SET and state changes require
   it. A concurrent claimant receives C301.
4. N-SET performed information, using the complete replacement sequence.
   N-SET is atomic; invalid changes leave the stored document untouched.
   Attributes must have been created before they can be set. Patient,
   admission, and referenced-request identity cannot be rewritten.
5. Before requesting COMPLETED, fill the performed station, workitem,
   start and end times, and Output Information Sequence. An empty output
   sequence is valid when there are no output objects. For CANCELED,
   supply the discontinuation reason code in the Progress Information
   Sequence; the SCP fills a missing cancellation time in that same item.
6. Read the results with N-GET, then unsubscribe or subscribe without a
   deletion lock to release the lock.

Transaction UID is never returned by N-GET or C-FIND. Queries cannot match
it. UPS states, priorities, readiness, SOP Instance UIDs and code values use
Single Value Matching; sequence and date/time matching use
`DICOMQueryMatcher`.

A Request Cancel action on a SCHEDULED instance performs the intermediate
IN PROGRESS transition and then CANCELED. On an IN PROGRESS instance it
notifies the subscribers; the owner decides whether to cancel. The request
itself does not transfer ownership.

## Observe work items

Specific subscriptions override later global subscription instructions for
an existing instance. Global subscriptions add subscriptions to currently
unsubscribed matching instances and to new instances. Filtered global
subscriptions use the same matching rules as C-FIND. Global unsubscribe
removes all subscriptions and deletion locks for that AE. Suspend Global
Subscription removes the global subscription but preserves existing
instance subscriptions and locks. A new filtered or unfiltered global
subscription replaces the AE's previous global selection.

Events cover state/readiness (1), cancel requests (2), progress (3), SCP
restart/shutdown (4), and station/human assignment (5). Idempotent N-SETs do
not emit duplicate update events. Cancellation details in a state report
are projected from the nested Progress Information Sequence. Text events
carry the instance's Specific Character Set when present.

## Embed the service

`DICOMUnifiedProcedureStepService` accepts a `DICOMArchiveIndex`, an outgoing
`notify` callback and an incoming `receive` callback for Event reports.
Optional `receivingAEs` and `eventReportsSupported` parameters let a host
advertise its actual notification capabilities. `DICOMUPSNotifier` handles
Event associations to configured remote nodes.

Call `reportStatus(restarted: true, ...)` after restoring the index, and
`reportStatus(restarted: false, ...)` before orderly shutdown. Specify
whether the UPS and subscription lists survived, and provide fallback AE
titles. Recipients are deduplicated. `DcmServer` does this automatically,
with the configured notification destinations as its fallback list.

Use one owning service for subscription management in an index. Document
versions arbitrate UPS state/update conflicts across service instances;
the archive protocol does not provide a transaction spanning the global
subscription and all affected instance subscriptions.

## Retention and validation policy

The service retains final instances indefinitely, including after their
last deletion lock is released. It never automatically deletes an instance
or forcibly removes a deletion lock. The host must preserve this policy
when accessing the public archive index; direct index writes bypass UPS
validation and lock protection. DIMSE N-DELETE is not a UPS operation.

Validation covers data-expressed conditional requirements of the UPS code,
content, reference/access, issuer, performer, and output destination macros,
mandatory creation attributes, read-only updates, and final-state values.
The creating/performing application remains responsible for conditions
requiring external knowledge: whether subject identification is necessary,
whether a task will produce composite objects, whether an actual performer
is known, and whether a reference selects only some frames or segments.
Code scheme ambiguity and clinical suitability are not inferred.

Delivery failures are logged without changing subscriptions or locks.
Events are not queued or retried, as permitted by CC.2.4.3. Configure AE
routing and application authorization in the host.

## Reproduce qualification

```sh
swift test --filter DcmSwiftUPSTests
python3 Scripts/interop/ups.py 11112 11113
python3 Scripts/interop/ups_dcm4che.py /path/to/dcm4che/bin/upsscu 11112 11113
```

The first interop script requires pynetdicom/pydicom. The second uses
unmodified dcm4che command-line tools for both requests and Event reception.
Use a fresh server directory for each interop run. UPS-RS and WebSocket
notifications share this state machine; see <doc:UPSREST>.

Local qualification on 2026-10-21:

| Check | Result |
| --- | --- |
| macOS full SwiftPM suite | 400 tests passed |
| macOS release build | Passed |
| UPS tests, macOS | 16 passed |
| UPS tests, Linux aarch64 / Swift 6.2.4 | 16 passed |
| UPS tests, iOS 26.2 Simulator / iPhone 17 Pro | 16 passed |
| pynetdicom 3.0.4 / pydicom 3.0.2 | Create, get, query, claim, update, complete, unlock, and Event reports passed |
| dcm4che 5.35.2 | Create, duplicate, get, subscribe, claim, wrong-owner rejection, incomplete-final rejection, cancel request, update, final cancel, warning, unsubscribe, and Event types 1–3 passed |

These are local results; this tranche has not been submitted to CI.
