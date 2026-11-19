import Foundation

/// A radiation dose report (PS3.16): CT (TID 10011), projection X-ray (TID
/// 10001), radiopharmaceutical (TID 10021) or patient radiation dose (TID
/// 10030). Reading keeps every numeric value with its concept and units, so
/// that a consumer can show totals and per-event values without knowing each
/// row of the templates; ``ct(device:studyInstanceUID:start:end:acquisitions:softwareVersions:intent:)`` makes a CT dose report.
public struct DICOMRadiationDoseReport: Sendable {
    public enum Kind: String, Sendable {
        case ct, projectionXRay, radiopharmaceutical, patient, other
    }

    /// A numeric value: concept, value, and UCUM units.
    public struct Value: Sendable, Equatable {
        public var concept: DICOMCode
        public var value: Double
        public var units: DICOMCode?

        public init(concept: DICOMCode, value: Double, units: DICOMCode?) {
            self.concept = concept
            self.value = value
            self.units = units
        }
    }

    /// An irradiation or administration event: a CT acquisition (TID 10013),
    /// an X-ray irradiation (TID 10003), or a radiopharmaceutical
    /// administration (TID 10022).
    public struct Event: Sendable, Equatable {
        /// The event container's concept, such as (113819, DCM, "CT Acquisition").
        public var concept: DICOMCode
        /// Irradiation Event UID (113769) or Radiopharmaceutical Administration Event UID (113503).
        public var uid: String?
        /// Acquisition Protocol (125203).
        public var protocolName: String?
        /// Target Region (123014).
        public var targetRegion: DICOMCode?
        /// CT Acquisition Type (113820) or Irradiation Event Type (113721).
        public var type: DICOMCode?
        /// DateTime Started (111526) or Radiopharmaceutical Start DateTime (123003).
        public var startedAt: String?
        /// The numeric values of the event and of its containers, depth first.
        public var values: [Value]
        /// The coded values of the event and of its containers.
        public var codes: [(concept: DICOMCode, value: DICOMCode)]

        public static func == (a: Event, b: Event) -> Bool {
            a.concept == b.concept && a.uid == b.uid && a.values == b.values
        }

        /// The first value of a concept, such as Mean CTDIvol.
        public func value(_ concept: DICOMCode) -> Value? { values.first { $0.concept.sameConcept(as: concept) } }
    }

    public var kind: Kind
    /// Root concept, such as (113701, DCM, "X-Ray Radiation Dose Report").
    public var title: DICOMCode
    public var procedure: DICOMCode?
    public var observers: [DICOMSRObserver]
    /// Study Instance UID of the Scope of Accumulation (113705), when a study.
    public var studyInstanceUID: String?
    /// Accumulated values (TID 10002, 10012) and the other values outside
    /// the events.
    public var accumulated: [Value]
    public var events: [Event]

