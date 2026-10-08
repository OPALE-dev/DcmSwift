import Foundation

/// Reading attributes of Items and data sets, for the RT objects.
private struct RTAttributes {
    let elements: [DataElement]

    init(_ elements: [DataElement]) { self.elements = elements }
    init(_ item: DataItem) { elements = item.elements }

    func element(_ name: String) -> DataElement? { elements.first { $0.name == name } }
    func text(_ name: String) -> String? {
        element(name)?.decodedTexts?.first.flatMap { $0.isEmpty ? nil : $0 }
    }
    func texts(_ name: String) -> [String] { element(name)?.decodedTexts ?? [] }
    func numbers(_ name: String) -> [Double] { element(name)?.decodedNumbers ?? [] }
    func number(_ name: String) -> Double? { numbers(name).first }
    func integer(_ name: String) -> Int? { number(name).map { Int($0) } }
    func items(_ name: String) -> [RTAttributes] { (element(name) as? DataSequence)?.items.map(RTAttributes.init) ?? [] }
    func code(_ name: String) -> DICOMCode? {
        (element(name) as? DataSequence)?.items.first.flatMap(DICOMCode.init(item:))
    }
}

/// An RT Structure Set (PS3.3 A.19): its ROIs and their contours.
public struct DICOMRTStructureSet: Sendable {
    public struct Contour: Sendable {
        /// Contour Geometric Type (3006,0042): POINT, OPEN_PLANAR,
        /// OPEN_NONPLANAR, or CLOSED_PLANAR.
        public let geometricType: String
        /// Contour Data (3006,0050), in millimeters in the patient
        /// coordinate system.
        public let points: [(x: Double, y: Double, z: Double)]
        /// The images the contour was drawn on.
        public let referencedSOPInstanceUIDs: [String]
    }

    public struct ROI: Sendable {
        /// ROI Number (3006,0022).
        public let number: Int
        public let name: String
        public let description: String?
        /// Referenced Frame of Reference UID (3006,0024).
        public let frameOfReferenceUID: String?
        /// ROI Generation Algorithm (3006,0036): AUTOMATIC, SEMIAUTOMATIC, MANUAL.
        public let generationAlgorithm: String?
        /// ROI Display Color (3006,002A), RGB.
        public let color: (red: Int, green: Int, blue: Int)?
        /// RT ROI Interpreted Type (3006,00A4), such as PTV or ORGAN.
        public let interpretedType: String?
        public let contours: [Contour]
    }

    /// Structure Set Label (3006,0002).
    public let label: String
    public let name: String?
    public let date: String?
    public let rois: [ROI]

    private static func contour(_ item: RTAttributes) -> Contour {
        let data = item.numbers("ContourData")
        var points: [(x: Double, y: Double, z: Double)] = []
        points.reserveCapacity(data.count / 3)
        var index = 0
        while index + 2 < data.count {
            points.append((x: data[index], y: data[index + 1], z: data[index + 2]))
            index += 3
        }
        let images: [String] = item.items("ContourImageSequence").compactMap { $0.text("ReferencedSOPInstanceUID") }
        return Contour(geometricType: item.text("ContourGeometricType") ?? "", points: points,
                       referencedSOPInstanceUIDs: images)
    }

    public init?(dataSet: DataSet) {
        let root = RTAttributes(dataSet.datasetElements)
        guard root.text("SOPClassUID") == "1.2.840.10008.5.1.4.1.1.481.3" else { return nil }
        label = root.text("StructureSetLabel") ?? ""
        name = root.text("StructureSetName")
        date = root.text("StructureSetDate")
        var contours: [Int: (color: (Int, Int, Int)?, contours: [Contour])] = [:]
        for item in root.items("ROIContourSequence") {
            guard let number = item.integer("ReferencedROINumber") else { continue }
            let rgb = item.numbers("ROIDisplayColor").map(Int.init)
            let shapes = item.items("ContourSequence").map(Self.contour)
            contours[number] = (rgb.count == 3 ? (rgb[0], rgb[1], rgb[2]) : nil, shapes)
        }
        var types: [Int: String] = [:]
        for observation in root.items("RTROIObservationsSequence") {
            if let number = observation.integer("ReferencedROINumber"), let type = observation.text("RTROIInterpretedType") {
                types[number] = type
            }
        }
        rois = root.items("StructureSetROISequence").compactMap { item in
            guard let number = item.integer("ROINumber") else { return nil }
            let color = contours[number]?.color.map { (red: $0.0, green: $0.1, blue: $0.2) }
            return ROI(number: number, name: item.text("ROIName") ?? "", description: item.text("ROIDescription"),
                       frameOfReferenceUID: item.text("ReferencedFrameOfReferenceUID"),
                       generationAlgorithm: item.text("ROIGenerationAlgorithm"), color: color,
                       interpretedType: types[number], contours: contours[number]?.contours ?? [])
        }
    }
}

