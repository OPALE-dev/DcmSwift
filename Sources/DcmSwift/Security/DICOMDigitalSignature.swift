import Crypto
import Foundation
import SwiftASN1
import X509
import _CryptoExtras

/// MAC Algorithm (0400,0015) of the Digital Signatures Macro (PS3.3
/// C.12.1.1.3, PS3.15 C.1).
public enum DICOMMACAlgorithm: String, CaseIterable, Sendable {
    case ripemd160 = "RIPEMD160"
    case md5 = "MD5"
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha384 = "SHA384"
    case sha512 = "SHA512"

    /// Whether DcmSwift creates signatures with it: MD5 and RIPEMD-160 are
    /// only verified, as PS3.15 C.1 recommends against them.
    public var canSign: Bool { ![.md5, .ripemd160].contains(self) }

    func hash(_ data: Data) -> [UInt8] {
        switch self {
        case .ripemd160: return RIPEMD160.hash(data)
        case .md5: return Array(Insecure.MD5.hash(data: data))
        case .sha1: return Array(Insecure.SHA1.hash(data: data))
        case .sha256: return Array(SHA256.hash(data: data))
        case .sha384: return Array(SHA384.hash(data: data))
        case .sha512: return Array(SHA512.hash(data: data))
        }
    }

    /// The DER DigestInfo prefix of PKCS #1 v1.5 (RFC 8017 9.2).
    var digestInfoPrefix: [UInt8] {
        switch self {
        case .md5: return [0x30, 0x20, 0x30, 0x0C, 0x06, 0x08, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x05, 0x05, 0x00, 0x04, 0x10]
        case .sha1: return [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05, 0x00, 0x04, 0x14]
        case .ripemd160: return [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x24, 0x03, 0x02, 0x01, 0x05, 0x00, 0x04, 0x14]
        case .sha256: return [0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20]
        case .sha384: return [0x30, 0x41, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30]
        case .sha512: return [0x30, 0x51, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40]
        }
    }
}

public struct DICOMDigitalSignatureError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// Creates Digital Signatures with the Base RSA Digital Signature Profile
/// (PS3.15 C.1): a MAC of the signed Data Elements, encrypted with an RSA
/// private key, and the X.509 certificate of the signer.
public struct DICOMDigitalSigner: Sendable {
    public let privateKey: _RSA.Signing.PrivateKey
    /// The DER encoding of the signer's certificate.
    public let certificate: [UInt8]
    public let algorithm: DICOMMACAlgorithm

    /// From PEM files: an RSA private key, and the signer's certificate.
    public init(privateKeyPEM: String, certificatePEM: String, algorithm: DICOMMACAlgorithm = .sha256) throws {
        guard algorithm.canSign else { throw DICOMDigitalSignatureError("\(algorithm.rawValue) is not used to sign") }
        privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let parsed = try Certificate(pemEncoded: certificatePEM)
        var serializer = DER.Serializer()
        try serializer.serialize(parsed)
        certificate = serializer.serializedBytes
        guard let key = _RSA.Signing.PublicKey(parsed.publicKey),
              key.pkcs1DERRepresentation == privateKey.publicKey.pkcs1DERRepresentation else {
            throw DICOMDigitalSignatureError("the certificate does not hold the RSA public key of the private key")
        }
        self.algorithm = algorithm
    }

    /// Signs the top level of a data set; returns the Digital Signature UID.
    ///
    /// - Parameters:
    ///   - dataSet: the data set to sign, to which the Items are added.
    ///   - tags: the Data Elements to sign, as 8 hexadecimal digits; all those
    ///     that may be signed when nil (PS3.3 C.12.1.1.3.1.1), which covers
    ///     the Creator and Authorization profiles (PS3.15 C.2, C.3).
    ///   - purpose: Digital Signature Purpose Code Sequence (0400,0401).
    ///   - dateTime: Digital Signature DateTime (0400,0105).
    @discardableResult
    public func sign(_ dataSet: DataSet, tags: [String]? = nil, purpose: DICOMCode? = nil,
                     dateTime: Date = Date()) throws -> String {
        var elements = dataSet.datasetElements
        let uid = try sign(&elements, tags: tags, purpose: purpose, dateTime: dateTime, dataSet: dataSet, parent: nil)
        for element in elements where !dataSet.datasetElements.contains(where: { $0 === element }) {
            dataSet.add(element: element)
        }
        dataSet.sortElements()
        return uid
    }

