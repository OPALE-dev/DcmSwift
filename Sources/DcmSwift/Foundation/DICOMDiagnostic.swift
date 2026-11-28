import Foundation

/// A message of DcmSwift with what an application needs to translate it:
/// its template, among ``DICOMDiagnosticTemplate``, and its arguments.
/// ``description`` is the English message; ``formatted(_:)`` renders it
/// with the templates of another language.
///
/// Read failures (``DicomReadFailure``), encoding checks
/// (``ValidationResult``), and IOD findings (``DICOMIODFinding``) carry one.
public struct DICOMDiagnostic: Sendable, Equatable, CustomStringConvertible {
    /// An argument of a template: text shown as it is, such as a tag, a
    /// number or a UID, or another message, translated in turn.
    public enum Argument: Sendable, Equatable {
        case text(String)
        indirect case diagnostic(DICOMDiagnostic)
    }

    public let template: DICOMDiagnosticTemplate
    public let arguments: [Argument]

    public init(_ template: DICOMDiagnosticTemplate, _ arguments: [Argument] = []) {
        self.template = template
        self.arguments = arguments
    }

    /// A template with text arguments.
    public init(_ template: DICOMDiagnosticTemplate, _ arguments: String...) {
        self.init(template, arguments.map(Argument.text))
    }

    /// A message DcmSwift does not know, shown as it is.
    public static func verbatim(_ text: String) -> DICOMDiagnostic {
        DICOMDiagnostic(.verbatim, [.text(text)])
    }

    /// The diagnostic of an English message: the template it is, for a
    /// message without arguments, otherwise the message shown as it is.
    public static func parsing(_ message: String) -> DICOMDiagnostic {
        DICOMDiagnosticTemplate(rawValue: message).map { DICOMDiagnostic($0) } ?? .verbatim(message)
    }

    /// The English message.
    public var description: String { formatted { $0.rawValue } }

    /// The message with the templates `translate` gives, such as those of a
    /// string catalog. A template names its arguments `%1$@`, `%2$@`…; a
    /// translation may reorder them.
    public func formatted(_ translate: (DICOMDiagnosticTemplate) -> String) -> String {
        let values = arguments.map { argument -> String in
            switch argument {
            case .text(let text): text
            case .diagnostic(let diagnostic): diagnostic.formatted(translate)
            }
        }
        return Self.substitute(translate(template), values)
    }

    /// Replaces `%n$@` by the nth value, and `%@` by the next one.
    static func substitute(_ format: String, _ values: [String]) -> String {
        var result = ""
        var next = 0
        var index = format.startIndex
        while index < format.endIndex {
            let character = format[index]
            guard character == "%" else {
                result.append(character)
                index = format.index(after: index)
                continue
            }
            var cursor = format.index(after: index)
            var digits = ""
            while cursor < format.endIndex, format[cursor].isNumber {
                digits.append(format[cursor])
                cursor = format.index(after: cursor)
            }
            if !digits.isEmpty, cursor < format.endIndex, format[cursor] == "$" {
                cursor = format.index(after: cursor)
            } else {
                digits = ""
                cursor = format.index(after: index)
            }
            if cursor < format.endIndex, format[cursor] == "@" {
                let position = digits.isEmpty ? next : (Int(digits) ?? 1) - 1
                next = position + 1
                result += values.indices.contains(position) ? values[position] : ""
                index = format.index(after: cursor)
            } else if cursor < format.endIndex, format[cursor] == "%" {
                result.append("%")
                index = format.index(after: cursor)
            } else {
                result.append(character)
                index = format.index(after: index)
            }
        }
        return result
    }
}

/// The English templates of the messages of DcmSwift: the key of each in a
/// string catalog. Their arguments are `%1$@`, `%2$@`…
public enum DICOMDiagnosticTemplate: String, CaseIterable, Sendable {
    /// A message shown as it is, such as an error of the system.
    case verbatim = "%1$@"

    // MARK: Reading (DicomReadFailure)

