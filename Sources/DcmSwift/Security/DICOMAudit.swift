import Foundation

/// A coded value of an audit message: csd-code, codeSystemName, and
/// originalText, which is the DICOM Code Meaning (PS3.15 A.5.1).
public struct DICOMAuditCode: Hashable, Sendable {
    public var code: String
    public var codeSystemName: String
    public var originalText: String
    public var displayName: String?

    public init(_ code: String, codeSystemName: String, originalText: String, displayName: String? = nil) {
        self.code = code
        self.codeSystemName = codeSystemName
        self.originalText = originalText
        self.displayName = displayName
    }

    /// A DCM code, with its meaning from PS3.16 Annex D.
    public static func dcm(_ value: String) -> DICOMAuditCode {
        DICOMAuditCode(value, codeSystemName: "DCM",
                       originalText: DICOMTerminology.shared.dicomCode(value)?.meaning ?? value)
    }

    /// A code of RFC 3881, which DICOM keeps for some fields.
    public static func rfc3881(_ value: String, _ meaning: String) -> DICOMAuditCode {
        DICOMAuditCode(value, codeSystemName: "RFC-3881", originalText: meaning)
    }

    // Participant Object ID Type Codes (PS3.15 A.5.2.5).
    public static let patientNumber = rfc3881("2", "Patient Number")
    public static let uri = rfc3881("12", "URI")
    public static var studyInstanceUID: DICOMAuditCode { dcm("110180") }
    public static var sopClassUID: DICOMAuditCode { dcm("110181") }
    public static var nodeID: DICOMAuditCode { dcm("110182") }
}

/// An audit message of the Audit Trail Message Format Profile (PS3.15 A.5),
/// encoded as the XML of the DICOM Audit Message Schema (A.5.1).
public struct DICOMAuditMessage: Sendable {
    /// EventOutcomeIndicator.
    public enum Outcome: Int, Sendable {
        case success = 0
        case minorFailure = 4
        case seriousFailure = 8
        case majorFailure = 12
    }

    /// EventActionCode.
    public enum Action: String, Sendable {
        case create = "C", read = "R", update = "U", delete = "D", execute = "E"
    }

    /// NetworkAccessPointTypeCode.
    public enum NetworkAccessPointType: String, Sendable {
        case machineName = "1", ipAddress = "2", telephoneNumber = "3", emailAddress = "4", uri = "5"
    }

    public struct ActiveParticipant: Sendable {
        public var userID: String
        public var alternativeUserID: String?
        public var userName: String?
        public var isRequestor: Bool
        public var roles: [DICOMAuditCode]
        public var networkAccessPointID: String?
        public var networkAccessPointType: NetworkAccessPointType?
        /// MediaType of MediaIdentifier, for media participants.
        public var mediaType: DICOMAuditCode?

        public init(userID: String, alternativeUserID: String? = nil, userName: String? = nil,
                    isRequestor: Bool, roles: [DICOMAuditCode] = [], networkAccessPointID: String? = nil,
                    networkAccessPointType: NetworkAccessPointType? = nil, mediaType: DICOMAuditCode? = nil) {
            self.userID = userID
            self.alternativeUserID = alternativeUserID
            self.userName = userName
            self.isRequestor = isRequestor
            self.roles = roles
            self.networkAccessPointID = networkAccessPointID
            self.networkAccessPointType = networkAccessPointType
            self.mediaType = mediaType
        }

        /// A DICOM application: its process as UserID and its AE titles as
        /// AlternativeUserID, "AETITLES=A;B" (A.5.2.1).
        public static func application(
            aeTitles: [String], isRequestor: Bool, roles: [DICOMAuditCode] = [], host: String? = nil,
            process: String = "\(ProcessInfo.processInfo.processName)[\(ProcessInfo.processInfo.processIdentifier)]"
        ) -> ActiveParticipant {
            ActiveParticipant(
                userID: process, alternativeUserID: aeTitles.isEmpty ? nil : "AETITLES=" + aeTitles.joined(separator: ";"),
                userName: ProcessInfo.processInfo.processName, isRequestor: isRequestor, roles: roles,
                networkAccessPointID: host, networkAccessPointType: host.map(NetworkAccessPointType.of))
        }

