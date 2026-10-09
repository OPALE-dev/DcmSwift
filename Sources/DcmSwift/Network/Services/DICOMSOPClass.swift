/// SOP classes of the DICOM services (PS3.4), from the 2026d edition.
public enum DICOMSOPClass {
    public static let verification = "1.2.840.10008.1.1"
    public static let storageCommitmentPushModel = "1.2.840.10008.1.20.1"

    /// Patient Root, Study Root, and Patient/Study Only (retired) Query/
    /// Retrieve information models (PS3.4 C.6), and Composite Instance Root
    /// retrieval (PS3.4 Annex Y).
    public static let patientRootFind = "1.2.840.10008.5.1.4.1.2.1.1"
    public static let patientRootMove = "1.2.840.10008.5.1.4.1.2.1.2"
    public static let patientRootGet = "1.2.840.10008.5.1.4.1.2.1.3"
    public static let studyRootFind = "1.2.840.10008.5.1.4.1.2.2.1"
    public static let studyRootMove = "1.2.840.10008.5.1.4.1.2.2.2"
    public static let studyRootGet = "1.2.840.10008.5.1.4.1.2.2.3"
    public static let patientStudyOnlyFind = "1.2.840.10008.5.1.4.1.2.3.1"
    public static let patientStudyOnlyMove = "1.2.840.10008.5.1.4.1.2.3.2"
    public static let patientStudyOnlyGet = "1.2.840.10008.5.1.4.1.2.3.3"
    public static let compositeInstanceRootGet = "1.2.840.10008.5.1.4.1.2.4.2"
    public static let compositeInstanceRootMove = "1.2.840.10008.5.1.4.1.2.4.3"
    public static let compositeInstanceRetrieveWithoutBulkDataGet = "1.2.840.10008.5.1.4.1.2.5.3"

    /// Modality Worklist Information Model - FIND (PS3.4 K.6).
    public static let modalityWorklistFind = "1.2.840.10008.5.1.4.31"
    /// Procedural Event Logging and Substance Administration Logging
    /// (PS3.4 P.2, P.3), with their well-known SOP Instances.
    public static let proceduralEventLogging = "1.2.840.10008.1.40"
    public static let proceduralEventLoggingInstance = "1.2.840.10008.1.40.1"
    public static let substanceAdministrationLogging = "1.2.840.10008.1.42"
    public static let substanceAdministrationLoggingInstance = "1.2.840.10008.1.42.1"
    /// Instance Availability Notification (PS3.4 R).
    public static let instanceAvailabilityNotification = "1.2.840.10008.5.1.4.33"
    /// Modality Performed Procedure Step (PS3.4 F.7), Retrieve (F.8), and
    /// Notification (F.9); all three share the SOP Instance UIDs.
    public static let modalityPerformedProcedureStep = "1.2.840.10008.3.1.2.3.3"
    public static let modalityPerformedProcedureStepRetrieve = "1.2.840.10008.3.1.2.3.4"
    public static let modalityPerformedProcedureStepNotification = "1.2.840.10008.3.1.2.3.5"