    case noSuchFile = "No such file"
    case cannotOpenStream = "Cannot open stream, init failed"
    case cannotReadMagic = "Cannot read DICOM magic bytes (DICM)"
    case notDICOM = "Not a DICOM file, no DICM magic bytes found"
    case unsupportedTransferSyntax = "Unsupported Transfer Syntax %1$@"
    case cannotReadDeflated = "Cannot read deflated Data Set"
    case cannotParseInflated = "Cannot parse inflated Data Set"
    case datasetCorrupted = "Dataset is corrupted"
    case unreadableElement = "Unreadable data element at offset %1$@"
    case elementCountExceeded = "Fatal, maximum Data Element count exceeded (%1$@)"
    case truncatedHeader = "Fatal, truncated header for %1$@"
    case invalidExplicitVRHeader = "Fatal, invalid or truncated Explicit VR header for %1$@ at offset %2$@"
    case truncatedValueLength = "Fatal, truncated value length for %1$@ at offset %2$@"
    case negativeLength = "Fatal, invalid negative length for %1$@ at offset %2$@"
    case lengthExceedsMaximum = "Fatal, value length for %1$@ exceeds configured maximum (%2$@ > %3$@)"
    case lengthOverflows = "Fatal, cannot read length properly, decoded %1$@ length at offset(%2$@) overflows (%3$@)"
    case sequenceDepthExceeded = "Fatal, maximum Sequence nesting depth exceeded (%1$@)"
    case truncatedDelimiterLength = "Fatal, truncated %1$@ length"
    case delimiterLengthNotZero = "Fatal, %1$@ length must be zero (%2$@)"
    case expectedItemTag = "Fatal, expected Item tag in Sequence but found %1$@"
    case negativeItemLength = "Fatal, invalid negative Item length (%1$@)"
    case itemLengthExceedsMaximum = "Fatal, Item length exceeds configured maximum (%1$@ > %2$@)"
    case itemCountExceeded = "Fatal, maximum Sequence Item count exceeded (%1$@)"
    case truncatedUndefinedLengthItem = "Fatal, truncated undefined-length Item"
    case sequenceDelimiterBeforeItemDelimiter = "Fatal, Sequence Delimitation Item found before Item Delimitation Item"
    case unreadableElementInUndefinedLengthItem = "Fatal, cannot read Data Element in undefined-length Item"
    case itemLengthOverflowsStream = "Fatal, Item length overflows the remaining stream"
    case itemLengthExceedsSequence = "Fatal, Item length exceeds its enclosing Sequence"
    case unreadableElementInDefinedLengthItem = "Fatal, cannot read Data Element in defined-length Item"
    case elementCrossesItem = "Fatal, Data Element crosses the defined Item boundary"
    case sequenceLengthOverflowsStream = "Fatal, Sequence length overflows the remaining stream"
    case truncatedItemHeader = "Fatal, truncated Item header in defined-length Sequence"
    case sequenceLengthMismatch = "Fatal, Sequence content does not match its defined length"
    case missingSequenceDelimiter = "Fatal, missing Sequence Delimitation Item"
    case truncatedItemLength = "Fatal, truncated Item length in undefined-length Sequence"
    case invalidPixelDelimiter = "Fatal, invalid Pixel Data Sequence Delimitation Item"
    case unexpectedPixelTag = "Fatal, unexpected tag %1$@ in encapsulated Pixel Data"
    case fragmentCountExceeded = "Fatal, maximum Pixel Data fragment count exceeded (%1$@)"
    case undefinedFragmentLength = "Fatal, encapsulated Pixel Data items require defined lengths"
    case fragmentLengthOverflows = "Fatal, cannot read PixelSequence item length properly, decoded length at offset(%1$@) overflows (%2$@)"

    // MARK: Encoding (ValidationResult)