    public enum Codes {
        static let dcm = DICOMSRCodes.dcm
        public static let xRayRadiationDoseReport = dcm("113701", "X-Ray Radiation Dose Report")
        public static let radiopharmaceuticalRadiationDoseReport = dcm("113500", "Radiopharmaceutical Radiation Dose Report")
        public static let patientRadiationDoseReport = dcm("128401", "Patient Radiation Dose Report")
        public static let projectionXRay = dcm("113704", "Projection X-Ray")
        public static let computedTomography = DICOMCode("77477000", scheme: "SCT", meaning: "Computed Tomography X-Ray")
        public static let scopeOfAccumulation = dcm("113705", "Scope of Accumulation")
        public static let study = dcm("113014", "Study")
        public static let studyInstanceUID = dcm("110180", "Study Instance UID")
        public static let deviceRoleInProcedure = dcm("113876", "Device Role in Procedure")
        public static let irradiatingDevice = dcm("113859", "Irradiating Device")
        public static let sourceOfDoseInformation = dcm("113854", "Source of Dose Information")
        public static let automatedDataCollection = dcm("113856", "Automated Data Collection")
        public static let startOfXRayIrradiation = dcm("113809", "Start of X-Ray Irradiation")
        public static let endOfXRayIrradiation = dcm("113810", "End of X-Ray Irradiation")
        public static let ctAccumulatedDoseData = dcm("113811", "CT Accumulated Dose Data")
        public static let totalNumberOfIrradiationEvents = dcm("113812", "Total Number of Irradiation Events")
        public static let ctDoseLengthProductTotal = dcm("113813", "CT Dose Length Product Total")
        public static let ctEffectiveDoseTotal = dcm("113814", "CT Effective Dose Total")
        public static let ctAcquisition = dcm("113819", "CT Acquisition")
        public static let ctAcquisitionType = dcm("113820", "CT Acquisition Type")
        public static let irradiationEventUID = dcm("113769", "Irradiation Event UID")
        public static let ctAcquisitionParameters = dcm("113822", "CT Acquisition Parameters")
        public static let exposureTime = dcm("113824", "Exposure Time")
        public static let scanningLength = dcm("113825", "Scanning Length")
        public static let nominalSingleCollimationWidth = dcm("113826", "Nominal Single Collimation Width")
        public static let nominalTotalCollimationWidth = dcm("113827", "Nominal Total Collimation Width")
        public static let pitchFactor = dcm("113828", "Pitch Factor")
        public static let numberOfXRaySources = dcm("113823", "Number of X-Ray Sources")
        public static let ctXRaySourceParameters = dcm("113831", "CT X-Ray Source Parameters")
        public static let identificationOfTheXRaySource = dcm("113832", "Identification of the X-Ray Source")
        public static let kvp = dcm("113733", "KVP")
        public static let maximumXRayTubeCurrent = dcm("113833", "Maximum X-Ray Tube Current")
        public static let xRayTubeCurrent = dcm("113734", "X-Ray Tube Current")
        public static let exposureTimePerRotation = dcm("113834", "Exposure Time per Rotation")
        public static let ctDose = dcm("113829", "CT Dose")
        public static let meanCTDIvol = dcm("113830", "Mean CTDIvol")
        public static let ctdiwPhantomType = dcm("113835", "CTDIw Phantom Type")
        public static let dlp = dcm("113838", "DLP")
        public static let effectiveDose = dcm("113839", "Effective Dose")
        public static let headPhantom = dcm("113690", "IEC 160mm Head CT Dosimetry Phantom")
        public static let bodyPhantom = dcm("113691", "IEC 320mm Body CT Dosimetry Phantom")
        public static let spiralAcquisition = DICOMCode("116152004", scheme: "SCT", meaning: "Spiral Acquisition")
        public static let sequencedAcquisition = dcm("113804", "Sequenced Acquisition")
        public static let acquisitionProtocol = dcm("125203", "Acquisition Protocol")
        public static let targetRegion = dcm("123014", "Target Region")
        public static let accumulatedXRayDoseData = dcm("113702", "Accumulated X-Ray Dose Data")
        public static let irradiationEventXRayData = dcm("113706", "Irradiation Event X-Ray Data")
        public static let irradiationEventType = dcm("113721", "Irradiation Event Type")
        public static let dateTimeStarted = dcm("111526", "DateTime Started")
        public static let doseAreaProductTotal = dcm("113722", "Dose Area Product Total")
        public static let doseRPTotal = dcm("113725", "Dose (RP) Total")
        public static let totalFluoroTime = dcm("113730", "Total Fluoro Time")
        public static let doseAreaProduct = dcm("122130", "Dose Area Product")
        public static let doseRP = dcm("113738", "Dose (RP)")
        public static let radiopharmaceuticalAdministration = dcm("113502", "Radiopharmaceutical Administration")
        public static let administrationEventUID = dcm("113503", "Radiopharmaceutical Administration Event UID")
        public static let administeredActivity = dcm("113507", "Administered activity")
        public static let radiopharmaceuticalStart = dcm("123003", "Radiopharmaceutical Start DateTime")
    }

    static func ucum(_ value: String, _ meaning: String) -> DICOMCode { DICOMCode(value, scheme: "UCUM", meaning: meaning) }

    // MARK: Reading