    /// Storage SOP classes of PS3.4 Table B.5-1.
    public static let storage: [String] = [
        "1.2.840.10008.5.1.4.1.1.1",  // Computed Radiography Image Storage
        "1.2.840.10008.5.1.4.1.1.1.1",  // Digital X-Ray Image Storage - For Presentation
        "1.2.840.10008.5.1.4.1.1.1.1.1",  // Digital X-Ray Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.1.2",  // Digital Mammography X-Ray Image Storage - For Presentation
        "1.2.840.10008.5.1.4.1.1.1.2.1",  // Digital Mammography X-Ray Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.1.3",  // Digital Intra-Oral X-Ray Image Storage - For Presentation
        "1.2.840.10008.5.1.4.1.1.1.3.1",  // Digital Intra-Oral X-Ray Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.2",  // CT Image Storage
        "1.2.840.10008.5.1.4.1.1.2.3",  // CT Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.2.1",  // Enhanced CT Image Storage
        "1.2.840.10008.5.1.4.1.1.2.4",  // Enhanced CT Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.2.2",  // Legacy Converted Enhanced CT Image Storage
        "1.2.840.10008.5.1.4.1.1.2.5",  // Legacy Converted Enhanced CT Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.3.1",  // Ultrasound Multi-frame Image Storage
        "1.2.840.10008.5.1.4.1.1.4",  // MR Image Storage
        "1.2.840.10008.5.1.4.1.1.4.1",  // Enhanced MR Image Storage
        "1.2.840.10008.5.1.4.1.1.4.2",  // MR Spectroscopy Storage
        "1.2.840.10008.5.1.4.1.1.4.3",  // Enhanced MR Color Image Storage
        "1.2.840.10008.5.1.4.1.1.4.4",  // Legacy Converted Enhanced MR Image Storage
        "1.2.840.10008.5.1.4.1.1.6.1",  // Ultrasound Image Storage
        "1.2.840.10008.5.1.4.1.1.6.2",  // Enhanced US Volume Storage
        "1.2.840.10008.5.1.4.1.1.6.3",  // Photoacoustic Image Storage
        "1.2.840.10008.5.1.4.1.1.7",  // Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.7.1",  // Multi-frame Single Bit Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.7.2",  // Multi-frame Grayscale Byte Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.7.3",  // Multi-frame Grayscale Word Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.7.4",  // Multi-frame True Color Secondary Capture Image Storage
        "1.2.840.10008.5.1.4.1.1.9.1.1",  // 12-lead ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.1.2",  // General ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.1.3",  // Ambulatory ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.1.4",  // General 32-bit ECG Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.2.1",  // Hemodynamic Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.3.1",  // Cardiac Electrophysiology Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.4.1",  // Basic Voice Audio Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.4.2",  // General Audio Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.5.1",  // Arterial Pulse Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.6.1",  // Respiratory Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.6.2",  // Multi-channel Respiratory Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.1",  // Routine Scalp Electroencephalogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.2",  // Electromyogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.3",  // Electrooculogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.7.4",  // Sleep Electroencephalogram Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.8.1",  // Body Position Waveform Storage
        "1.2.840.10008.5.1.4.1.1.9.100.1",  // Waveform Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.9.100.2",  // Waveform Acquisition Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.1",  // Grayscale Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.2",  // Color Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.3",  // Pseudo-Color Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.4",  // Blending Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.5",  // XA/XRF Grayscale Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.8",  // Advanced Blending Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.9",  // Volume Rendering Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.10",  // Segmented Volume Rendering Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.11",  // Multiple Volume Rendering Volumetric Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.11.12",  // Variable Modality LUT Softcopy Presentation State Storage
        "1.2.840.10008.5.1.4.1.1.12.1",  // X-Ray Angiographic Image Storage
        "1.2.840.10008.5.1.4.1.1.12.1.1",  // Enhanced XA Image Storage
        "1.2.840.10008.5.1.4.1.1.12.2",  // X-Ray Radiofluoroscopic Image Storage
        "1.2.840.10008.5.1.4.1.1.12.2.1",  // Enhanced XRF Image Storage
        "1.2.840.10008.5.1.4.1.1.13.1.1",  // X-Ray 3D Angiographic Image Storage
        "1.2.840.10008.5.1.4.1.1.13.1.2",  // X-Ray 3D Craniofacial Image Storage
        "1.2.840.10008.5.1.4.1.1.13.1.3",  // Breast Tomosynthesis Image Storage
        "1.2.840.10008.5.1.4.1.1.13.1.4",  // Breast Projection X-Ray Image Storage - For Presentation
        "1.2.840.10008.5.1.4.1.1.13.1.5",  // Breast Projection X-Ray Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.14.1",  // Intravascular Optical Coherence Tomography Image Storage - For Presentation
        "1.2.840.10008.5.1.4.1.1.14.2",  // Intravascular Optical Coherence Tomography Image Storage - For Processing
        "1.2.840.10008.5.1.4.1.1.20",  // Nuclear Medicine Image Storage
        "1.2.840.10008.5.1.4.1.1.30",  // Parametric Map Storage
        "1.2.840.10008.5.1.4.1.1.66",  // Raw Data Storage
        "1.2.840.10008.5.1.4.1.1.66.1",  // Spatial Registration Storage
        "1.2.840.10008.5.1.4.1.1.66.2",  // Spatial Fiducials Storage
        "1.2.840.10008.5.1.4.1.1.66.3",  // Deformable Spatial Registration Storage
        "1.2.840.10008.5.1.4.1.1.66.4",  // Segmentation Storage
        "1.2.840.10008.5.1.4.1.1.66.5",  // Surface Segmentation Storage
        "1.2.840.10008.5.1.4.1.1.66.6",  // Tractography Results Storage
        "1.2.840.10008.5.1.4.1.1.66.7",  // Label Map Segmentation Storage
        "1.2.840.10008.5.1.4.1.1.66.8",  // Height Map Segmentation Storage
        "1.2.840.10008.5.1.4.1.1.67",  // Real World Value Mapping Storage
        "1.2.840.10008.5.1.4.1.1.68.1",  // Surface Scan Mesh Storage
        "1.2.840.10008.5.1.4.1.1.68.2",  // Surface Scan Point Cloud Storage
        "1.2.840.10008.5.1.4.1.1.77.1.1",  // VL Endoscopic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.1.1",  // Video Endoscopic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.2",  // VL Microscopic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.2.1",  // Video Microscopic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.3",  // VL Slide-Coordinates Microscopic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.4",  // VL Photographic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.4.1",  // Video Photographic Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.1",  // Ophthalmic Photography 8 Bit Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.2",  // Ophthalmic Photography 16 Bit Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.3",  // Stereometric Relationship Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.4",  // Ophthalmic Tomography Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.5",  // Wide Field Ophthalmic Photography Stereographic Projection Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.6",  // Wide Field Ophthalmic Photography 3D Coordinates Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.7",  // Ophthalmic Optical Coherence Tomography En Face Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.5.8",  // Ophthalmic Optical Coherence Tomography B-scan Volume Analysis Storage
        "1.2.840.10008.5.1.4.1.1.77.1.6",  // VL Whole Slide Microscopy Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.7",  // Dermoscopic Photography Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.8",  // Confocal Microscopy Image Storage
        "1.2.840.10008.5.1.4.1.1.77.1.9",  // Confocal Microscopy Tiled Pyramidal Image Storage
        "1.2.840.10008.5.1.4.1.1.78.1",  // Lensometry Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.2",  // Autorefraction Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.3",  // Keratometry Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.4",  // Subjective Refraction Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.5",  // Visual Acuity Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.6",  // Spectacle Prescription Report Storage
        "1.2.840.10008.5.1.4.1.1.78.7",  // Ophthalmic Axial Measurements Storage
        "1.2.840.10008.5.1.4.1.1.78.8",  // Intraocular Lens Calculations Storage
        "1.2.840.10008.5.1.4.1.1.79.1",  // Macular Grid Thickness and Volume Report
        "1.2.840.10008.5.1.4.1.1.80.1",  // Ophthalmic Visual Field Static Perimetry Measurements Storage
        "1.2.840.10008.5.1.4.1.1.81.1",  // Ophthalmic Thickness Map Storage
        "1.2.840.10008.5.1.4.1.1.82.1",  // Corneal Topography Map Storage
        "1.2.840.10008.5.1.4.1.1.88.11",  // Basic Text SR Storage
        "1.2.840.10008.5.1.4.1.1.88.22",  // Enhanced SR Storage
        "1.2.840.10008.5.1.4.1.1.88.33",  // Comprehensive SR Storage
        "1.2.840.10008.5.1.4.1.1.88.34",  // Comprehensive 3D SR Storage
        "1.2.840.10008.5.1.4.1.1.88.35",  // Extensible SR Storage
        "1.2.840.10008.5.1.4.1.1.88.40",  // Procedure Log Storage
        "1.2.840.10008.5.1.4.1.1.88.50",  // Mammography CAD SR Storage
        "1.2.840.10008.5.1.4.1.1.88.59",  // Key Object Selection Document Storage
        "1.2.840.10008.5.1.4.1.1.88.65",  // Chest CAD SR Storage
        "1.2.840.10008.5.1.4.1.1.88.67",  // X-Ray Radiation Dose SR Storage
        "1.2.840.10008.5.1.4.1.1.88.68",  // Radiopharmaceutical Radiation Dose SR Storage
        "1.2.840.10008.5.1.4.1.1.88.69",  // Colon CAD SR Storage
        "1.2.840.10008.5.1.4.1.1.88.70",  // Implantation Plan SR Storage
        "1.2.840.10008.5.1.4.1.1.90.1",  // Content Assessment Results Storage
        "1.2.840.10008.5.1.4.1.1.91.1",  // Microscopy Bulk Simple Annotations Storage
        "1.2.840.10008.5.1.4.1.1.104.1",  // Encapsulated PDF Storage
        "1.2.840.10008.5.1.4.1.1.104.2",  // Encapsulated CDA Storage
        "1.2.840.10008.5.1.4.1.1.104.3",  // Encapsulated STL Storage
        "1.2.840.10008.5.1.4.1.1.104.4",  // Encapsulated OBJ Storage
        "1.2.840.10008.5.1.4.1.1.104.5",  // Encapsulated MTL Storage
        "1.2.840.10008.5.1.4.1.1.128",  // Positron Emission Tomography Image Storage
        "1.2.840.10008.5.1.4.1.1.130",  // Enhanced PET Image Storage
        "1.2.840.10008.5.1.4.1.1.128.1",  // Legacy Converted Enhanced PET Image Storage
        "1.2.840.10008.5.1.4.1.1.131",  // Basic Structured Display Storage
        "1.2.840.10008.5.1.4.1.1.200.2",  // CT Performed Procedure Protocol Storage
        "1.2.840.10008.5.1.4.1.1.200.8",  // XA Performed Procedure Protocol Storage
        "1.2.840.10008.5.1.4.1.1.481.1",  // RT Image Storage
        "1.2.840.10008.5.1.4.1.1.481.2",  // RT Dose Storage
        "1.2.840.10008.5.1.4.1.1.481.3",  // RT Structure Set Storage
        "1.2.840.10008.5.1.4.1.1.481.4",  // RT Beams Treatment Record Storage
        "1.2.840.10008.5.1.4.1.1.481.5",  // RT Plan Storage
        "1.2.840.10008.5.1.4.1.1.481.6",  // RT Brachy Treatment Record Storage
        "1.2.840.10008.5.1.4.1.1.481.7",  // RT Treatment Summary Record Storage
        "1.2.840.10008.5.1.4.1.1.481.8",  // RT Ion Plan Storage
        "1.2.840.10008.5.1.4.1.1.481.9",  // RT Ion Beams Treatment Record Storage
        "1.2.840.10008.5.1.4.1.1.481.10",  // RT Physician Intent Storage
        "1.2.840.10008.5.1.4.1.1.481.11",  // RT Segment Annotation Storage
        "1.2.840.10008.5.1.4.1.1.481.12",  // RT Radiation Set Storage
        "1.2.840.10008.5.1.4.1.1.481.13",  // C-Arm Photon-Electron Radiation Storage
        "1.2.840.10008.5.1.4.1.1.481.14",  // Tomotherapeutic Radiation Storage
        "1.2.840.10008.5.1.4.1.1.481.15",  // Robotic-Arm Radiation Storage
        "1.2.840.10008.5.1.4.1.1.481.16",  // RT Radiation Record Set Storage
        "1.2.840.10008.5.1.4.1.1.481.17",  // RT Radiation Salvage Record Storage
        "1.2.840.10008.5.1.4.1.1.481.18",  // Tomotherapeutic Radiation Record Storage
        "1.2.840.10008.5.1.4.1.1.481.19",  // C-Arm Photon-Electron Radiation Record Storage
        "1.2.840.10008.5.1.4.1.1.481.20",  // Robotic Radiation Record Storage
        "1.2.840.10008.5.1.4.1.1.481.21",  // RT Radiation Set Delivery Instruction Storage
        "1.2.840.10008.5.1.4.1.1.481.22",  // RT Treatment Preparation Storage
        "1.2.840.10008.5.1.4.1.1.481.23",  // Enhanced RT Image Storage
        "1.2.840.10008.5.1.4.1.1.481.24",  // Enhanced Continuous RT Image Storage
        "1.2.840.10008.5.1.4.1.1.481.25",  // RT Patient Position Acquisition Instruction Storage
        "1.2.840.10008.5.1.4.34.7",  // RT Beams Delivery Instruction Storage
        "1.2.840.10008.5.1.4.34.10",  // RT Brachy Application Setup Delivery Instruction Storage
    ]

