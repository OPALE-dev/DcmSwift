import Foundation

/// Relevant Patient Information Query (PS3.4 Q). Records are actual SR
/// content supplied by the application, not summaries inferred from images.
/// The application remains responsible for the selected PS3.16 template's
/// clinical content and constraints.
public struct DICOMRelevantPatientInformationService: DICOMQueryService {
    public struct Template: Hashable, Sendable {
        public var mappingResource: String
        public var identifier: String
        public init(mappingResource: String = "DCMR", identifier: String) {
            self.mappingResource = mappingResource; self.identifier = identifier
        }
    }
    public let supportedTemplates: Set<Template>
    private let records: [Data]
    static let models = [DICOMSOPClass.generalRelevantPatientInformationFind,
                         DICOMSOPClass.breastImagingRelevantPatientInformationFind,
                         DICOMSOPClass.cardiacRelevantPatientInformationFind]
    static let required = ["00100010", "00100020", "00100021", "00100030", "00100040",
                           "0040A032", "0040A040", "0040A043", "0040A504", "0040A730"]

    /// Snapshots response identifiers. Declaring templates separately permits
    /// a supported query to return no patients rather than C200.
    public init(records: [DataSet], supportedTemplates: Set<Template>) throws {
        self.supportedTemplates = supportedTemplates
        self.records = try records.map { record in
            let object = try DICOMJSON.object(record, options: .init(numbersAsStrings: true))
            guard let template = Self.template(object), supportedTemplates.contains(template),
                  Self.required.allSatisfy({ object[$0] != nil }),
                  ["00100010", "00100020", "0040A032", "0040A040", "0040A043"].allSatisfy({
                    !DICOMQueryMatcher.isUniversal(DICOMQueryMatcher.strings(object[$0] as? [String: Any] ?? [:])) || $0 == "0040A043"
                  }),
                  record.sequence(forTagName: "ConceptNameCodeSequence")?.items.count == 1,
                  record.sequence(forTagName: "ConceptNameCodeSequence")?.items.first.flatMap(DICOMCode.init(item:)) != nil,
                  record.string(forTag: "ValueType") == "CONTAINER",
                  record.textValues(forTag: "ObservationDateTime")?.first.flatMap(DICOMDateTimeValue.dateTime) != nil,
                  !Self.containsReference(object) else { throw DICOMCommandError("invalid Relevant Patient Information response identifier") }
            return try DICOMDataSetCoding.encode(record, transferSyntax: TransferSyntax.explicitVRLittleEndian)
        }
    }

    private static func containsReference(_ object: [String: Any]) -> Bool {
        if object["0040DB73"] != nil { return true }
        return object.values.contains { value in
            guard let attribute = value as? [String: Any], let items = attribute["Value"] as? [[String: Any]] else { return false }
            return items.contains(where: containsReference)
        }
    }

    /// Template declared by a patient information response or request.
    public static func template(in identifier: DataSet) throws -> Template? {
        template(try DICOMJSON.object(identifier, options: .init(numbersAsStrings: true)))
    }

    private static func template(_ object: [String: Any]) -> Template? {
        guard let items = (object["0040A504"] as? [String: Any])?["Value"] as? [[String: Any]], items.count == 1,
              let resource = DICOMQueryMatcher.strings(items[0]["00080105"] as? [String: Any] ?? [:]).first,
              let id = DICOMQueryMatcher.strings(items[0]["0040DB00"] as? [String: Any] ?? [:]).first,
              !resource.isEmpty, !id.isEmpty else { return nil }
        return Template(mappingResource: resource, identifier: id)
    }

    public func find(_ identifier: DataSet, informationModel: String, context: DICOMServiceContext) async throws -> AsyncThrowingStream<DataSet, Error> {
        func invalid(_ comment: String) -> DICOMServiceError { .init(status: .identifierDoesNotMatchSOPClass, comment: comment) }
        guard Self.models.contains(informationModel) else { throw invalid("unsupported Relevant Patient Information model") }
        let query = try DICOMJSON.object(identifier, options: .init(numbersAsStrings: true))
        guard let template = Self.template(query),
              let patient = identifier.string(forTag: "PatientID"), !patient.isEmpty,
              !patient.contains("\\"), !patient.contains("*"), !patient.contains("?"),
              identifier.element(forTagName: "IssuerOfPatientID") != nil else { throw invalid("Patient ID, issuer and template are required") }
        for (tag, attribute) in query where !["00100020", "00100021", "0040A504", "00080005"].contains(tag) {
            let value = attribute as? [String: Any] ?? [:]
            guard (value["Value"] as? [Any] ?? []).isEmpty, value["InlineBinary"] == nil, value["BulkDataURI"] == nil else {
                throw invalid("return attributes must have zero length")
            }
        }
        let restricted = informationModel == DICOMSOPClass.breastImagingRelevantPatientInformationFind ? "9000"
            : informationModel == DICOMSOPClass.cardiacRelevantPatientInformationFind ? "3802" : nil
        guard supportedTemplates.contains(template), restricted == nil || (template.mappingResource == "DCMR" && template.identifier == restricted) else {
            throw DICOMServiceError(status: DICOMStatus(code: 0xC200), comment: "unsupported patient information template")
        }
        let issuer = identifier.string(forTag: "IssuerOfPatientID") ?? ""
        guard !issuer.contains("\\"), !issuer.contains("*"), !issuer.contains("?") else { throw invalid("issuer requires Single Value Matching") }
        var matches: [DataSet] = []
        for bytes in records {
            let record = try DICOMDataSetCoding.decode(bytes, transferSyntax: TransferSyntax.explicitVRLittleEndian)
            let object = try DICOMJSON.object(record, options: .init(numbersAsStrings: true))
            guard record.string(forTag: "PatientID") == patient,
                  issuer.isEmpty || record.string(forTag: "IssuerOfPatientID") == issuer,
                  Self.template(object) == template else { continue }
            var response = object.filter { Self.required.contains($0.key) || query[$0.key] != nil || $0.key == "00080005" }
            for (tag, key) in query where response[tag] == nil {
                response[tag] = ["vr": (key as? [String: Any])?["vr"] as? String ?? "UN"]
            }
            matches.append(try DICOMJSON.dataSet(response))
            guard matches.count <= 1 else { throw DICOMServiceError(status: DICOMStatus(code: 0xC100), comment: "more than one matching patient record") }
        }
        return AsyncThrowingStream { continuation in
            for match in matches { continuation.yield(match) }
            continuation.finish()
        }
    }
}
