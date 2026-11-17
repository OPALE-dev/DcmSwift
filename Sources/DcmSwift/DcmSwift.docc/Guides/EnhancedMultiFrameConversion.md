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

## Representation profile

`DICOMEnhancedMultiFrameConversion.convert(_:to:)` accepts a complete scope of `DICOMRetrieveItem` values. The archive builds a transient read-only view from its complete catalogue before applying query keys. It does not persist converted bytes or change stored objects. This currently reads and converts the catalogue for each view request; there is no view cache. A conversion failure aborts the requested view, including when caused by an object outside the eventual query match.

Classic CT, MR and PET with compatible MONOCHROME2 pixel descriptions are grouped within their source series and invariant patient/study/frame-of-reference attributes. Source Instance Number followed by SOP Instance UID determines frame order. Native pixels or pixels decoded by an installed codec are preserved. Output uses the corresponding Legacy Converted Enhanced IOD because full enhanced acquisition semantics cannot generally be recovered from classic attributes. True and legacy enhanced CT/MR/PET can be split when the classic IOD can be populated from the functional groups and available source attributes.

Geometry, rescale, windows, acquisition timestamps with offsets, anatomy and applicable optional macros populate functional groups. PS3.16 Table L-1 body-part codes are generated from the pinned 2026d DocBook. Unassigned shared/per-frame attributes retain source information. Missing unconditional Type 2 attributes become explicitly empty; mandatory Type 1 clinical values are never fabricated. When a CT/PET source has no window, output includes a window spanning its full representable rescaled integer range, labelled `Full representable modality range`. A partially specified window fails. For derived images with no calculation technique, the extensible Defined Term is `UNKNOWN`.

Dependent objects retain their SOP Class and receive new instance/series UIDs. SOP/frame references and series references are remapped transitively, including cycles. A whole enhanced IMAGE/COMPOSITE SR reference expands into one content item per classic target. Conversion Source Attributes continue to identify the other view. Invalidated signatures and concatenation/offset metadata are removed. Every produced object passes the local PS3.3 IOD validator before any view is returned.

## Declared failures

The converter refuses overlays, curves or graphic annotations requiring a presentation conversion; encrypted attributes; incompatible pixel descriptions; missing unrecoverable mandatory metadata; and ambiguous coordinate or by-reference SR structures during frame splitting. It does not implement general GSPS synthesis or arbitrary storage SOP conversion. The failure is C000 and the source remains intact. Invalid or unnegotiated view identifiers return A900.

Annex Y extraction supports multi-frame Secondary Capture and true/legacy enhanced CT/MR/PET in the documented pixel profile. It copies independent encapsulated codestreams and selects functional groups; collection decoding requires unchanged Image Pixel attributes. Unsupported video or other dependent structures return the Annex Y extraction failure. This profile does not claim universal video or storage representation support.