/// An RT Dose (PS3.3 A.18): the dose grid, and its dose-volume histograms.
public struct DICOMRTDose: Sendable {
    public struct DVH: Sendable {
        /// Referenced ROI Number of the DVH Referenced ROI Sequence.
        public let roiNumbers: [Int]
        /// DVH Type (3004,0001): DIFFERENTIAL, CUMULATIVE, or NATURAL.
        public let type: String
        /// Dose Units (3004,0002): GY or RELATIVE.
        public let doseUnits: String
        /// DVH Volume Units (3004,0054): CM3, PERCENT, or PER_U.
        public let volumeUnits: String
        /// The bins: width in dose units (after DVH Dose Scaling), and volume.
        public let bins: [(width: Double, volume: Double)]
        public let minimumDose: Double?
        public let maximumDose: Double?
        public let meanDose: Double?
    }

    /// Dose Units (3004,0002): GY or RELATIVE.
    public let units: String
    /// Dose Type (3004,0004): PHYSICAL, EFFECTIVE, or ERROR.
    public let type: String
    /// Dose Summation Type (3004,000A), such as PLAN or BEAM.
    public let summationType: String
    public let rows: Int
    public let columns: Int
    public let frames: Int
    /// Dose Grid Scaling (3004,000E): the dose of one unit of a sample.
    public let gridScaling: Double
    public let imagePosition: [Double]
    public let imageOrientation: [Double]
    /// Pixel Spacing (0028,0030): row spacing, column spacing.
    public let pixelSpacing: [Double]
    /// Grid Frame Offset Vector (3004,000C): the offset of each frame.
    public let frameOffsets: [Double]
    public let dvhs: [DVH]
    private let dataSet: DataSet

    public init?(dataSet: DataSet) {
        let root = RTAttributes(dataSet.datasetElements)
        guard root.text("SOPClassUID") == "1.2.840.10008.5.1.4.1.1.481.2" else { return nil }
        self.dataSet = dataSet
        units = root.text("DoseUnits") ?? ""
        type = root.text("DoseType") ?? ""
        summationType = root.text("DoseSummationType") ?? ""
        rows = root.integer("Rows") ?? 0
        columns = root.integer("Columns") ?? 0
        frames = root.integer("NumberOfFrames") ?? (rows > 0 ? 1 : 0)
        gridScaling = root.number("DoseGridScaling") ?? 1
        imagePosition = root.numbers("ImagePositionPatient")
        imageOrientation = root.numbers("ImageOrientationPatient")
        pixelSpacing = root.numbers("PixelSpacing")
        frameOffsets = root.numbers("GridFrameOffsetVector")
        dvhs = root.items("DVHSequence").map { item in
            let scaling = item.number("DVHDoseScaling") ?? 1
            let data = item.numbers("DVHData")
            var bins: [(width: Double, volume: Double)] = []
            var index = 0
            while index + 1 < data.count {
                bins.append((width: data[index] * scaling, volume: data[index + 1]))
                index += 2
            }
            return DVH(roiNumbers: item.items("DVHReferencedROISequence").compactMap { $0.integer("ReferencedROINumber") },
                       type: item.text("DVHType") ?? "", doseUnits: item.text("DoseUnits") ?? "",
                       volumeUnits: item.text("DVHVolumeUnits") ?? "", bins: bins,
                       minimumDose: item.number("DVHMinimumDose"), maximumDose: item.number("DVHMaximumDose"),
                       meanDose: item.number("DVHMeanDose"))
        }
    }

    /// The dose of each voxel of a frame, row by row, in Dose Units: the
    /// stored values times Dose Grid Scaling.
    public func dose(frame: Int) throws -> [Double] {
        try DICOMImageRenderer(dataset: dataSet).storedValues(frame: frame).map { Double($0) * gridScaling }
    }

    /// The highest dose of the grid.
    public func maximumDose() throws -> Double {
        try (0..<frames).map { try dose(frame: $0).max() ?? 0 }.max() ?? 0
    }
}