        /// A remote DICOM node, by its AE title and address.
        public static func node(aeTitle: String, host: String?, isRequestor: Bool,
                                roles: [DICOMAuditCode] = []) -> ActiveParticipant {
            ActiveParticipant(
                userID: aeTitle.isEmpty ? (host ?? "unknown") : aeTitle,
                alternativeUserID: aeTitle.isEmpty ? nil : "AETITLES=\(aeTitle)", isRequestor: isRequestor,
                roles: roles, networkAccessPointID: host, networkAccessPointType: host.map(NetworkAccessPointType.of))
        }
    }

    /// ParticipantObjectDescription for DICOM objects (A.5.2.4).
    public struct ObjectDescription: Sendable {
        public struct SOPClass: Sendable {
            public var uid: String
            public var numberOfInstances: Int
            /// Instance UIDs; usually left empty, as messages grow large.
            public var instances: [String]

            public init(uid: String, numberOfInstances: Int, instances: [String] = []) {
                self.uid = uid
                self.numberOfInstances = numberOfInstances
                self.instances = instances
            }
        }

        public var mpps: [String] = []
        public var accessions: [String] = []
        public var sopClasses: [SOPClass] = []
        public var containedStudies: [String] = []
        public var encrypted: Bool?
        public var anonymized: Bool?

        public init(mpps: [String] = [], accessions: [String] = [], sopClasses: [SOPClass] = [],
                    containedStudies: [String] = [], encrypted: Bool? = nil, anonymized: Bool? = nil) {
            self.mpps = mpps
            self.accessions = accessions
            self.sopClasses = sopClasses
            self.containedStudies = containedStudies
            self.encrypted = encrypted
            self.anonymized = anonymized
        }
    }

    public struct ParticipantObject: Sendable {
        public var idType: DICOMAuditCode
        public var id: String
        /// ParticipantObjectName, required without a query.
        public var name: String?
        /// ParticipantObjectQuery, required without a name.
        public var query: Data?
        /// ParticipantObjectDetail type-value pairs.
        public var details: [(type: String, value: Data)]
        public var descriptions: [ObjectDescription]
        public var typeCode: String?
        public var typeCodeRole: String?
        public var dataLifeCycle: String?
        public var sensitivity: String?

        public init(idType: DICOMAuditCode, id: String, name: String? = nil, query: Data? = nil,
                    details: [(type: String, value: Data)] = [], descriptions: [ObjectDescription] = [],
                    typeCode: String? = nil, typeCodeRole: String? = nil, dataLifeCycle: String? = nil,
                    sensitivity: String? = nil) {
            self.idType = idType
            self.id = id
            self.name = name
            self.query = query
            self.details = details
            self.descriptions = descriptions
            self.typeCode = typeCode
            self.typeCodeRole = typeCodeRole
            self.dataLifeCycle = dataLifeCycle
            self.sensitivity = sensitivity
        }

        /// A patient: type 1 Person, role 1 Patient, ID type Patient Number.
        public static func patient(id: String, name: String) -> ParticipantObject {
            ParticipantObject(idType: .patientNumber, id: id, name: name, typeCode: "1", typeCodeRole: "1")
        }

        /// A study: type 2 System Object, role 3 Report, with its SOP
        /// Classes and the number of their instances.
        public static func study(uid: String, sopClasses: [ObjectDescription.SOPClass] = [],
                                 accessions: [String] = []) -> ParticipantObject {
            let description = sopClasses.isEmpty && accessions.isEmpty
                ? [] : [ObjectDescription(accessions: accessions, sopClasses: sopClasses)]
            return ParticipantObject(idType: .studyInstanceUID, id: uid, name: uid, descriptions: description,
                                     typeCode: "2", typeCodeRole: "3")
        }
    }