    /// Reads a dose report: a document declaring TID 10001, 10011, 10021 or
    /// 10030, or whose root is one of their titles.
    public init?(document: DICOMStructuredReport) {
        let root = document.root
        guard let title = root.conceptName else { return nil }
        let template = document.template?.identifier
        let procedure = root.code(of: DICOMSRCodes.procedureReported)
        switch template {
        case "10011": kind = .ct
        case "10001": kind = .projectionXRay
        case "10021": kind = .radiopharmaceutical
        case "10030": kind = .patient
        default:
            if title.sameConcept(as: Codes.radiopharmaceuticalRadiationDoseReport) { kind = .radiopharmaceutical }
            else if title.sameConcept(as: Codes.patientRadiationDoseReport) { kind = .patient }
            else if title.sameConcept(as: Codes.xRayRadiationDoseReport) {
                kind = root.children(named: Codes.ctAccumulatedDoseData).isEmpty && procedure?.sameConcept(as: Codes.computedTomography) != true
                    ? .projectionXRay : .ct
            } else { return nil }
        }
        self.title = title
        self.procedure = procedure
        observers = DICOMSRObserver.read(root)
        studyInstanceUID = root.children(named: Codes.scopeOfAccumulation).first.flatMap { scope in
            if case .uidReference(let uid)? = scope.children(named: Codes.studyInstanceUID).first?.value { return uid }
            return nil
        }
        let eventConcepts = [Codes.ctAcquisition, Codes.irradiationEventXRayData, Codes.radiopharmaceuticalAdministration]
        func isEvent(_ item: DICOMSRContentItem) -> Bool {
            guard case .container = item.value else { return false }
            if let concept = item.conceptName, eventConcepts.contains(where: concept.sameConcept(as:)) { return true }
            return !item.children(named: Codes.irradiationEventUID).isEmpty || !item.children(named: Codes.administrationEventUID).isEmpty
        }
        func values(_ item: DICOMSRContentItem) -> [Value] {
            item.flattened().compactMap { entry in
                guard let concept = entry.item.conceptName, case .number(let value?, let units, _) = entry.item.value else { return nil }
                return Value(concept: concept, value: value, units: units)
            }
        }
        var accumulated: [Value] = [], events: [Event] = []
        func walk(_ item: DICOMSRContentItem) {
            for child in item.children {
                if isEvent(child) {
                    events.append(Self.event(child, values: values(child)))
                } else if case .container = child.value {
                    walk(child)
                } else if let concept = child.conceptName, case .number(let value?, let units, _) = child.value {
                    accumulated.append(Value(concept: concept, value: value, units: units))
                }
            }
        }
        walk(root)
        self.accumulated = accumulated
        self.events = events
    }

    static func event(_ item: DICOMSRContentItem, values: [Value]) -> Event {
        func first(_ concepts: [DICOMCode]) -> DICOMSRContentItem.Value? {
            for concept in concepts { if let found = item.children(named: concept).first { return found.value } }
            return nil
        }
        var uid: String?, protocolName: String?, target: DICOMCode?, type: DICOMCode?, started: String?
        if case .uidReference(let value)? = first([Codes.irradiationEventUID, Codes.administrationEventUID]) { uid = value }
        if case .text(let value)? = first([Codes.acquisitionProtocol]) { protocolName = value }
        if case .code(let value)? = first([Codes.targetRegion]) { target = value }
        if case .code(let value)? = first([Codes.ctAcquisitionType, Codes.irradiationEventType]) { type = value }
        if case .dateTime(let value)? = first([Codes.dateTimeStarted, Codes.radiopharmaceuticalStart]) { started = value }
        let codes = item.flattened().dropFirst().compactMap { entry -> (concept: DICOMCode, value: DICOMCode)? in
            guard let concept = entry.item.conceptName, case .code(let value) = entry.item.value else { return nil }
            return (concept, value)
        }
        return Event(concept: item.conceptName ?? Codes.ctAcquisition, uid: uid, protocolName: protocolName, targetRegion: target,
                     type: type, startedAt: started, values: values, codes: codes)
    }

    /// The first accumulated value of a concept, such as CT Dose Length Product Total.
    public func accumulated(_ concept: DICOMCode) -> Value? { accumulated.first { $0.concept.sameConcept(as: concept) } }