/// An RT Plan (PS3.3 A.20): prescription, fractions, and beams.
public struct DICOMRTPlan: Sendable {
    public struct ControlPoint: Sendable {
        public let index: Int
        /// Cumulative Meterset Weight (300A,0134).
        public let cumulativeMetersetWeight: Double?
        public let gantryAngle: Double?
        public let collimatorAngle: Double?
        public let couchAngle: Double?
        /// Nominal Beam Energy (300A,0114), in MeV.
        public let nominalEnergy: Double?
        /// Isocenter Position (300A,012C), in millimeters.
        public let isocenter: [Double]
    }

    public struct Beam: Sendable {
        public let number: Int
        public let name: String?
        /// Beam Type (300A,00C4): STATIC or DYNAMIC.
        public let type: String?
        /// Radiation Type (300A,00C6), such as PHOTON or ELECTRON.
        public let radiationType: String?
        public let treatmentMachine: String?
        /// Final Cumulative Meterset Weight (300A,010E).
        public let finalCumulativeMetersetWeight: Double?
        public let controlPoints: [ControlPoint]
        /// Beam Meterset (300A,0086) of the first Fraction Group referencing it.
        public let meterset: Double?
    }

    public struct FractionGroup: Sendable {
        public let number: Int
        public let fractionsPlanned: Int?
        public let beamNumbers: [Int]
    }

    /// RT Plan Label (300A,0002).
    public let label: String
    public let name: String?
    public let date: String?
    /// RT Plan Geometry (300A,000C): PATIENT or TREATMENT_DEVICE.
    public let geometry: String?
    /// Target Prescription Dose (300A,0026) of the Dose Reference Sequence,
    /// in Gy, the highest when several are given.
    public let prescriptionDose: Double?
    public let fractionGroups: [FractionGroup]
    public let beams: [Beam]

    public init?(dataSet: DataSet) {
        let root = RTAttributes(dataSet.datasetElements)
        guard root.text("SOPClassUID") == "1.2.840.10008.5.1.4.1.1.481.5" else { return nil }
        label = root.text("RTPlanLabel") ?? ""
        name = root.text("RTPlanName")
        date = root.text("RTPlanDate")
        geometry = root.text("RTPlanGeometry")
        prescriptionDose = root.items("DoseReferenceSequence").compactMap { $0.number("TargetPrescriptionDose") }.max()
        var metersets: [Int: Double] = [:]
        fractionGroups = root.items("FractionGroupSequence").map { group in
            let references = group.items("ReferencedBeamSequence")
            for reference in references {
                if let beam = reference.integer("ReferencedBeamNumber"), metersets[beam] == nil {
                    metersets[beam] = reference.number("BeamMeterset")
                }
            }
            return FractionGroup(number: group.integer("FractionGroupNumber") ?? 0,
                                 fractionsPlanned: group.integer("NumberOfFractionsPlanned"),
                                 beamNumbers: references.compactMap { $0.integer("ReferencedBeamNumber") })
        }
        beams = root.items("BeamSequence").compactMap { beam in
            guard let number = beam.integer("BeamNumber") else { return nil }
            // Control points inherit unchanged values from the previous one.
            var gantry: Double?, collimator: Double?, couch: Double?, energy: Double?, isocenter: [Double] = []
            let points = beam.items("ControlPointSequence").enumerated().map { offset, point -> ControlPoint in
                gantry = point.number("GantryAngle") ?? gantry
                collimator = point.number("BeamLimitingDeviceAngle") ?? collimator
                couch = point.number("PatientSupportAngle") ?? couch
                energy = point.number("NominalBeamEnergy") ?? energy
                let position = point.numbers("IsocenterPosition")
                if !position.isEmpty { isocenter = position }
                return ControlPoint(index: point.integer("ControlPointIndex") ?? offset,
                                    cumulativeMetersetWeight: point.number("CumulativeMetersetWeight"),
                                    gantryAngle: gantry, collimatorAngle: collimator, couchAngle: couch,
                                    nominalEnergy: energy, isocenter: isocenter)
            }
            return Beam(number: number, name: beam.text("BeamName"), type: beam.text("BeamType"),
                        radiationType: beam.text("RadiationType"), treatmentMachine: beam.text("TreatmentMachineName"),
                        finalCumulativeMetersetWeight: beam.number("FinalCumulativeMetersetWeight"),
                        controlPoints: points, meterset: metersets[number])
        }
    }
}