    public var eventID: DICOMAuditCode
    public var action: Action?
    public var dateTime: Date
    public var outcome: Outcome
    public var outcomeDescription: String?
    public var eventTypes: [DICOMAuditCode]
    public var participants: [ActiveParticipant]
    /// AuditSourceID, the system reporting the event.
    public var sourceID: String
    public var enterpriseSiteID: String?
    /// AuditSourceTypeCode values, such as "4" for an application server.
    public var sourceTypes: [String]
    public var objects: [ParticipantObject]

    public init(eventID: DICOMAuditCode, action: Action?, dateTime: Date = Date(), outcome: Outcome = .success,
                outcomeDescription: String? = nil, eventTypes: [DICOMAuditCode] = [],
                participants: [ActiveParticipant], source: DICOMAuditSource, objects: [ParticipantObject] = []) {
        self.eventID = eventID
        self.action = action
        self.dateTime = dateTime
        self.outcome = outcome
        self.outcomeDescription = outcomeDescription
        self.eventTypes = eventTypes
        self.participants = participants
        sourceID = source.id
        enterpriseSiteID = source.enterpriseSiteID
        sourceTypes = source.types
        self.objects = objects
    }

    // MARK: XML (PS3.15 A.5.1)

    /// The message as UTF-8 XML. Empty values are left out, as A.5.2
    /// forbids empty elements and attributes.
    public func xml() -> Data {
        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"#
        xml += "<AuditMessage>"
        xml += "<EventIdentification"
        xml += attribute("EventActionCode", action?.rawValue)
        xml += attribute("EventDateTime", Self.dateTimeString(dateTime))
        xml += attribute("EventOutcomeIndicator", String(outcome.rawValue)) + ">"
        xml += coded("EventID", eventID)
        for type in eventTypes { xml += coded("EventTypeCode", type) }
        if let description = nonEmpty(outcomeDescription) {
            xml += "<EventOutcomeDescription>\(Self.escape(description))</EventOutcomeDescription>"
        }
        xml += "</EventIdentification>"
        for participant in participants {
            xml += "<ActiveParticipant"
            xml += attribute("UserID", participant.userID)
            xml += attribute("AlternativeUserID", participant.alternativeUserID)
            xml += attribute("UserName", participant.userName)
            xml += attribute("UserIsRequestor", participant.isRequestor ? "true" : "false")
            xml += attribute("NetworkAccessPointID", participant.networkAccessPointID)
            xml += attribute("NetworkAccessPointTypeCode",
                             participant.networkAccessPointID == nil ? nil : participant.networkAccessPointType?.rawValue)
            xml += ">"
            for role in participant.roles { xml += coded("RoleIDCode", role) }
            if let media = participant.mediaType {
                xml += "<MediaIdentifier>" + coded("MediaType", media) + "</MediaIdentifier>"
            }
            xml += "</ActiveParticipant>"
        }
        xml += "<AuditSourceIdentification"
        xml += attribute("AuditEnterpriseSiteID", enterpriseSiteID)
        xml += attribute("AuditSourceID", sourceID) + ">"
        for type in sourceTypes { xml += "<AuditSourceTypeCode" + attribute("csd-code", type) + "/>" }
        xml += "</AuditSourceIdentification>"
        for object in objects {
            xml += "<ParticipantObjectIdentification"
            xml += attribute("ParticipantObjectID", object.id)
            xml += attribute("ParticipantObjectTypeCode", object.typeCode)
            xml += attribute("ParticipantObjectTypeCodeRole", object.typeCodeRole)
            xml += attribute("ParticipantObjectDataLifeCycle", object.dataLifeCycle)
            xml += attribute("ParticipantObjectSensitivity", object.sensitivity) + ">"
            xml += coded("ParticipantObjectIDTypeCode", object.idType)
            if let query = object.query, !query.isEmpty {
                xml += "<ParticipantObjectQuery>\(query.base64EncodedString())</ParticipantObjectQuery>"
            } else {
                xml += "<ParticipantObjectName>\(Self.escape(nonEmpty(object.name) ?? object.id))</ParticipantObjectName>"
            }
            for detail in object.details where !detail.type.isEmpty && !detail.value.isEmpty {
                xml += "<ParticipantObjectDetail" + attribute("type", detail.type)
                    + attribute("value", detail.value.base64EncodedString()) + "/>"
            }
            for description in object.descriptions { xml += self.description(description) }
            xml += "</ParticipantObjectIdentification>"
        }
        xml += "</AuditMessage>"
        return Data(xml.utf8)
    }