    /// Total DLP of a CT report: the accumulated total, else the sum of the events' DLP (mGy.cm).
    public var ctDoseLengthProductTotal: Double? {
        if let total = accumulated(Codes.ctDoseLengthProductTotal) { return total.value }
        let dlp = events.compactMap { $0.value(Codes.dlp)?.value }
        return dlp.isEmpty ? nil : dlp.reduce(0, +)
    }

    // MARK: CT dose report

    /// A CT acquisition of a dose report (TID 10013).
    public struct CTAcquisition: Sendable {
        public var protocolName: String
        public var targetRegion: DICOMCode
        public var type: DICOMCode
        public var uid: String
        /// Mean CTDIvol (mGy) and DLP (mGy.cm) of the acquisition.
        public var ctdiVol: Double
        public var dlp: Double
        public var phantom: DICOMCode
        public var exposureTime: Double
        public var scanningLength: Double
        public var singleCollimationWidth: Double
        public var totalCollimationWidth: Double
        public var pitchFactor: Double?
        public var kvp: Double
        public var maximumTubeCurrent: Double
        public var tubeCurrent: Double
        public var exposureTimePerRotation: Double?

        public init(protocolName: String, targetRegion: DICOMCode, type: DICOMCode = Codes.spiralAcquisition, uid: String? = nil,
                    ctdiVol: Double, dlp: Double, phantom: DICOMCode = Codes.bodyPhantom, exposureTime: Double, scanningLength: Double,
                    singleCollimationWidth: Double, totalCollimationWidth: Double, pitchFactor: Double? = nil, kvp: Double,
                    maximumTubeCurrent: Double, tubeCurrent: Double, exposureTimePerRotation: Double? = nil) {
            self.protocolName = protocolName
            self.targetRegion = targetRegion
            self.type = type
            self.uid = uid ?? DICOMEncapsulatedDocument.newUID()
            self.ctdiVol = ctdiVol
            self.dlp = dlp
            self.phantom = phantom
            self.exposureTime = exposureTime
            self.scanningLength = scanningLength
            self.singleCollimationWidth = singleCollimationWidth
            self.totalCollimationWidth = totalCollimationWidth
            self.pitchFactor = pitchFactor
            self.kvp = kvp
            self.maximumTubeCurrent = maximumTubeCurrent
            self.tubeCurrent = tubeCurrent
            self.exposureTimePerRotation = exposureTimePerRotation
        }
    }

