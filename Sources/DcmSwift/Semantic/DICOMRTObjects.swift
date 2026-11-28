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

extension DICOMRTStructureSet.Contour {
    /// The area a CLOSED_PLANAR contour encloses, in mm², from the normal of
    /// its plane (Newell's method); nil for other geometric types or fewer
    /// than three points.
    public var area: Double? {
        guard geometricType == "CLOSED_PLANAR", points.count >= 3 else { return nil }
        let normal = Self.normal(points)
        return (normal.x * normal.x + normal.y * normal.y + normal.z * normal.z).squareRoot() / 2
    }

    /// Whether the contour lies in an axial plane: its normal along z.
    var isAxial: Bool {
        let n = Self.normal(points)
        let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
        return length > 0 && abs(n.z) / length > 0.999
    }

    /// Whether a point of the same axial plane is inside the contour (even-odd rule).
    func contains(x: Double, y: Double) -> Bool {
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func normal(_ points: [(x: Double, y: Double, z: Double)]) -> (x: Double, y: Double, z: Double) {
        var n = (x: 0.0, y: 0.0, z: 0.0)
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        }
        return n
    }
}

extension DICOMRTStructureSet.ROI {
    /// The number of points of all its contours.
    public var pointCount: Int { contours.reduce(0) { $0 + $1.points.count } }

    /// The smallest box holding its contours, in mm in the patient
    /// coordinate system; nil without points.
    public var bounds: (minimum: (x: Double, y: Double, z: Double), maximum: (x: Double, y: Double, z: Double))? {
        let all = contours.flatMap(\.points)
        guard let first = all.first else { return nil }
        var low = first, high = first
        for p in all {
            low = (min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = (max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        }
        return (low, high)
    }

    /// The positions of its axial contour planes along z, in mm, in order.
    public var planes: [Double] {
        Array(Set(contours.filter { $0.isAxial && !$0.points.isEmpty }.map { Self.plane($0.points[0].z) })).sorted()
    }

    /// The volume its CLOSED_PLANAR axial contours enclose, in cm³, as
    /// dicompyler-core computes it: each plane is as thick as the smallest
    /// gap between two planes, the first and last planes count for half, and
    /// a contour inside another of its plane is a hole; the planes are in
    /// the order of their positions. Nil when the ROI has
    /// no such contour, or contours that are not axial.
    public var volume: Double? {
        let closed = contours.filter { $0.geometricType == "CLOSED_PLANAR" && $0.points.count >= 3 }
        guard !closed.isEmpty, closed.allSatisfy(\.isAxial) else { return nil }
        let byPlane = Dictionary(grouping: closed) { Self.plane($0.points[0].z) }
        let positions = byPlane.keys.sorted()
        let thickness = zip(positions, positions.dropFirst()).map { $1 - $0 }.min() ?? 0
        var total = 0.0
        for (index, position) in positions.enumerated() {
            let shapes = byPlane[position]!.sorted { ($0.area ?? 0) > ($1.area ?? 0) }
            let weight = positions.count > 1 && (index == 0 || index == positions.count - 1) ? 0.5 : 1
            for (rank, shape) in shapes.enumerated() {
                let area = (shape.area ?? 0) * weight
                // A hole: inside the largest contour of its plane.
                let isHole = rank > 0 && shapes[0].contains(x: shape.points[0].x, y: shape.points[0].y)
                total += isHole ? -area : area
            }
        }
        return total * thickness / 1000
    }

    /// A plane position, rounded to a hundredth of a millimeter.
    private static func plane(_ z: Double) -> Double { (z * 100).rounded() / 100 }
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