    private func description(_ description: ObjectDescription) -> String {
        var xml = "<ParticipantObjectDescription>"
        for uid in description.mpps where !uid.isEmpty { xml += "<MPPS" + attribute("UID", uid) + "/>" }
        for number in description.accessions where !number.isEmpty { xml += "<Accession" + attribute("Number", number) + "/>" }
        for sopClass in description.sopClasses {
            xml += "<SOPClass" + attribute("UID", sopClass.uid)
                + attribute("NumberOfInstances", String(sopClass.numberOfInstances)) + ">"
            for uid in sopClass.instances where !uid.isEmpty { xml += "<Instance" + attribute("UID", uid) + "/>" }
            xml += "</SOPClass>"
        }
        if !description.containedStudies.isEmpty {
            xml += "<ParticipantObjectContainsStudy>"
            for uid in description.containedStudies where !uid.isEmpty { xml += "<StudyIDs" + attribute("UID", uid) + "/>" }
            xml += "</ParticipantObjectContainsStudy>"
        }
        if let encrypted = description.encrypted { xml += "<Encrypted>\(encrypted)</Encrypted>" }
        if let anonymized = description.anonymized { xml += "<Anonymized>\(anonymized)</Anonymized>" }
        return xml + "</ParticipantObjectDescription>"
    }

    private func coded(_ name: String, _ code: DICOMAuditCode) -> String {
        "<\(name)" + attribute("csd-code", code.code) + attribute("codeSystemName", code.codeSystemName)
            + attribute("displayName", code.displayName) + attribute("originalText", code.originalText) + "/>"
    }

