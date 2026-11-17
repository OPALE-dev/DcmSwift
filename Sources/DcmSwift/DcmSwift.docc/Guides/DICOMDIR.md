# DICOMDIR

Read, write, and validate DICOMDIR files and their File-sets.

## Read a DICOMDIR

```swift
if let dicomDir = DicomDir(forPath: dicomDirPath) {
    print(dicomDir.index)                                 // every indexed file
    print(dicomDir.patients)                              // indexed patients
    print(dicomDir.index(forPatientID: "198726783"))      // files of one patient
}
```

The reader rejects dangling record pointers and resolves referenced files
relative to the DICOMDIR. A generic record view exposes every current 2026d
F.4-1 record type without discarding unknown or private attributes.
`directoryRecordTree` rebuilds the reachable typed hierarchy from the
serialized sibling and lower-level offsets, and returns nothing for malformed or
incomplete graphs.

## Write a DICOMDIR

``DicomDir`` keeps its legacy Basic Directory PATIENT, STUDY, SERIES, IMAGE
construction API. `directoryRecordRoots` also writes any current PS3.3 record
tree from typed ``DICOMDirectoryValue`` values, including nested Sequences. For
example, an RT Dose record can be added to the `children` of a Series record:

```swift
let dose = DICOMDirectoryRecordDefinition(
    type: .rtDose,
    elements: [
        "InstanceNumber": .string("1"),
        "DoseSummationType": .string("PLAN")
    ]
)
```

The writer calculates record offsets from the final Explicit VR Little Endian
layout, validates the hierarchy and required keys before writing, and rejects
invalid PS3.10 Referenced File IDs.

## Validate

| Method | Checks |
| --- | --- |
| `validateDirectoryStructure()` | Basic Directory container, File-set ID, pointer elements, consistency flag, cycles, root chain, orphan records; record types and parent-child relationships against PS3.3 Table F.4-1; a UID for PRIVATE records; retired record types, including HL7 STRUC DOC |
| `validateReferencedFiles()` | Unique and contained Referenced File IDs, existing targets, and matching SOP Class, SOP Instance, and Transfer Syntax UIDs |

Unknown, retired, and misplaced record types are diagnostics only: the
DICOMDIR still loads and `directoryRecordTree` keeps those records and their
children. Offset-graph errors still reject the file.

Record keys are validated as follows:

- Unconditional top-level Type 1 and Type 2 keys are represented for every
  current F.5 record type, including the Content Identification Macro and the
  top-level Scope of Inventory Sequence.
- Type 1C rules cover PRIVATE record UIDs, complete referenced-SOP identity
  tuples, Specific Character Set when a key uses an extended repertoire,
  non-empty present keys, verified SR documents, and Hanging Protocol
  Definition Items. File-set validation also checks Type 1C keys that depend on
  the referenced SOP Instance.
- Basic and Enhanced Coded Entry attributes are validated recursively: one
  code-value form, Code Meaning, Coding Scheme Designator when applicable,
  Context Group provenance, and private-extension provenance.
- SOP Instance Reference Items in Referenced Image, Instance, and Waveform
  Sequences require both referenced UIDs and non-empty Sequences.
- Scope of Inventory validates its zero-or-one Item constraint,
  extended-matching dependencies, and matching Sequence cardinalities.
- Optional Icon Image Keys are validated against PS3.3 F.7: one Item, mandatory
  Image Pixel attributes, monochrome or palette encodings, 1- or 8-bit unsigned
  samples, geometry and high-bit consistency, native Pixel Data length, and
  palette descriptors and data.

Synthetic round trips cover all 35 current F.4-1 record types with their
unconditional top-level Type 1 and Type 2 keys, including those of included
macros.

## File-set Descriptor

The optional non-DICOM File-set Descriptor is represented by
`fileSetDescriptorFileID` and `fileSetDescriptorCharacterSet`. Its File ID,
containment, and existence are validated; its content is not decoded yet.

## Scope

These checks do not claim conformance with a PS3.11 media storage application
profile or a PS3.12 media format. Deeper IOD and module conditions, per-type
writer qualification, other conditional and nested macro rules, and palette LUT
semantics are listed in <doc:DeferredLimitations>.
