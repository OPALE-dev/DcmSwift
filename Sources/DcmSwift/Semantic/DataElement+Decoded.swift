import Foundation

extension DataElement {
    /// The VR to read the Value with: the Data Dictionary's for UN Values
    /// (PS3.5 6.2.2, Little Endian).
    var decodingVR: VR.VR {
        guard vr == .UN, !(self is DataSequence),
              let known = DicomSpec.shared.vrForTag(withCode: tagCode()), known != .UN else { return vr }
        return known
    }

    /// The Values as text, also for UN Values of a text VR.
    var decodedTexts: [String]? {
        if let texts = textValues { return texts }
        guard vr == .UN, let data, [.AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT]
            .contains(decodingVR) else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        while text.last == " " || text.last == "\0" { text.removeLast() }
        return text.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
    }

    /// The Values as numbers: decimal and integer strings, binary integers
    /// and floats, also for UN Values.
    var decodedNumbers: [Double] {
        if let texts = decodedTexts {
            return texts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        let vr = decodingVR
        let order = self.vr == .UN ? ByteOrder.LittleEndian : byteOrder
        guard let data else { return [] }
        let bytes = [UInt8](data)
        func words(_ width: Int) -> [UInt64] {
            guard bytes.count.isMultiple(of: width) else { return [] }
            return stride(from: 0, to: bytes.count, by: width).map { offset in
                (0..<width).reduce(UInt64(0)) { value, index in
                    let byte = UInt64(bytes[offset + (order == .BigEndian ? width - 1 - index : index)])
                    return value | byte << UInt64(index * 8)
                }
            }
        }
        switch vr {
        case .US: return words(2).map { Double($0) }
        case .SS: return words(2).map { Double(Int16(truncatingIfNeeded: $0)) }
        case .UL: return words(4).map { Double($0) }
        case .SL: return words(4).map { Double(Int32(truncatingIfNeeded: $0)) }
        case .UV: return words(8).map { Double($0) }
        case .SV: return words(8).map { Double(Int64(bitPattern: $0)) }
        case .FL: return words(4).map { Double(Float(bitPattern: UInt32($0))) }
        case .FD: return words(8).map { Double(bitPattern: $0) }
        default: return []
        }
    }
}
