/// The meaning of a DIMSE status, as the standard names it. Some codes mean
/// different things in different services (A700 is out of resources for
/// storage and for a query alike, but B000 is a coercion in C-STORE and
/// failed sub-operations in C-MOVE), so the command it answers is given.
extension DICOMStatus {
    /// The name of the status (PS3.7 C.1 to C.5, PS3.4 B.2.3, C.4.1.1.4,
    /// C.4.2.1.5, C.4.3.1.4), or nil for a code the standard does not define
    /// for the service.
    ///
    /// - Parameter field: the command of the response; nil for the general statuses only.
    /// - Returns: the name, in English.
    public func name(for field: DICOMCommand.Field? = nil) -> String? {
        if let general = Self.generalNames[code] { return general }
        let service = field.map { DICOMCommand.Field(rawValue: $0.rawValue & 0x7FFF) }
        switch service {
        case .cStoreRequest?:
            switch code {
            case 0xA700...0xA7FF: return "Refused: Out of Resources"
            case 0xA900...0xA9FF: return "Error: Data Set Does Not Match SOP Class"
            case 0xC000...0xCFFF: return "Error: Cannot Understand"
            case 0xB000: return "Warning: Coercion of Data Elements"
            case 0xB007: return "Warning: Data Set Does Not Match SOP Class"
            case 0xB006: return "Warning: Elements Discarded"
            default: return nil
            }
        case .cFindRequest?:
            switch code {
            case 0xA700: return "Refused: Out of Resources"
            case 0xA710: return "Failed: Invalid Prior Record Key"
            case 0xA900: return "Error: Identifier Does Not Match SOP Class"
            case 0xB001: return "Warning: Matching Reached Response Limit"
            case 0xC000...0xCFFF: return "Failed: Unable to Process"
            case 0xFF01: return "Pending: Optional Keys Not Supported"
            default: return nil
            }
        case .cMoveRequest?, .cGetRequest?:
            switch code {
            case 0xA701: return "Refused: Out of Resources – Unable to Calculate Number of Matches"
            case 0xA702: return "Refused: Out of Resources – Unable to Perform Sub-operations"
            case 0xA801 where service == .cMoveRequest: return "Refused: Move Destination Unknown"
            case 0xA900: return "Error: Identifier Does Not Match SOP Class"
            // Frame-level retrieve (PS3.4 C.4.2.1.5, C.4.3.1.4).
            case 0xAA00: return "Failed: None of the Frames Requested Were Found in the SOP Instance"
            case 0xAA01: return "Failed: Unable to Create New Object for This SOP Class"
            case 0xAA02: return "Failed: Unable to Extract Frames"
            case 0xAA03: return "Failed: Time-Based Request Received for a Non-Time-Based Original SOP Instance"
            case 0xAA04: return "Failed: Invalid Request"
            case 0xC000...0xCFFF: return "Failed: Unable to Process"
            case 0xB000: return "Warning: Sub-operations Complete – One or More Failures or Warnings"
            default: return nil
            }
        default:
            return nil
        }
    }

    /// The statuses of every service (PS3.7 C.1 to C.5).
    private static let generalNames: [UInt16: String] = [
        0x0000: "Success",
        0xFF00: "Pending",
        0xFE00: "Cancel",
        0x0001: "Warning: Requested Optional Attributes Are Not Supported",
        0x0107: "Warning: Attribute List Error",
        0x0116: "Warning: Attribute Value Out of Range",
        0x0122: "Failure: Refused: SOP Class Not Supported",
        0x0119: "Failure: Class-Instance Conflict",
        0x0111: "Failure: Duplicate SOP Instance",
        0x0210: "Failure: Duplicate Invocation",
        0x0115: "Failure: Invalid Argument Value",
        0x0106: "Failure: Invalid Attribute Value",
        0x0117: "Failure: Invalid Object Instance",
        0x0120: "Failure: Missing Attribute",
        0x0121: "Failure: Missing Attribute Value",
        0x0212: "Failure: Mistyped Argument",
        0x0114: "Failure: No Such Argument",
        0x0105: "Failure: No Such Attribute",
        0x0113: "Failure: No Such Event Type",
        0x0123: "Failure: No Such Action",
        0x0112: "Failure: No Such Object Instance",
        0x0118: "Failure: No Such SOP Class",
        0x0110: "Failure: Processing Failure",
        0x0213: "Failure: Resource Limitation",
        0x0211: "Failure: Unrecognized Operation",
        0x0124: "Failure: Refused: Not Authorized",
    ]
}