    private func attribute(_ name: String, _ value: String?) -> String {
        guard let value = nonEmpty(value) else { return "" }
        return " \(name)=\"\(Self.escape(value))\""
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func escape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\t", "\n", "\r": result += "&#\(scalar.value);"
            default:
                // Other control characters cannot appear in XML 1.0.
                if scalar.value >= 0x20 { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }

    /// EventDateTime: an xsd:dateTime with its time zone (A.5.2.2).
    static func dateTimeString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

extension DICOMAuditMessage.NetworkAccessPointType {
    /// IP Address for numeric hosts, Machine Name otherwise.
    static func of(_ host: String) -> Self {
        let isIPv4 = host.split(separator: ".").count == 4 && host.allSatisfy { $0.isNumber || $0 == "." }
        return isIPv4 || host.contains(":") ? .ipAddress : .machineName
    }
}

/// The system that reports audit events: AuditSourceIdentification.
public struct DICOMAuditSource: Sendable {
    public var id: String
    public var enterpriseSiteID: String?
    /// AuditSourceTypeCode values: "4" for an application server.
    public var types: [String]

    public init(id: String, enterpriseSiteID: String? = nil, types: [String] = ["4"]) {
        self.id = id
        self.enterpriseSiteID = enterpriseSiteID
        self.types = types
    }
}

// MARK: - The audit messages of PS3.15 A.5.3

extension DICOMAuditMessage {
    // Role ID codes.
    static var application: DICOMAuditCode { .dcm("110150") }
    static var applicationLauncher: DICOMAuditCode { .dcm("110151") }
    public static var destinationRole: DICOMAuditCode { .dcm("110152") }
    public static var sourceRole: DICOMAuditCode { .dcm("110153") }
    public static var destinationMedia: DICOMAuditCode { .dcm("110154") }
    public static var sourceMedia: DICOMAuditCode { .dcm("110155") }

    /// Application Activity (A.5.3.1): an application started or stopped.
    public static func applicationActivity(
        started: Bool, application: ActiveParticipant, launchers: [ActiveParticipant] = [],
        source: DICOMAuditSource, outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        var process = application
        process.roles = [Self.application]
        let launched = launchers.map { participant -> ActiveParticipant in
            var participant = participant
            participant.roles = [applicationLauncher]
            return participant
        }
        return DICOMAuditMessage(
            eventID: .dcm("110100"), action: .execute, dateTime: dateTime, outcome: outcome,
            eventTypes: [.dcm(started ? "110120" : "110121")], participants: [process] + launched, source: source)
    }

    /// Audit Log Used (A.5.3.2).
    public static func auditLogUsed(
        by users: [ActiveParticipant], logURI: String, source: DICOMAuditSource, outcome: Outcome = .success,
        dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(
            eventID: .dcm("110101"), action: .read, dateTime: dateTime, outcome: outcome, participants: users,
            source: source, objects: [ParticipantObject(idType: .uri, id: logURI, name: "Security Audit Log",
                                                         typeCode: "2", typeCodeRole: "13")])
    }

    /// Begin Transferring DICOM Instances (A.5.3.3).
    public static func beginTransferring(
        sender: ActiveParticipant, receiver: ActiveParticipant, others: [ActiveParticipant] = [],
        studies: [ParticipantObject], patient: ParticipantObject, source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(
            eventID: .dcm("110102"), action: .execute, dateTime: dateTime, outcome: outcome,
            participants: [role(sender, sourceRole), role(receiver, destinationRole)] + others, source: source,
            objects: studies + [patient])
    }

    /// Data Export (A.5.3.4): data written to media or sent outside.
    public static func dataExport(
        exporters: [ActiveParticipant], media: ActiveParticipant, recipients: [ActiveParticipant] = [],
        studies: [ParticipantObject], patients: [ParticipantObject], source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        var media = media
        media.isRequestor = false
        media.roles = [destinationMedia]
        return DICOMAuditMessage(
            eventID: .dcm("110106"), action: .read, dateTime: dateTime, outcome: outcome,
            participants: recipients.map { role($0, destinationRole) } + exporters.map { role($0, sourceRole) } + [media],
            source: source, objects: studies + patients)
    }

    /// Data Import (A.5.3.5): data read from media or received from outside.
    public static func dataImport(
        importers: [ActiveParticipant], media: ActiveParticipant, senders: [ActiveParticipant] = [],
        studies: [ParticipantObject], patients: [ParticipantObject], source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        var media = media
        media.isRequestor = false
        media.roles = [sourceMedia]
        return DICOMAuditMessage(
            eventID: .dcm("110107"), action: .create, dateTime: dateTime, outcome: outcome,
            participants: importers.map { role($0, destinationRole) } + [media] + senders.map { role($0, sourceRole) },
            source: source, objects: studies + patients)
    }

    /// DICOM Instances Accessed (A.5.3.6): created, read, updated, or deleted.
    public static func instancesAccessed(
        action: Action, by users: [ActiveParticipant], studies: [ParticipantObject], patient: ParticipantObject,
        source: DICOMAuditSource, outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(eventID: .dcm("110103"), action: action, dateTime: dateTime, outcome: outcome,
                          participants: users, source: source, objects: studies + [patient])
    }

    /// DICOM Instances Transferred (A.5.3.7), when the transfer completes:
    /// create when the receiver did not hold the instances, read otherwise.
    public static func instancesTransferred(
        action: Action = .create, sender: ActiveParticipant, receiver: ActiveParticipant,
        others: [ActiveParticipant] = [], studies: [ParticipantObject], patient: ParticipantObject,
        source: DICOMAuditSource, outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(
            eventID: .dcm("110104"), action: action, dateTime: dateTime, outcome: outcome,
            participants: [role(sender, sourceRole), role(receiver, destinationRole)] + others, source: source,
            objects: studies + [patient])
    }

    /// DICOM Study Deleted (A.5.3.8).
    public static func studyDeleted(
        by users: [ActiveParticipant], studies: [ParticipantObject], patient: ParticipantObject,
        source: DICOMAuditSource, outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(eventID: .dcm("110105"), action: .delete, dateTime: dateTime, outcome: outcome,
                          participants: users, source: source, objects: studies + [patient])
    }

    /// Network Entry (A.5.3.9): a node attached to or detached from the
    /// network.
    public static func networkEntry(
        attached: Bool, node: ActiveParticipant, source: DICOMAuditSource, outcome: Outcome = .success,
        dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        var node = node
        node.isRequestor = false
        return DICOMAuditMessage(eventID: .dcm("110108"), action: .execute, dateTime: dateTime, outcome: outcome,
                                 eventTypes: [.dcm(attached ? "110124" : "110125")], participants: [node], source: source)
    }

    /// Query (A.5.3.10): the query Data Set, with its Transfer Syntax, for
    /// the SOP Class queried.
    public static func query(
        issuer: ActiveParticipant, responder: ActiveParticipant, others: [ActiveParticipant] = [],
        sopClassUID: String, query: Data, transferSyntaxUID: String, source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        let object = ParticipantObject(
            idType: .sopClassUID, id: sopClassUID, query: query,
            details: [(type: "TransferSyntax", value: Data(transferSyntaxUID.utf8))], typeCode: "2", typeCodeRole: "3")
        return DICOMAuditMessage(
            eventID: .dcm("110112"), action: .execute, dateTime: dateTime, outcome: outcome,
            participants: [role(issuer, sourceRole), role(responder, destinationRole)] + others, source: source,
            objects: [object])
    }

    /// Security Alert (A.5.3.11): `type` is a code of CID 403, such as
    /// 110126 Node Authentication; each subject carries an alert
    /// description.
    public static func securityAlert(
        type: DICOMAuditCode, reporters: [ActiveParticipant], performers: [ActiveParticipant] = [],
        subjects: [(id: String, isURI: Bool, description: String)], source: DICOMAuditSource,
        outcome: Outcome = .minorFailure, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        let performers = performers.map { participant -> ActiveParticipant in
            var participant = participant
            participant.isRequestor = false
            return participant
        }
        let objects = subjects.map {
            ParticipantObject(idType: $0.isURI ? .uri : .nodeID, id: $0.id, name: $0.id,
                              details: [(type: "Alert Description", value: Data($0.description.utf8))], typeCode: "2")
        }
        return DICOMAuditMessage(eventID: .dcm("110113"), action: .execute, dateTime: dateTime, outcome: outcome,
                                 eventTypes: [type], participants: reporters + performers, source: source, objects: objects)
    }

    /// User Authentication (A.5.3.12): a login or logout; the user's network
    /// access point is mandatory.
    public static func userAuthentication(
        login: Bool, user: ActiveParticipant, authenticator: ActiveParticipant? = nil, source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(eventID: .dcm("110114"), action: .execute, dateTime: dateTime, outcome: outcome,
                          eventTypes: [.dcm(login ? "110122" : "110123")], participants: [user] + (authenticator.map { [$0] } ?? []),
                          source: source)
    }

    /// Order Record (A.5.3.13).
    public static func orderRecord(
        action: Action, by users: [ActiveParticipant], patient: ParticipantObject, source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(eventID: .dcm("110109"), action: action, dateTime: dateTime, outcome: outcome,
                          participants: users, source: source, objects: [patient])
    }

    /// Patient Record (A.5.3.14).
    public static func patientRecord(
        action: Action, by users: [ActiveParticipant], patient: ParticipantObject, source: DICOMAuditSource,
        outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(eventID: .dcm("110110"), action: action, dateTime: dateTime, outcome: outcome,
                          participants: users, source: source, objects: [patient])
    }

    /// Procedure Record (A.5.3.15).
    public static func procedureRecord(
        action: Action?, by users: [ActiveParticipant], studies: [ParticipantObject] = [],
        patient: ParticipantObject, source: DICOMAuditSource, outcome: Outcome = .success, dateTime: Date = Date()
    ) -> DICOMAuditMessage {
        DICOMAuditMessage(eventID: .dcm("110111"), action: action, dateTime: dateTime, outcome: outcome,
                          participants: users, source: source, objects: studies + [patient])
    }

    private static func role(_ participant: ActiveParticipant, _ role: DICOMAuditCode) -> ActiveParticipant {
        var participant = participant
        if !participant.roles.contains(role) { participant.roles.append(role) }
        return participant
    }
}