    /// Retired storage SOP classes, still accepted so that old objects stay
    /// transferable.
    public static let retiredStorage: [String] = [
        "1.2.840.10008.5.1.1.27",  // Stored Print Storage SOP Class (Retired)
        "1.2.840.10008.5.1.1.29",  // Hardcopy Grayscale Image Storage SOP Class (Retired)
        "1.2.840.10008.5.1.1.30",  // Hardcopy Color Image Storage SOP Class (Retired)
        "1.2.840.10008.5.1.4.1.1.3",  // Ultrasound Multi-frame Image Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.5",  // Nuclear Medicine Image Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.6",  // Ultrasound Image Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.8",  // Standalone Overlay Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.9",  // Standalone Curve Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.9.1",  // Waveform Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.10",  // Standalone Modality LUT Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.11",  // Standalone VOI LUT Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.12.3",  // X-Ray Angiographic Bi-Plane Image Storage (Retired)
        "1.2.840.10008.5.1.4.1.1.77.1",  // VL Image Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.77.2",  // VL Multi-frame Image Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.88.1",  // Text SR Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.88.2",  // Audio SR Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.88.3",  // Detail SR Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.88.4",  // Comprehensive SR Storage - Trial (Retired)
        "1.2.840.10008.5.1.4.1.1.129",  // Standalone PET Curve Storage (Retired)
        "1.2.840.10008.5.1.4.34.1",  // RT Beams Delivery Instruction Storage - Trial (Retired)
    ]