    /// A CT Radiation Dose report (TID 10011) of one study, made by an
    /// irradiating device, with its accumulated DLP and its acquisitions.
    /// The equipment module takes the device's manufacturer, model, and
    /// serial number, with `softwareVersions`.
    /// A CT Radiation Dose report (TID 10011) of one study. `intent` is the
    /// procedure intent (CID 3629), diagnostic by default.
    public static func ct(device: DICOMSRObserver, studyInstanceUID: String, start: String, end: String,
                          acquisitions: [CTAcquisition], softwareVersions: String? = nil,
                          intent: DICOMCode = DICOMCode("261004008", scheme: "SCT", meaning: "Diagnostic Intent")) -> DICOMStructuredReport {
        func num(_ concept: DICOMCode, _ value: Double, _ units: DICOMCode) -> DICOMSRContentItem {
            DICOMSRContentItem("CONTAINS", concept, .number(value, units: units, qualifier: nil))
        }
        let mGy = ucum("mGy", "mGy"), mGycm = ucum("mGy.cm", "mGy.cm"), s = ucum("s", "s"), mm = ucum("mm", "mm")
        let ratio = ucum("{ratio}", "ratio"), kV = ucum("kV", "kV"), mA = ucum("mA", "mA")
        var children = [DICOMSRContentItem("HAS CONCEPT MOD", DICOMSRCodes.procedureReported, .code(Codes.computedTomography), children: [
            DICOMSRContentItem("HAS CONCEPT MOD", DICOMCode("363703001", scheme: "SCT", meaning: "Has Intent"), .code(intent)),
        ])]
        children += device.items
        if case .device = device {
            children.append(DICOMSRContentItem("HAS OBS CONTEXT", Codes.deviceRoleInProcedure, .code(Codes.irradiatingDevice)))
        }
        children += [
            DICOMSRContentItem("HAS OBS CONTEXT", Codes.startOfXRayIrradiation, .dateTime(start)),
            DICOMSRContentItem("HAS OBS CONTEXT", Codes.endOfXRayIrradiation, .dateTime(end)),
            DICOMSRContentItem("HAS OBS CONTEXT", Codes.scopeOfAccumulation, .code(Codes.study), children: [
                DICOMSRContentItem("HAS PROPERTIES", Codes.studyInstanceUID, .uidReference(studyInstanceUID)),
            ]),
            DICOMSRContentItem("CONTAINS", Codes.ctAccumulatedDoseData, .container(continuity: "SEPARATE"), children: [
                num(Codes.totalNumberOfIrradiationEvents, Double(acquisitions.count), ucum("{events}", "events")),
                num(Codes.ctDoseLengthProductTotal, acquisitions.map(\.dlp).reduce(0, +), mGycm),
            ]),
        ]
        children += acquisitions.map { acquisition in
            var parameters = [
                num(Codes.exposureTime, acquisition.exposureTime, s),
                num(Codes.scanningLength, acquisition.scanningLength, mm),
                num(Codes.nominalSingleCollimationWidth, acquisition.singleCollimationWidth, mm),
                num(Codes.nominalTotalCollimationWidth, acquisition.totalCollimationWidth, mm),
            ]
            if let pitch = acquisition.pitchFactor { parameters.append(num(Codes.pitchFactor, pitch, ratio)) }
            parameters.append(num(Codes.numberOfXRaySources, 1, ucum("{X-Ray sources}", "X-Ray sources")))
            var source = [
                DICOMSRContentItem("CONTAINS", Codes.identificationOfTheXRaySource, .text("A")),
                num(Codes.kvp, acquisition.kvp, kV),
                num(Codes.maximumXRayTubeCurrent, acquisition.maximumTubeCurrent, mA),
                num(Codes.xRayTubeCurrent, acquisition.tubeCurrent, mA),
            ]
            if let rotation = acquisition.exposureTimePerRotation { source.append(num(Codes.exposureTimePerRotation, rotation, s)) }
            parameters.append(DICOMSRContentItem("CONTAINS", Codes.ctXRaySourceParameters, .container(continuity: "SEPARATE"), children: source))
            return DICOMSRContentItem("CONTAINS", Codes.ctAcquisition, .container(continuity: "SEPARATE"), children: [
                DICOMSRContentItem("CONTAINS", Codes.acquisitionProtocol, .text(acquisition.protocolName)),
                DICOMSRContentItem("CONTAINS", Codes.targetRegion, .code(acquisition.targetRegion)),
                DICOMSRContentItem("CONTAINS", Codes.ctAcquisitionType, .code(acquisition.type)),
                DICOMSRContentItem("CONTAINS", Codes.irradiationEventUID, .uidReference(acquisition.uid)),
                DICOMSRContentItem("CONTAINS", Codes.ctAcquisitionParameters, .container(continuity: "SEPARATE"), children: parameters),
                DICOMSRContentItem("CONTAINS", Codes.ctDose, .container(continuity: "SEPARATE"), children: [
                    num(Codes.meanCTDIvol, acquisition.ctdiVol, mGy),
                    DICOMSRContentItem("CONTAINS", Codes.ctdiwPhantomType, .code(acquisition.phantom)),
                    num(Codes.dlp, acquisition.dlp, mGycm),
                ]),
            ])
        }
        children.append(DICOMSRContentItem("CONTAINS", Codes.sourceOfDoseInformation, .code(Codes.automatedDataCollection)))
        var document = DICOMStructuredReport(sopClassUID: DICOMStructuredReport.xRayRadiationDose, completionFlag: "COMPLETE",
                                             verificationFlag: "UNVERIFIED", template: (mappingResource: "DCMR", identifier: "10011"),
                                             root: DICOMSRContentItem(nil, Codes.xRayRadiationDoseReport, .container(continuity: "SEPARATE"),
                                                                      children: children))
        if case .device(_, _, let manufacturer?, let model?, let serial?) = device, let softwareVersions {
            document.equipment = .init(manufacturer: manufacturer, modelName: model, serialNumber: serial, softwareVersions: softwareVersions)
        }
        return document
    }
}
