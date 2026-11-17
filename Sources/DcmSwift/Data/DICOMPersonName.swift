import Foundation

/// A structured DICOM Person Name (PN) Value (PS3.5 6.2.1).
///
/// A name contains up to three representations: alphabetic, ideographic, and
/// phonetic. Each representation contains the same five named components.
/// `rawValue` is the interoperable DICOM form and preserves required interior
/// empty groups and components when it is generated.
public struct DICOMPersonName: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    /// One of the alphabetic, ideographic, or phonetic component groups.
    public struct ComponentGroup: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public var familyName: String?
        public var givenName: String?
        public var middleName: String?
        public var namePrefix: String?
        public var nameSuffix: String?

        public init(
            familyName: String? = nil,
            givenName: String? = nil,
            middleName: String? = nil,
            namePrefix: String? = nil,
            nameSuffix: String? = nil
        ) {
            self.familyName = familyName
            self.givenName = givenName
            self.middleName = middleName
            self.namePrefix = namePrefix
            self.nameSuffix = nameSuffix
        }

        public init?(rawValue: String) {
            let components = rawValue.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
            guard components.count <= 5, !components.contains(where: { $0.contains("=") || $0.contains("\\") }) else {
                return nil
            }
            func component(_ index: Int) -> String? {
                guard components.indices.contains(index), !components[index].isEmpty else { return nil }
                return components[index]
            }
            self.init(
                familyName: component(0), givenName: component(1), middleName: component(2),
                namePrefix: component(3), nameSuffix: component(4))
        }

        public var rawValue: String {
            var components = [familyName, givenName, middleName, namePrefix, nameSuffix]
            while let last = components.last, last == nil { components.removeLast() }
            return components.map { $0 ?? "" }.joined(separator: "^")
        }

        /// Whether the group can be serialized without colliding with PN or
        /// multi-value delimiters.
        public var isValid: Bool {
            [familyName, givenName, middleName, namePrefix, nameSuffix]
                .compactMap { $0 }
                .allSatisfy { !$0.contains("^") && !$0.contains("=") && !$0.contains("\\") }
        }

        public var description: String { rawValue }
    }

    public var alphabetic: ComponentGroup?
    public var ideographic: ComponentGroup?
    public var phonetic: ComponentGroup?

    public init(
        alphabetic: ComponentGroup? = nil,
        ideographic: ComponentGroup? = nil,
        phonetic: ComponentGroup? = nil
    ) {
        self.alphabetic = alphabetic
        self.ideographic = ideographic
        self.phonetic = phonetic
    }

    /// Convenience initializer for the common single, alphabetic
    /// representation.
    public init(
        familyName: String? = nil,
        givenName: String? = nil,
        middleName: String? = nil,
        namePrefix: String? = nil,
        nameSuffix: String? = nil
    ) {
        self.init(alphabetic: ComponentGroup(
            familyName: familyName, givenName: givenName, middleName: middleName,
            namePrefix: namePrefix, nameSuffix: nameSuffix))
    }

    public init?(rawValue: String) {
        let groups = rawValue.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
        guard groups.count <= 3, !rawValue.contains("\\") else { return nil }
        func group(_ index: Int) -> ComponentGroup? {
            guard groups.indices.contains(index), !groups[index].isEmpty else { return nil }
            return ComponentGroup(rawValue: groups[index])
        }
        if groups.indices.contains(0), !groups[0].isEmpty, group(0) == nil { return nil }
        if groups.indices.contains(1), !groups[1].isEmpty, group(1) == nil { return nil }
        if groups.indices.contains(2), !groups[2].isEmpty, group(2) == nil { return nil }
        self.init(alphabetic: group(0), ideographic: group(1), phonetic: group(2))
    }

    public var rawValue: String {
        var groups = [alphabetic, ideographic, phonetic]
        while let last = groups.last, last == nil { groups.removeLast() }
        return groups.map { $0?.rawValue ?? "" }.joined(separator: "=")
    }

    /// The first available representation, in DICOM preference order.
    public var preferredRepresentation: ComponentGroup? {
        alphabetic ?? ideographic ?? phonetic
    }

    /// Whether every component can be serialized without delimiter conflicts.
    public var isValid: Bool {
        [alphabetic, ideographic, phonetic].compactMap { $0 }.allSatisfy(\.isValid)
    }

    public var description: String { rawValue }
}
