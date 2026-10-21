/// Optional Query/Retrieve behavior (PS3.4 C.5 and Z.5).
/// Options take effect only when accepted for the operation's SOP Class.
public struct DICOMQueryRetrieveOptions: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let relational = Self(rawValue: 1)
    public static let combinedDateTime = Self(rawValue: 2)
    public static let fuzzyPersonNames = Self(rawValue: 4)
    public static let timezoneAdjustment = Self(rawValue: 8)
    public static let enhancedMultiFrameConversion = Self(rawValue: 16)
    public static let emptyValueMatching = Self(rawValue: 32)
    public static let multipleValueMatching = Self(rawValue: 64)

    static let findModels = [DICOMSOPClass.patientRootFind, DICOMSOPClass.studyRootFind, DICOMSOPClass.patientStudyOnlyFind]
    static let retrieveModels = [DICOMSOPClass.patientRootGet, DICOMSOPClass.patientRootMove,
        DICOMSOPClass.studyRootGet, DICOMSOPClass.studyRootMove,
        DICOMSOPClass.patientStudyOnlyGet, DICOMSOPClass.patientStudyOnlyMove,
        DICOMSOPClass.compositeInstanceRootGet, DICOMSOPClass.compositeInstanceRootMove]

    static func fields(for sopClass: String) -> [Self]? {
        if findModels.contains(sopClass) {
            return [.relational, .combinedDateTime, .fuzzyPersonNames, .timezoneAdjustment,
                    .enhancedMultiFrameConversion, .emptyValueMatching, .multipleValueMatching]
        }
        if [DICOMSOPClass.compositeInstanceRootGet, DICOMSOPClass.compositeInstanceRootMove,
            DICOMSOPClass.compositeInstanceRetrieveWithoutBulkDataGet].contains(sopClass) {
            // Y.5.1.1: byte 1 is reserved, conversion remains byte 2.
            // Z.5.1 explicitly references this layout.
            return [[], .enhancedMultiFrameConversion]
        }
        if retrieveModels.contains(sopClass) { return [.relational, .enhancedMultiFrameConversion] }
        return nil
    }

    /// Encodes the SOP-specific layout, including unsupported options as zero.
    public func negotiation(for sopClass: String) throws -> DICOMExtendedNegotiation {
        guard let fields = Self.fields(for: sopClass) else {
            throw DICOMCommandError("not a Query/Retrieve SOP Class")
        }
        return DICOMExtendedNegotiation(sopClassUID: sopClass,
            applicationInformation: fields.map { !$0.isEmpty && contains($0) ? 1 : 0 })
    }

    public init(negotiation: DICOMExtendedNegotiation) throws {
        guard let fields = Self.fields(for: negotiation.sopClassUID),
              !negotiation.applicationInformation.isEmpty,
              negotiation.applicationInformation.count <= fields.count,
              zip(fields, negotiation.applicationInformation).allSatisfy({ $0.0.isEmpty || $0.1 <= 1 }) else {
            throw DICOMPDUError(.invalidPDUParameterValue, "invalid Query/Retrieve extended negotiation")
        }
        self = []
        for (field, byte) in zip(fields, negotiation.applicationInformation) where byte == 1 { insert(field) }
    }
}

public extension DICOMNegotiatedAssociation {
    /// Accepted options; absent negotiation means baseline behavior.
    func queryRetrieveOptions(for sopClass: String) -> DICOMQueryRetrieveOptions {
        guard let item = extendedNegotiations.first(where: { $0.sopClassUID == sopClass }) else { return [] }
        return (try? DICOMQueryRetrieveOptions(negotiation: item)) ?? []
    }
}