    case noPreamble = "No prefix header was found"
    case groupLengthMismatch = "File Meta Information Group Length is %1$@ but the group holds %2$@ bytes (PS3.10 7.1)"
    case duplicateElement = "Data Element %1$@ appears more than once (PS3.5 7.1)"
    case tagsNotAscending = "Data Element %1$@ follows %2$@: tags are not in ascending order (PS3.5 7.1)"
    case noPrivateCreator = "Private Data Element %1$@ has no Private Creator (%2$@) (PS3.5 7.8.1)"
    case oddLength = "Value Field length must be even (%1$@)"
    case unsupportedTransferSyntaxElement = "Transfer Syntax is not supported by this implementation [%1$@]"
    case unsupportedSOPClass = "SOP Class is not supported by this implementation [%1$@]"
    case fixedWidthLength = "Invalid VR length of %1$@ element [%2$@] (%3$@ is not a multiple of %4$@)"
    case invalidValue = "Value %1$@ of %2$@ is invalid for %3$@: %4$@"
    case undecodableText = "%1$@ cannot be decoded in its Specific Character Set"
    case uiPaddedWithSpace = "%1$@ is padded with a space; UI is padded with NUL (PS3.5 6.2)"
    case paddedWithNUL = "%1$@ is padded with NUL; %2$@ is padded with a space (PS3.5 6.2)"
    case retiredTag = "Tag %1$@ %2$@ is retired"
    case unknownTag = "Unknow tag, may be private"
    case vrMismatch = "Value Representation mismatch, %1$@ permits %2$@"
    case vmMismatch = "Value Multiplicity mismatch, %1$@ requires VM %2$@ but contains %3$@"
    case missingMetaElement = "Missing required File Meta Information element %1$@"
    case metaMismatch = "%1$@ does not match %2$@"
    case transferSyntaxMismatch = "TransferSyntaxUID does not match the Data Set transfer syntax"

    // MARK: Values (PS3.5 Table 6.2-1)

    case longerThanBytes = "longer than %1$@ bytes"
    case longerThanCharacters = "longer than %1$@ characters"
    case outsideDefaultRepertoire = "outside the Default Character Repertoire"
    case onlySpaces = "only spaces"
    case notAge = "not nnnD, nnnW, nnnM, or nnnY"
    case notCodeString = "not uppercase letters, digits, space, or underscore"
    case acrNemaDate = "ACR-NEMA YYYY.MM.DD format, not compliant"
    case notDate = "not a YYYYMMDD date"
    case notDecimal = "not a decimal number"
    case notDateTime = "not a YYYYMMDDHHMMSS.FFFFFF&ZZXX date and time"
    case notInteger = "not an integer between -2^31 and 2^31-1"
    case acrNemaTime = "HH:MM:SS format of ACR-NEMA, not compliant"
    case notTime = "not an HHMMSS.FFFFFF time"
    case notUID = "not digits in dot-separated components without leading zeros"
    case leadingSpace = "leading space"
    case notURI = "not a URI of the Default Character Repertoire"
    case controlOrBackslash = "control character or backslash"
    case controlCharacter = "control character other than TAB, LF, FF, CR, or ESC"
    case tooManyComponentGroups = "more than three component groups"
    case longComponentGroup = "a component group longer than 64 characters"
    case tooManyComponents = "more than five components"

    // MARK: IOD (DICOMIODFinding)

    case noSOPClass = "SOP Class UID is missing, so the IOD is unknown"
    case noIOD = "SOP Class %1$@ has no IOD in PS3.3 %2$@"
    case missing = "is missing (Type %1$@)"
    case missingByCondition = "is missing (Type %1$@, required by its condition)"
    case empty = "is empty (Type %1$@)"
    case notEnumerated = "has the value \"%1$@\", not one of the Enumerated Values %2$@"
    case missingFunctionalGroup = "is in neither the Shared nor every Per-Frame Functional Groups Sequence Item"

    /// Whether a value problem keeps a format of ACR-NEMA: a warning, not an error.
    public var isACRNEMAFormat: Bool { self == .acrNemaDate || self == .acrNemaTime }
}
