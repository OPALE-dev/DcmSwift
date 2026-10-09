import Foundation

extension DICOMAuditMessage {
    /// The host of a SwiftNIO socket address description, such as
    /// "[IPv4]127.0.0.1/127.0.0.1:55432" or "[IPv6]::1/::1:55432".
    static func host(of description: String?) -> String? {
        guard var text = description, !text.isEmpty, text != "unknown" else { return nil }
        if let slash = text.firstIndex(of: "/") { text = String(text[text.index(after: slash)...]) }
        if let colon = text.lastIndex(of: ":"), Int(text[text.index(after: colon)...]) != nil {
            text = String(text[..<colon])
        }
        return text.isEmpty ? nil : text
    }

    /// The patient and study of a data set, as participant objects, with the
    /// SOP Class of the instance.
    static func objects(of dataSet: DataSet) -> (study: ParticipantObject, patient: ParticipantObject) {
        let sopClass = dataSet.string(forTag: "SOPClassUID") ?? ""
        let study = ParticipantObject.study(
            uid: dataSet.string(forTag: "StudyInstanceUID") ?? "unknown",
            sopClasses: sopClass.isEmpty ? [] : [.init(uid: sopClass, numberOfInstances: 1)],
            accessions: dataSet.string(forTag: "AccessionNumber").map { [$0] } ?? [])
        return (study, patient(of: dataSet.string(forTag: "PatientID"), name: dataSet.string(forTag: "PatientName")))
    }

    static func patient(of id: String?, name: String?) -> ParticipantObject {
        let id = id.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        return .patient(id: id, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? id)
    }

    /// The studies and patients of archive records, each study with its SOP
    /// Classes and their number of instances.
    static func objects(of records: [DICOMArchive.Record]) -> [ParticipantObject] {
        var studies: [String: [String: Int]] = [:]
        var patients: [String: String] = [:]
        for record in records {
            studies[record.attributes["StudyInstanceUID"] ?? "unknown", default: [:]][record.sopClassUID, default: 0] += 1
            patients[record.attributes["PatientID"] ?? "unknown"] = record.attributes["PatientName"]
        }
        let studyObjects = studies.keys.sorted().map { uid in
            ParticipantObject.study(uid: uid, sopClasses: studies[uid]!.keys.sorted().map {
                .init(uid: $0, numberOfInstances: studies[uid]![$0]!)
            })
        }
        return studyObjects + patients.keys.sorted().map { patient(of: $0, name: patients[$0]) }
    }
}

extension DICOMUserIdentity {
    /// The user name, or the kind of credential when it is not a name.
    var primaryFieldDescription: String {
        switch kind {
        case .username, .usernameAndPasscode:
            let name = String(decoding: primaryField, as: UTF8.self)
            return name.isEmpty ? "unknown" : name
        case .kerberos: return "Kerberos ticket"
        case .saml: return "SAML assertion"
        case .jwt: return "JSON Web Token"
        }
    }
}
