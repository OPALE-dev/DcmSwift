# Query/Retrieve extensions

Implement the optional Query/Retrieve behavior through accepted association negotiation, not through request flags alone (DICOM 2026d PS3.4 C.5; PS3.7 D.3.3.5).

## Contract

- Each SOP Class has its own Service Class Application Information. FIND uses seven bytes in 2026d, MOVE/GET use two, and Retrieve Without Bulk Data uses one. Missing optional bytes mean false. Replies grant only proposed and implemented behavior.
- Archive DIMSE requests validate their information model and hierarchy. Relational FIND permits constraints below the response level; relational retrieval removes the requirement for ancestor unique keys. DICOMweb retains its existing contract.
- Combined date/time matching compares the paired interval, including midnight crossings. Fuzzy PN matching uses a documented algorithm. Timezone adjustment compares query and stored offsets without modifying stored attributes.
- Composite Instance Root retrieval addresses instances directly by SOP Instance UID. FRAME requests must either create conforming derived instances with extraction provenance or return a defined failure; returning the original as an extracted instance is forbidden.
- Retrieve Without Bulk Data omits exactly the top-level attributes in PS3.4 Z.1.3 and Waveform Data inside Waveform Sequence; it preserves icon pixels, identifiers and other attributes. These incomplete objects are not suitable for ordinary archive storage.
- Relevant Patient Information Query is a separate provider of actual template-constrained SR content, not an image-derived clinical summary. Enforce exact patient identity, supported template, and at most one result (PS3.4 Q).
- Enhanced Multi-Frame Image Conversion, Empty Value Matching and Multiple Value Matching remain unadvertised until their full semantics are implemented. Query/Retrieve View is rejected when conversion has not been accepted.

## Evidence

Implementation and qualification results are recorded here as they become available. Normative source: local DICOM 2026d DocBook, PS3.4 Annexes C, Q, Y, Z and PS3.7 Annex D.
