# Query/Retrieve extensions

Implement the optional Query/Retrieve behavior through accepted association negotiation, not through request flags alone (DICOM 2026d PS3.4 C.5; PS3.7 D.3.3.5).

## Contract

- Each SOP Class has its own Service Class Application Information. FIND uses seven bytes in 2026d, MOVE/GET use two; Composite Instance Root and Retrieve Without Bulk Data retain a reserved zero first byte followed by the conversion byte. Missing optional bytes mean false. Replies grant only proposed and implemented behavior.
- Archive DIMSE requests validate their information model and hierarchy. Relational FIND permits constraints below the response level; relational retrieval removes the requirement for ancestor unique keys. DICOMweb retains its existing contract.
- Combined date/time matching compares the paired interval, including midnight crossings. Fuzzy PN matching uses a documented algorithm. Timezone adjustment compares query and stored offsets without modifying stored attributes.
- Composite Instance Root retrieval addresses instances directly by SOP Instance UID. FRAME requests must either create conforming derived instances with extraction provenance or return a defined failure; returning the original as an extracted instance is forbidden.
- Retrieve Without Bulk Data omits exactly the top-level attributes in PS3.4 Z.1.3 and Waveform Data inside Waveform Sequence; it preserves icon pixels, identifiers and other attributes. These incomplete objects are not suitable for ordinary archive storage.
- Relevant Patient Information Query is a separate provider of actual template-constrained SR content, not an image-derived clinical summary. Enforce exact patient identity, supported template, and at most one result (PS3.4 Q).
- Enhanced Multi-Frame Image Conversion, Empty Value Matching and Multiple Value Matching remain unadvertised until their full semantics are implemented. Query/Retrieve View is rejected when conversion has not been accepted.

## Evidence

Implementation and qualification results are recorded here as they become available. Normative source: local DICOM 2026d DocBook, PS3.4 Annexes C, Q, Y, Z and PS3.7 Annex D.

## Querying an archive

`DICOMArchiveServices` offers relational queries/retrieval, combined Study Date/Time ranges, fuzzy PN matching and timezone adjustment. The server intersects these capabilities with the request for each SOP Class. Custom services default to baseline behavior and must declare the options they implement through `queryRetrieveOptions`.

```swift
let options: DICOMQueryRetrieveOptions = [.relational, .combinedDateTime, .fuzzyPersonNames, .timezoneAdjustment]
try await client.withAssociation(
    to: remote,
    presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootFind]),
    extendedNegotiations: [try options.negotiation(for: DICOMSOPClass.studyRootFind)]
) { association in
    for try await match in association.find(identifier) {
        // Consume one response entity.
    }
}
```

Baseline identifiers require ancestor unique keys and reject keys below the query level. Relational FIND permits descendant constraints. Counts and aggregate return keys describe the complete matched entity, even when a descendant constraint selected only one member. Relational retrieval still accepts only unique keys. Unsupported information models, malformed UIDs and an unaccepted Query/Retrieve View return A900.

Fuzzy PN matching folds case and accents, ignores punctuation and component order, and matches each query token to a distinct stored token. Wildcards are supported; there is no phonetic, synonym or language-specific equivalence. Baseline archive PN matching preserves accents and ignores case. Combined matching supports the indexed Study Date/Study Time pair. Timezone adjustment uses query and stored offsets; absent offsets use UTC. Explicit DT offsets take precedence. Neither operation rewrites stored attributes. Other services retain their existing matcher defaults.

Index adapters receive compatible candidate predicates. Complete entities are fetched for counts and return keys. Fuzzy and timezone predicates that cannot be expressed safely are left to the core matcher. This can broaden the candidate set for large archives; it does not require a file scan.

`commonExtendedNegotiations` can also be proposed by the client. The association and service context expose the requestor's SOP/service-class mapping to the host. As required by PS3.7 D.3.3.6, there is no AC response for this item. The mapping does not itself grant support for an unknown specialized SOP Class; the host must configure that abstract syntax explicitly.

## Retrieving instances and frames

Use `compositeInstanceRootGet` or `compositeInstanceRootMove` with Query/Retrieve Level `IMAGE` and one or more SOP Instance UIDs. No Study or Series UID is required. The corrected UIDs are `.4.3` for GET and `.4.2` for MOVE; earlier public constants had these reversed.

For `FRAME`, supply exactly one SOP Instance UID and exactly one of Simple Frame List, Calculated Frame List or Time Range. Frame numbers are one-based and increasing. The native extractor supports multi-frame Secondary Capture single-bit, unsigned grayscale byte/word, and RGB byte images, with Frame Time or Frame Time Vector. It packs selected bits, normalizes Big Endian samples, preserves patient/study/series identity, creates a new instance UID, adjusts timing, appends Frame Extraction and Contributing Equipment provenance, and removes private attributes. Repeated extractions append provenance rather than replacing its history.

Enhanced CT/MR/PET, compressed/video frames, per-frame functional groups, overlays, curves and other unsupported frame-dependent structures are refused rather than copied inconsistently. AA00 means no selected frames, AA01 an unsupported SOP Class, AA02 an unsupported/invalid extraction representation, AA03 missing temporal information, and AA04 an invalid frame selector. This is a declared subset of Annex Y extraction, not a claim to extract every storage SOP Class.

For `compositeInstanceRetrieveWithoutBulkDataGet`, use `IMAGE` and the SOP Instance UID list. Top-level Pixel Data (including float/double), Pixel Data Provider URL, Spectroscopy Data, repeating overlay/curve/audio data and Encapsulated Document are removed. Waveform samples are removed inside Waveform Sequence. Icon Image pixels, private attributes, waveform descriptors, other attributes and all identifiers are preserved. The source object remains unchanged. The receiving application must handle this deliberately incomplete object without treating it as a complete stored image.

## Relevant Patient Information

Supply actual response identifiers to `DICOMRelevantPatientInformationService`, with the supported Mapping Resource/Template Identifier pairs. The service snapshots the data, checks mandatory return attributes, root concept and container, observation datetime, and absence of by-reference relationships. The application must qualify the full PS3.16 template and clinical content; this service does not generate or clinically validate patient summaries.

Pass the service as `relevantPatientInformation:` to `DICOMServer`. General, Breast Imaging and Cardiac Relevant Patient Information FIND are separate SOP Classes; the specialized classes require DCMR TID 9000 and 3802 respectively. Unsupported templates return C200, multiple matches C100, and invalid identifiers A900. Only Patient ID, optional issuer value and the required Content Template Sequence constrain matching; requested return attributes must be zero length.

```sh
DcmServer --aet QRSCP --patient-information-directory ./patient-information
```

The directory accepts DICOM JSON, Part 10 or bare data sets. It is loaded at startup; the templates declared by its records form the supported set. The API also permits declaring supported templates for which no patient record currently exists. This service works with or without `--storage-directory`.

## Qualification and remaining work

`DcmSwiftQueryRetrieveExtensionTests` covers negotiation, hierarchy rules, matching, bulk omission, frame selection and representation, patient responses and real DIMSE loopback. `Scripts/interop/query_retrieve.py` starts an isolated `DcmServer` and an independent pynetdicom C-MOVE receiver; it checks FIND, GET, MOVE, frame provenance/pixels, UTF-8 patient content and failure statuses.

Enhanced Multi-Frame Image Conversion remains unimplemented and unadvertised. Full classic/enhanced view conversion requires coherent derived instances and reference remapping across the retrieved objects (PS3.4 C.3.5); negotiating a flag alone does not provide that behavior. Empty Value Matching and Multiple Value Matching are also declined. External archive, video extraction and clinical template qualification remain outside the evidence above.
