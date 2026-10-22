# Enhanced multi-frame Q/R views

The conversion contract follows DICOM 2026d PS3.4 C.3.5 and C.4, with PS3.3 modality-specific IODs. A view is a complete conversion result, not a per-request UID rewrite.

- Derive stable UIDs from a versioned SHA-256 namespace and source identities. Do not append suffixes to another producer's UID root. A restart must not change view identity.
- Convert compatible CT/MR/PET classic images to modality-specific legacy enhanced images; recover classic frames from supported true/legacy enhanced images. Preserve pixel samples and source attributes; populate functional groups and conversion provenance.
- Build the reference closure before filtering the query or retrieval. Convert dependent instances, new series identities and frame-qualified references together. Never silently omit presentations, SRs, other dependent objects or source attributes.
- Preserve Conversion Source Attributes references to the other view. Add Contributing Equipment with purpose 109106 and the prescribed contribution description. Keep patient, study and spatial/temporal frame of reference identities.
- Refuse the complete requested view if a source or reference representation cannot be converted without information loss or invalid structure. Missing acquisition information must not be filled with invented clinical values.
- Validate produced image IODs. Return the same view UIDs to FIND and subsequent GET/MOVE, including after restart. Without a negotiated Query/Retrieve View, preserve stored behavior.
- Frame extraction retains its Annex Y identity rule (same series, new instance), distinct from view conversion (new series and instance). Support enhanced functional groups and existing frame codecs; unsupported video codecs receive the defined extraction failure.

Qualification must cover bidirectional pixels/geometry, deterministic UIDs, full reference closure, nested SR/presentation references, all three frame selectors, negotiation and actual DIMSE operations. Closure of the milestone means these contracts are implemented and qualified in the declared representation scope; it does not claim every optional storage/video representation.