    public static var allStorage: [String] { storage + retiredStorage }
}

/// Transfer syntaxes a storage SCP can accept and keep as received: every
/// syntax of the 2026d registry that encodes a data set, retired ones
/// included (the SMPTE ST 2110 stream syntaxes do not).
public enum DICOMTransferSyntaxes {
    public static let uncompressed = [
        TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian,
    ]

    public static let storage: [String] = [
        "1.2.840.10008.1.2.1",  // Explicit VR Little Endian
        "1.2.840.10008.1.2",  // Implicit VR Little Endian: Default Transfer Syntax for DICOM
        "1.2.840.10008.1.2.1.98",  // Encapsulated Uncompressed Explicit VR Little Endian
        "1.2.840.10008.1.2.1.99",  // Deflated Explicit VR Little Endian
        "1.2.840.10008.1.2.2",  // Explicit VR Big Endian (Retired)
        "1.2.840.10008.1.2.4.50",  // JPEG Baseline (Process 1): Default Transfer Syntax for Lossy JPEG 8 Bit Image Compression
        "1.2.840.10008.1.2.4.51",  // JPEG Extended (Process 2 & 4): Default Transfer Syntax for Lossy JPEG 12 Bit Image Compression (Process 4 only)
        "1.2.840.10008.1.2.4.52",  // JPEG Extended (Process 3 & 5) (Retired)
        "1.2.840.10008.1.2.4.53",  // JPEG Spectral Selection, Non-Hierarchical (Process 6 & 8) (Retired)
        "1.2.840.10008.1.2.4.54",  // JPEG Spectral Selection, Non-Hierarchical (Process 7 & 9) (Retired)
        "1.2.840.10008.1.2.4.55",  // JPEG Full Progression, Non-Hierarchical (Process 10 & 12) (Retired)
        "1.2.840.10008.1.2.4.56",  // JPEG Full Progression, Non-Hierarchical (Process 11 & 13) (Retired)
        "1.2.840.10008.1.2.4.57",  // JPEG Lossless, Non-Hierarchical (Process 14)
        "1.2.840.10008.1.2.4.58",  // JPEG Lossless, Non-Hierarchical (Process 15) (Retired)
        "1.2.840.10008.1.2.4.59",  // JPEG Extended, Hierarchical (Process 16 & 18) (Retired)
        "1.2.840.10008.1.2.4.60",  // JPEG Extended, Hierarchical (Process 17 & 19) (Retired)
        "1.2.840.10008.1.2.4.61",  // JPEG Spectral Selection, Hierarchical (Process 20 & 22) (Retired)
        "1.2.840.10008.1.2.4.62",  // JPEG Spectral Selection, Hierarchical (Process 21 & 23) (Retired)
        "1.2.840.10008.1.2.4.63",  // JPEG Full Progression, Hierarchical (Process 24 & 26) (Retired)
        "1.2.840.10008.1.2.4.64",  // JPEG Full Progression, Hierarchical (Process 25 & 27) (Retired)
        "1.2.840.10008.1.2.4.65",  // JPEG Lossless, Hierarchical (Process 28) (Retired)
        "1.2.840.10008.1.2.4.66",  // JPEG Lossless, Hierarchical (Process 29) (Retired)
        "1.2.840.10008.1.2.4.70",  // JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14 [Selection Value 1]): Default Transfer Syntax for Lossless JPEG Image Compression
        "1.2.840.10008.1.2.4.80",  // JPEG-LS Lossless Image Compression
        "1.2.840.10008.1.2.4.81",  // JPEG-LS Lossy (Near-Lossless) Image Compression
        "1.2.840.10008.1.2.4.90",  // JPEG 2000 Image Compression (Lossless Only)
        "1.2.840.10008.1.2.4.91",  // JPEG 2000 Image Compression
        "1.2.840.10008.1.2.4.92",  // JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only)
        "1.2.840.10008.1.2.4.93",  // JPEG 2000 Part 2 Multi-component Image Compression
        "1.2.840.10008.1.2.4.94",  // JPIP Referenced
        "1.2.840.10008.1.2.4.95",  // JPIP Referenced Deflate
        "1.2.840.10008.1.2.4.100",  // MPEG2 Main Profile / Main Level
        "1.2.840.10008.1.2.4.100.1",  // Fragmentable MPEG2 Main Profile / Main Level
        "1.2.840.10008.1.2.4.101",  // MPEG2 Main Profile / High Level
        "1.2.840.10008.1.2.4.101.1",  // Fragmentable MPEG2 Main Profile / High Level
        "1.2.840.10008.1.2.4.102",  // MPEG-4 AVC/H.264 High Profile / Level 4.1
        "1.2.840.10008.1.2.4.102.1",  // Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.1
        "1.2.840.10008.1.2.4.103",  // MPEG-4 AVC/H.264 BD-compatible High Profile / Level 4.1
        "1.2.840.10008.1.2.4.103.1",  // Fragmentable MPEG-4 AVC/H.264 BD-compatible High Profile / Level 4.1
        "1.2.840.10008.1.2.4.104",  // MPEG-4 AVC/H.264 High Profile / Level 4.2 For 2D Video
        "1.2.840.10008.1.2.4.104.1",  // Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.2 For 2D Video
        "1.2.840.10008.1.2.4.105",  // MPEG-4 AVC/H.264 High Profile / Level 4.2 For 3D Video
        "1.2.840.10008.1.2.4.105.1",  // Fragmentable MPEG-4 AVC/H.264 High Profile / Level 4.2 For 3D Video
        "1.2.840.10008.1.2.4.106",  // MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2
        "1.2.840.10008.1.2.4.106.1",  // Fragmentable MPEG-4 AVC/H.264 Stereo High Profile / Level 4.2
        "1.2.840.10008.1.2.4.107",  // HEVC/H.265 Main Profile / Level 5.1
        "1.2.840.10008.1.2.4.108",  // HEVC/H.265 Main 10 Profile / Level 5.1
        "1.2.840.10008.1.2.4.110",  // JPEG XL Lossless
        "1.2.840.10008.1.2.4.111",  // JPEG XL JPEG Recompression
        "1.2.840.10008.1.2.4.112",  // JPEG XL
        "1.2.840.10008.1.2.4.201",  // High-Throughput JPEG 2000 Image Compression (Lossless Only)
        "1.2.840.10008.1.2.4.202",  // High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)
        "1.2.840.10008.1.2.4.203",  // High-Throughput JPEG 2000 Image Compression
        "1.2.840.10008.1.2.4.204",  // JPIP HTJ2K Referenced
        "1.2.840.10008.1.2.4.205",  // JPIP HTJ2K Referenced Deflate
        "1.2.840.10008.1.2.5",  // RLE Lossless
        "1.2.840.10008.1.2.6.1",  // RFC 2557 MIME encapsulation (Retired)
        "1.2.840.10008.1.2.6.2",  // XML Encoding (Retired)
        "1.2.840.10008.1.2.8.1",  // Deflated Image Frame Compression
        "1.2.840.10008.1.20",  // Papyrus 3 Implicit VR Little Endian (Retired)
    ]
}