    /// Signs the Data Elements of a Sequence Item.
    @discardableResult
    public func sign(_ item: DataItem, tags: [String]? = nil, purpose: DICOMCode? = nil, dateTime: Date = Date(),
                     dataSet: DataSet? = nil) throws -> String {
        var elements = item.elements
        let uid = try sign(&elements, tags: tags, purpose: purpose, dateTime: dateTime, dataSet: dataSet, parent: item)
        item.elements = elements.sorted { $0.tagCode() < $1.tagCode() }
        return uid
    }

    private func sign(_ elements: inout [DataElement], tags: [String]?, purpose: DICOMCode?, dateTime: Date,
                      dataSet: DataSet?, parent: DataElement?) throws -> String {
        let ordered = elements.sorted { $0.tagCode() < $1.tagCode() }
        let signed: [DataElement]
        if let tags {
            let wanted = Set(tags.map { $0.uppercased() })
            signed = ordered.filter { wanted.contains($0.tagCode().uppercased()) && DICOMSignatureStream.isSignable($0) }
            guard signed.count == wanted.count else {
                throw DICOMDigitalSignatureError("some Data Elements to sign are absent or cannot be signed")
            }
        } else {
            signed = ordered.filter(DICOMSignatureStream.isSignable)
        }
        // Values padded beyond an even length are shortened first: their
        // padding is not significant, and DCMTK, which reads them so, would
        // not verify the signature otherwise.
        signed.forEach(DICOMSignatureStream.normalizePadding)
        let macParameters = sequence(DICOMSignatureStream.macParametersTag, in: &elements, dataSet: dataSet, parent: parent)
        let signatures = sequence(DICOMSignatureStream.signaturesTag, in: &elements, dataSet: dataSet, parent: parent)
        let used = macParameters.items.compactMap { $0.elements.first { $0.tagCode() == "04000005" }?.uint16Values?.first }
        let macID = (used.max() ?? 0) + 1

        // MAC Parameters Sequence Item.
        let parameters = item(in: macParameters)
        add("04000005", .US, Self.uint16(macID), to: parameters, dataSet: dataSet)
        // Encapsulated Pixel Data is signed in its own Transfer Syntax, which
        // keeps the Explicit VR Little Endian encoding of the other Data
        // Elements; anything else in Explicit VR Little Endian.
        let encapsulated = signed.contains { $0 is PixelSequence }
        let syntax = encapsulated ? dataSet?.transferSyntax?.tsUID ?? TransferSyntax.explicitVRLittleEndian
            : TransferSyntax.explicitVRLittleEndian
        add("04000010", .UI, syntax, to: parameters, dataSet: dataSet)
        add("04000015", .CS, algorithm.rawValue, to: parameters, dataSet: dataSet)
        let tagList = signed.map { DataTag(withGroup: $0.group, element: $0.element) }
        add("04000020", .AT, tagList, to: parameters, dataSet: dataSet)

        // Digital Signatures Sequence Item, but its Signature.
        let signature = item(in: signatures)
        let uid = "2.25." + DICOMDeidentifier.decimal(withUnsafeBytes(of: UUID().uuid) { Array($0) })
        add("04000005", .US, Self.uint16(macID), to: signature, dataSet: dataSet)
        add("04000100", .UI, uid, to: signature, dataSet: dataSet)
        add("04000105", .DT, Self.dateTime(dateTime), to: signature, dataSet: dataSet)
        add("04000110", .CS, "X509_1993_SIG", to: signature, dataSet: dataSet)
        add("04000115", .OB, Data(certificate), to: signature, dataSet: dataSet)
        if let purpose { addPurpose(purpose, to: signature, dataSet: dataSet) }

        let stream = DICOMSignatureStream.bytes(signed: signed, signatureItem: signature)
        let mac = algorithm.hash(stream)
        let value: _RSA.Signing.RSASignature
        switch algorithm {
        case .sha1: value = try privateKey.signature(for: Insecure.SHA1.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .sha256: value = try privateKey.signature(for: SHA256.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .sha384: value = try privateKey.signature(for: SHA384.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .sha512: value = try privateKey.signature(for: SHA512.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .md5, .ripemd160: throw DICOMDigitalSignatureError("\(algorithm.rawValue) is not used to sign")
        }
        _ = mac
        add("04000120", .OB, value.rawRepresentation, to: signature, dataSet: dataSet)
        signature.elements.sort { $0.tagCode() < $1.tagCode() }
        parameters.elements.sort { $0.tagCode() < $1.tagCode() }
        return uid
    }

    // MARK: Building the Items

    private func sequence(_ tag: String, in elements: inout [DataElement], dataSet: DataSet?,
                          parent: DataElement?) -> DataSequence {
        if let existing = elements.first(where: { $0.tagCode().uppercased() == tag }) as? DataSequence { return existing }
        let sequence = DataSequence(withTag: DataTag(withGroup: String(tag.prefix(4)), element: String(tag.suffix(4))),
                                    parent: parent)
        sequence.vr = .SQ
        sequence.length = -1
        sequence.dataset = dataSet
        elements.append(sequence)
        elements.sort { $0.tagCode() < $1.tagCode() }
        return sequence
    }

    private func item(in sequence: DataSequence) -> DataItem {
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        sequence.items.append(item)
        return item
    }

    private func add(_ tag: String, _ vr: VR.VR, _ value: Any, to item: DataItem, dataSet: DataSet?) {
        let element = DataElement(withTag: DataTag(withGroup: String(tag.prefix(4)), element: String(tag.suffix(4))),
                                  dataset: dataSet, parent: item)
        element.vr = vr
        if let data = value as? Data, vr == .US {
            element.data = data
            element.length = data.count
        } else {
            _ = element.setValue(value)
        }
        item.elements.append(element)
    }

    private func addPurpose(_ code: DICOMCode, to item: DataItem, dataSet: DataSet?) {
        let sequence = DataSequence(withTag: DataTag(withGroup: "0400", element: "0401"), parent: item)
        sequence.vr = .SQ
        sequence.length = -1
        let entry = self.item(in: sequence)
        add("00080100", .SH, code.value, to: entry, dataSet: dataSet)
        add("00080102", .SH, code.scheme, to: entry, dataSet: dataSet)
        add("00080104", .LO, code.meaning, to: entry, dataSet: dataSet)
        item.elements.append(sequence)
    }

    static func uint16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }

    /// Digital Signature DateTime, with its offset from UTC.
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMddHHmmss.SSSSSSxx"
        return formatter.string(from: date)
    }
}

/// The byte stream of the MAC calculation (PS3.3 C.12.1.1.3.1.2), in
/// Explicit VR Little Endian.
enum DICOMSignatureStream {
    static let macParametersTag = "4FFE0001"
    static let signaturesTag = "FFFAFFFA"
    private static let itemTag: [UInt8] = [0xFE, 0xFF, 0x00, 0xE0]
    private static let sequenceDelimiterTag: [UInt8] = [0xFE, 0xFF, 0xDD, 0xE0]

    private static let textVRs: Set<VR.VR> = [.AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI,
                                              .UR, .UT]

    /// Removes the trailing padding of a text value, then pads it to an
    /// even length again: NUL for UI, space otherwise; in Sequence Items too.
    static func normalizePadding(_ element: DataElement) {
        if let sequence = element as? DataSequence, !(element is PixelSequence) {
            for item in sequence.items { item.elements.forEach(normalizePadding) }
            return
        }
        guard textVRs.contains(element.vr), var bytes = element.data.map([UInt8].init), !bytes.isEmpty else { return }
        let original = bytes.count
        while let last = bytes.last, last == 0x20 || last == 0x00 { bytes.removeLast() }
        if bytes.count % 2 == 1 { bytes.append(element.vr == .UI ? 0x00 : 0x20) }
        guard bytes != [UInt8](element.data) || bytes.count != original else { return }
        element.data = Data(bytes)
        element.length = bytes.count
        element.recalculateLengthsOfParents()
    }

    /// Whether a Data Element may be signed (C.12.1.1.3.1.1).
    static func isSignable(_ element: DataElement) -> Bool {
        let tag = element.tagCode().uppercased()
        guard let group = Int(tag.prefix(4), radix: 16) else { return false }
        if tag.hasSuffix("0000") || tag == "00080001" || group < 0x0008 || group == 0xFFFA { return false }
        if [macParametersTag, "FFFCFFFC", "FFFEE00D"].contains(tag) || element.vr == .UN { return false }
        if let sequence = element as? DataSequence, !(element is PixelSequence) {
            return sequence.items.allSatisfy { $0.elements.allSatisfy { !containsUN($0) } }
        }
        return true
    }

    private static func containsUN(_ element: DataElement) -> Bool {
        if element.vr == .UN { return true }
        guard let sequence = element as? DataSequence, !(element is PixelSequence) else { return false }
        return sequence.items.contains { $0.elements.contains(where: containsUN) }
    }

    /// The signed Data Elements, then the Digital Signatures Sequence Item
    /// but its Certificate of Signer, Signature, and Certified Timestamp.
    static func bytes(signed: [DataElement], signatureItem: DataItem) -> Data {
        var stream = Data()
        for element in signed { append(element, to: &stream) }
        let excluded: Set<String> = ["04000115", "04000120", "04000305", "04000310"]
        for element in signatureItem.elements.sorted(by: { $0.tagCode() < $1.tagCode() })
        where !excluded.contains(element.tagCode().uppercased()) {
            append(element, to: &stream)
        }
        return stream
    }

    private static func append(_ element: DataElement, to stream: inout Data) {
        if let pixels = element as? PixelSequence {
            // Encapsulated: like a Sequence, the fragments as Items.
            stream.append(element.tag.data(withByteOrder: .LittleEndian))
            stream.append(contentsOf: Array("OB".utf8) + [0, 0])
            for fragment in pixels.items {
                stream.append(contentsOf: itemTag)
                if let data = fragment.data { stream.append(data) }
            }
            stream.append(contentsOf: sequenceDelimiterTag)
        } else if let sequence = element as? DataSequence {
            stream.append(element.tag.data(withByteOrder: .LittleEndian))
            stream.append(contentsOf: Array("SQ".utf8) + [0, 0])
            for item in sequence.items {
                stream.append(contentsOf: itemTag)
                for child in item.elements.sorted(by: { $0.tagCode() < $1.tagCode() }) where isSignable(child) {
                    append(child, to: &stream)
                }
            }
            stream.append(contentsOf: sequenceDelimiterTag)
        } else {
            var encoded = element.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
            // Native Pixel Data read in Implicit VR has no VR of its own; in
            // Explicit VR it is OB up to 8 Bits Allocated, OW above (PS3.5
            // A.2), which is how the MAC encodes it.
            if element.tagCode().uppercased() == "7FE00010", element.dataset?.vrMethod == .Implicit,
               let bits = element.dataset?.unsignedInteger16(forTag: "BitsAllocated"), encoded.count >= 6 {
                let vr = bits <= 8 ? "OB" : "OW"
                encoded.replaceSubrange(4..<6, with: Array(vr.utf8))
            }
            stream.append(encoded)
        }
    }
}

/// The verification of a Digital Signature.
public struct DICOMSignatureVerification: Sendable {
    public enum Status: Equatable, Sendable {
        case valid
        /// The MAC does not match: signed data changed, or the key is wrong.
        case invalid
        /// The signature cannot be checked, for the reason given.
        case unverifiable(String)
    }

    /// The tags from the top level to the Sequence Item that holds the
    /// signature; empty for the top level.
    public let path: [String]
    public let uid: String
    public let algorithm: String
    public let status: Status
    /// The subject of the Certificate of Signer.
    public let signer: String?
    public let dateTime: String?
    /// The signed Data Elements, as 8 hexadecimal digits.
    public let signedTags: [String]

    /// Verifies every Digital Signature of a data set, in Sequence Items
    /// too. The certificates are not checked against trusted authorities.
    public static func verify(_ dataSet: DataSet) -> [DICOMSignatureVerification] {
        verify(dataSet.datasetElements, path: [])
    }

    static func verify(_ elements: [DataElement], path: [String]) -> [DICOMSignatureVerification] {
        var results: [DICOMSignatureVerification] = []
        let ordered = elements.sorted { $0.tagCode() < $1.tagCode() }
        let parameters = (ordered.first { $0.tagCode().uppercased() == DICOMSignatureStream.macParametersTag } as? DataSequence)?
            .items ?? []
        let signatures = (ordered.first { $0.tagCode().uppercased() == DICOMSignatureStream.signaturesTag } as? DataSequence)?
            .items ?? []
        for signature in signatures {
            results.append(verify(signature, parameters: parameters, elements: ordered, path: path))
        }
        // Signatures of Sequence Items.
        for element in ordered {
            guard let sequence = element as? DataSequence, !(element is PixelSequence),
                  ![DICOMSignatureStream.macParametersTag, DICOMSignatureStream.signaturesTag]
                    .contains(element.tagCode().uppercased()) else { continue }
            for item in sequence.items {
                results += verify(item.elements, path: path + [element.tagCode().uppercased()])
            }
        }
        return results
    }

    private static func verify(_ signature: DataItem, parameters: [DataItem], elements: [DataElement],
                               path: [String]) -> DICOMSignatureVerification {
        func value(_ item: DataItem, _ tag: String) -> DataElement? {
            item.elements.first { $0.tagCode().uppercased() == tag }
        }
        let uid = value(signature, "04000100")?.textValues?.first ?? ""
        let dateTime = value(signature, "04000105")?.textValues?.first
        func result(_ status: Status, algorithm: String = "", signer: String? = nil,
                    tags: [String] = []) -> DICOMSignatureVerification {
            DICOMSignatureVerification(path: path, uid: uid, algorithm: algorithm, status: status, signer: signer,
                                       dateTime: dateTime, signedTags: tags)
        }
        guard let macID = value(signature, "04000005")?.uint16Values?.first,
              let macItem = parameters.first(where: { value($0, "04000005")?.uint16Values?.first == macID }) else {
            return result(.unverifiable("no MAC Parameters Sequence Item for this signature"))
        }
        let algorithmName = value(macItem, "04000015")?.textValues?.first ?? ""
        let tags = (value(macItem, "04000020")?.attributeTagValues ?? []).map { ($0.group + $0.element).uppercased() }
        guard let algorithm = DICOMMACAlgorithm(rawValue: algorithmName) else {
            return result(.unverifiable("MAC Algorithm \(algorithmName) is not supported"), algorithm: algorithmName, tags: tags)
        }
        // PS3.3 C.12.1.1.3: Explicit VR Little Endian Transfer Syntaxes,
        // those of encapsulated Pixel Data included.
        guard let syntax = value(macItem, "04000010")?.textValues?.first.flatMap(TransferSyntax.init),
              syntax.vrMethod == .Explicit, syntax.byteOrder == .LittleEndian else {
            return result(.unverifiable("the MAC Calculation Transfer Syntax is not Explicit VR Little Endian"),
                          algorithm: algorithmName, tags: tags)
        }
        guard value(signature, "04000110")?.textValues?.first == "X509_1993_SIG",
              let certificateBytes = value(signature, "04000115")?.data,
              let certificate = try? Certificate(derEncoded: [UInt8](certificateBytes)) else {
            return result(.unverifiable("no X509_1993_SIG Certificate of Signer"), algorithm: algorithmName, tags: tags)
        }
        let signer = String(describing: certificate.subject)
        guard let publicKey = _RSA.Signing.PublicKey(certificate.publicKey),
              let (modulus, exponent) = rsaComponents(Array(publicKey.pkcs1DERRepresentation)),
              let operation = RSAPublicOperation(modulus: modulus, exponent: exponent) else {
            return result(.unverifiable("the Certificate of Signer holds no RSA key"), algorithm: algorithmName,
                          signer: signer, tags: tags)
        }
        let wanted = Set(tags)
        let signed = elements.filter { wanted.contains($0.tagCode().uppercased()) }
        guard signed.count == wanted.count else {
            return result(.invalid, algorithm: algorithmName, signer: signer, tags: tags)
        }
        let stream = DICOMSignatureStream.bytes(signed: signed, signatureItem: signature)
        guard let signatureValue = value(signature, "04000120")?.data else {
            return result(.invalid, algorithm: algorithmName, signer: signer, tags: tags)
        }
        // SHA-1 and SHA-2 with swift-crypto; RIPEMD-160 and MD5, which it
        // lacks, with the public operation below.
        let rsaSignature = _RSA.Signing.RSASignature(rawRepresentation: signatureValue)
        let native: Bool?
        switch algorithm {
        case .sha1: native = publicKey.isValidSignature(rsaSignature, for: Insecure.SHA1.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .sha256: native = publicKey.isValidSignature(rsaSignature, for: SHA256.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .sha384: native = publicKey.isValidSignature(rsaSignature, for: SHA384.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .sha512: native = publicKey.isValidSignature(rsaSignature, for: SHA512.hash(data: stream), padding: .insecurePKCS1v1_5)
        case .md5, .ripemd160: native = nil
        }
        if let native { return result(native ? .valid : .invalid, algorithm: algorithmName, signer: signer, tags: tags) }
        let digest = algorithm.hash(stream)
        guard let decrypted = operation.apply([UInt8](signatureValue)) else {
            return result(.invalid, algorithm: algorithmName, signer: signer, tags: tags)
        }
        // EMSA-PKCS1-v1_5: 00 01 FF..FF 00 DigestInfo (RFC 8017 9.2); some
        // older signers leave out the NULL parameters of the algorithm.
        let infos = [algorithm.digestInfoPrefix + digest, Self.withoutNullParameters(algorithm.digestInfoPrefix) + digest]
        let valid = infos.contains { info in
            guard decrypted.count >= info.count + 11 else { return false }
            let padding = decrypted.count - info.count - 3
            return Array(decrypted.prefix(2)) == [0x00, 0x01]
                && decrypted[2..<(2 + padding)].allSatisfy { $0 == 0xFF }
                && decrypted[2 + padding] == 0x00 && Array(decrypted.suffix(info.count)) == info
        }
        return result(valid ? .valid : .invalid, algorithm: algorithmName, signer: signer, tags: tags)
    }

    /// The DigestInfo prefix without the NULL parameters (05 00).
    private static func withoutNullParameters(_ prefix: [UInt8]) -> [UInt8] {
        var bytes = prefix
        guard let index = bytes.firstIndex(of: 0x05), index + 1 < bytes.count, bytes[index + 1] == 0x00 else { return prefix }
        bytes.removeSubrange(index...(index + 1))
        bytes[1] -= 2
        bytes[3] -= 2
        return bytes
    }

    /// The modulus and exponent of a PKCS #1 RSAPublicKey: SEQUENCE {
    /// INTEGER n, INTEGER e }.
    static func rsaComponents(_ der: [UInt8]) -> (modulus: [UInt8], exponent: [UInt8])? {
        var index = 0
        func length() -> Int? {
            guard index < der.count else { return nil }
            let first = Int(der[index]); index += 1
            if first < 0x80 { return first }
            let count = first & 0x7F
            guard count <= 4, index + count <= der.count else { return nil }
            var value = 0
            for _ in 0..<count { value = value << 8 | Int(der[index]); index += 1 }
            return value
        }
        func integer() -> [UInt8]? {
            guard index < der.count, der[index] == 0x02 else { return nil }
            index += 1
            guard let count = length(), index + count <= der.count else { return nil }
            defer { index += count }
            return Array(der[index..<(index + count)])
        }
        guard der.first == 0x30 else { return nil }
        index = 1
        guard length() != nil, let modulus = integer(), let exponent = integer() else { return nil }
        return (modulus, exponent)
    }
}
