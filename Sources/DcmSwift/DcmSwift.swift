struct DcmSwift {
    var version = "0.1"
}

// MARK: - Enumeration definition

/**
 The ByteOrder enumeration defines 2 endianess methods, little and big endian
 
 http://dicom.nema.org/dicom/2013/output/chtml/part05/sect_7.3.html
 */
public enum ByteOrder {
    case BigEndian
    case LittleEndian
}


/**
 The VRMethod enumeration defines 2 Value Representation methods
 supported by the DICOM standard
 */
public enum VRMethod {
    case Explicit
    case Implicit
}

