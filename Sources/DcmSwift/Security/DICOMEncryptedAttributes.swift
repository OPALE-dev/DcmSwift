import Crypto
import Foundation
import SwiftASN1
import X509
import _CryptoExtras

/// A recipient of encrypted attributes: the X.509 certificate of its RSA
/// key (PS3.15 E.1.1, key transport).
public struct DICOMEncryptionRecipient: Sendable {
    public enum KeyTransport: Sendable {
        /// rsaEncryption, PKCS #1 v1.5 (RFC 3370 4.2.1).
        case pkcs1v1_5
        /// RSAES-OAEP with SHA-1 (RFC 3560).
        case oaep
    }

    /// The PKCS #1 DER of the RSA public key.
    let publicKeyDER: Data
    /// DER of the certificate's issuer Name.
    let issuer: [UInt8]
    let serialNumber: [UInt8]
    public let keyTransport: KeyTransport

    public init(certificatePEM: String, keyTransport: KeyTransport = .pkcs1v1_5) throws {
        let certificate = try Certificate(pemEncoded: certificatePEM)
        guard let key = _RSA.Signing.PublicKey(certificate.publicKey) else {
            throw DICOMEncryptionError("the certificate holds no RSA key")
        }
        publicKeyDER = key.pkcs1DERRepresentation
        _ = try _RSA.Encryption.PublicKey(derRepresentation: publicKeyDER)
        var serializer = DER.Serializer()
        try serializer.serialize(certificate.issuer)
        issuer = serializer.serializedBytes
        serialNumber = Array(certificate.serialNumber.bytes)
        self.keyTransport = keyTransport
    }
}

public struct DICOMEncryptionError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// The Encrypted Attributes Sequence (0400,0500) (PS3.3 C.12.1.1.4): the
/// original values of protected attributes in a Modified Attributes Sequence
/// (0400,0550), encrypted as CMS Enveloped-data (RFC 5652) for recipients.
public enum DICOMEncryptedAttributes {
    /// AES-256-CBC content encryption (RFC 3565).
    static let aes256CBC = "2.16.840.1.101.3.4.1.42"
    static let contentAlgorithms: [String: Int] = [
        "2.16.840.1.101.3.4.1.2": 16, "2.16.840.1.101.3.4.1.22": 24, "2.16.840.1.101.3.4.1.42": 32,
    ]
    static let rsaEncryption = "1.2.840.113549.1.1.1"
    static let rsaesOAEP = "1.2.840.113549.1.1.7"
    static let envelopedData = "1.2.840.113549.1.7.3"
    static let data = "1.2.840.113549.1.7.1"

    /// Adds an Item to the Encrypted Attributes Sequence of `dataSet` with
    /// the original Data Elements, readable by each recipient.
    public static func add(_ originals: [DataElement], to dataSet: DataSet,
                           recipients: [DICOMEncryptionRecipient]) throws {
        guard !recipients.isEmpty else { throw DICOMEncryptionError("no recipient") }
        // The Encrypted Attributes Data Set: a Modified Attributes Sequence
        // with one Item, in Explicit VR Little Endian.
        let content = DataSet()
        let modified = DataSequence(withTag: DataTag(withGroup: "0400", element: "0550"))
        modified.vr = .SQ
        modified.length = -1
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: modified)
        item.length = -1
        item.elements = originals.sorted { $0.tagCode() < $1.tagCode() }
        for element in item.elements { element.parent = item }
        modified.items = [item]
        content.add(element: modified)
        let encoded = try DICOMDataSetCoding.encode(content, transferSyntax: TransferSyntax.explicitVRLittleEndian)
        let enveloped = try envelope(encoded, recipients: recipients)

        let sequence = (dataSet.element(forTagName: "EncryptedAttributesSequence") as? DataSequence) ?? {
            let sequence = DataSequence(withTag: DataTag(withGroup: "0400", element: "0500"))
            sequence.vr = .SQ
            sequence.length = -1
            dataSet.add(element: sequence)
            return sequence
        }()
        let entry = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        entry.length = -1
        for (tag, vr, value) in [("0510", VR.VR.UI, TransferSyntax.explicitVRLittleEndian as Any), ("0520", .OB, enveloped)] {
            let element = DataElement(withTag: DataTag(withGroup: "0400", element: tag), dataset: dataSet, parent: entry)
            element.vr = vr
            _ = element.setValue(value)
            entry.elements.append(element)
        }
        sequence.items.append(entry)
        dataSet.sortElements()
    }

    /// The original Data Elements of every Encrypted Attributes Sequence
    /// Item that `privateKeyPEM` opens, overlaid.
    public static func decrypt(_ dataSet: DataSet, privateKeyPEM: String) throws -> [DataElement] {
        let key = try _RSA.Encryption.PrivateKey(pemRepresentation: privateKeyPEM)
        guard let sequence = dataSet.element(forTagName: "EncryptedAttributesSequence") as? DataSequence else { return [] }
        var originals: [String: DataElement] = [:]
        var opened = false
        for item in sequence.items {
            guard let syntax = item.element(withName: "EncryptedContentTransferSyntaxUID")?.textValues?.first,
                  let enveloped = item.elements.first(where: { $0.tagCode() == "04000520" })?.data,
                  let content = try? open([UInt8](enveloped), key: key) else { continue }
            opened = true
            let decoded = try DICOMDataSetCoding.decode(content, transferSyntax: syntax)
            for element in (decoded.element(forTagName: "ModifiedAttributesSequence") as? DataSequence)?.items.first?.elements ?? [] {
                originals[element.tagCode()] = element
            }
        }
        guard opened else { throw DICOMEncryptionError("no Encrypted Attributes Sequence Item is for this key") }
        return originals.keys.sorted().compactMap { originals[$0] }
    }

    /// Puts back the original values of the top-level attributes that
    /// `privateKeyPEM` decrypts; returns their number.
    @discardableResult
    public static func restore(_ dataSet: DataSet, privateKeyPEM: String) throws -> Int {
        let originals = try decrypt(dataSet, privateKeyPEM: privateKeyPEM)
        for original in originals {
            if let current = dataSet.datasetElements.first(where: { $0.tagCode() == original.tagCode() }) {
                _ = dataSet.remove(dataElement: current)
            }
            original.parent = nil
            dataSet.add(element: original)
        }
        dataSet.sortElements()
        return originals.count
    }

    // MARK: CMS Enveloped-data (RFC 5652)

    static func envelope(_ content: Data, recipients: [DICOMEncryptionRecipient]) throws -> Data {
        let key = SymmetricKey(size: .bits256)
        let iv = AES._CBC.IV()
        let encrypted = try AES._CBC.encrypt(content, using: key, iv: iv)
        let keyBytes = key.withUnsafeBytes { Data($0) }
        let infos = try recipients.map { recipient -> [UInt8] in
            let publicKey = try _RSA.Encryption.PublicKey(derRepresentation: recipient.publicKeyDER)
            let algorithm: [UInt8]
            let wrapped: Data
            switch recipient.keyTransport {
            case .pkcs1v1_5:
                algorithm = CMSDER.sequence(CMSDER.oid(rsaEncryption) + CMSDER.null)
                wrapped = try publicKey.encrypt(keyBytes, padding: ._WEAK_AND_INSECURE_PKCS_V1_5)
            case .oaep:
                algorithm = CMSDER.sequence(CMSDER.oid(rsaesOAEP) + CMSDER.sequence([]))
                wrapped = try publicKey.encrypt(keyBytes, padding: .PKCS1_OAEP)
            }
            // KeyTransRecipientInfo, version 0, by IssuerAndSerialNumber.
            return CMSDER.sequence(CMSDER.integer([0]) + CMSDER.sequence(recipient.issuer + CMSDER.integer(recipient.serialNumber))
                                + algorithm + CMSDER.octetString(Array(wrapped)))
        }
        let contentInfo = CMSDER.sequence(
            CMSDER.oid(data) + CMSDER.sequence(CMSDER.oid(aes256CBC) + CMSDER.octetString(Array(iv)))
                + CMSDER.element(0x80, Array(encrypted)))
        let enveloped = CMSDER.sequence(CMSDER.integer([0]) + CMSDER.element(0x31, infos.sorted { $0.lexicographicallyPrecedes($1) }.flatMap { $0 })
                                     + contentInfo)
        return Data(CMSDER.sequence(CMSDER.oid(envelopedData) + CMSDER.element(0xA0, enveloped)))
    }

    /// The content of Enveloped-data, opened with one of its key transport
    /// recipients.
    static func open(_ bytes: [UInt8], key: _RSA.Encryption.PrivateKey) throws -> Data {
        guard let info = CMSDER.Node.parse(bytes), info.children.count == 2, info.children[0].oid == envelopedData,
              let enveloped = info.children[1].children.first else {
            throw DICOMEncryptionError("not CMS Enveloped-data")
        }
        // EnvelopedData: version, [0] originatorInfo?, recipientInfos,
        // encryptedContentInfo, [1] unprotectedAttrs?
        let parts = enveloped.children.filter { $0.tag != 0xA0 && $0.tag != 0xA1 }
        guard parts.count >= 3, parts[1].tag == 0x31 else { throw DICOMEncryptionError("malformed Enveloped-data") }
        let contentInfo = parts[2]
        guard contentInfo.children.count >= 3, let algorithm = contentInfo.children[1].children.first?.oid,
              let keySize = contentAlgorithms[algorithm],
              let iv = contentInfo.children[1].children.dropFirst().first?.content else {
            throw DICOMEncryptionError("unsupported content encryption")
        }
        // [0] IMPLICIT OCTET STRING, primitive or constructed.
        let encryptedNode = contentInfo.children[2]
        let encrypted = encryptedNode.tag == 0x80 ? encryptedNode.content : encryptedNode.children.flatMap(\.content)
        for recipient in parts[1].children where recipient.tag == 0x30 {
            guard recipient.children.count == 4, let transport = recipient.children[2].children.first?.oid else { continue }
            let padding: _RSA.Encryption.Padding
            switch transport {
            case rsaEncryption: padding = ._WEAK_AND_INSECURE_PKCS_V1_5
            case rsaesOAEP: padding = .PKCS1_OAEP
            default: continue
            }
            guard let symmetric = try? key.decrypt(recipient.children[3].content, padding: padding),
                  symmetric.count == keySize else { continue }
            return try AES._CBC.decrypt(encrypted, using: SymmetricKey(data: symmetric), iv: AES._CBC.IV(ivBytes: iv))
        }
        throw DICOMEncryptionError("no recipient matches the key")
    }
}

/// A minimal DER encoder and parser for CMS.
enum CMSDER {
    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag] + length(content.count) + content }
    static func sequence(_ content: [UInt8]) -> [UInt8] { element(0x30, content) }
    static func octetString(_ content: [UInt8]) -> [UInt8] { element(0x04, content) }
    static let null: [UInt8] = [0x05, 0x00]

    static func integer(_ bytes: [UInt8]) -> [UInt8] {
        var value = Array(bytes.drop { $0 == 0 })
        if value.isEmpty { value = [0] }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return element(0x02, value)
    }

    static func oid(_ text: String) -> [UInt8] {
        let arcs = text.split(separator: ".").compactMap { UInt64($0) }
        var bytes: [UInt8] = [UInt8(arcs[0] * 40 + arcs[1])]
        for arc in arcs.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(arc & 0x7F)]
            var value = arc >> 7
            while value > 0 { chunk.insert(UInt8(value & 0x7F) | 0x80, at: 0); value >>= 7 }
            bytes += chunk
        }
        return element(0x06, bytes)
    }

    struct Node {
        let tag: UInt8
        let content: [UInt8]
        let children: [Node]

        var oid: String? {
            guard tag == 0x06, let first = content.first else { return nil }
            var arcs = [UInt64(first / 40), UInt64(first % 40)]
            var value: UInt64 = 0
            for byte in content.dropFirst() {
                value = value << 7 | UInt64(byte & 0x7F)
                if byte & 0x80 == 0 { arcs.append(value); value = 0 }
            }
            return arcs.map(String.init).joined(separator: ".")
        }

        static func parse(_ bytes: [UInt8]) -> Node? {
            var index = 0
            return parse(bytes, &index, end: bytes.count)
        }

        private static func parse(_ bytes: [UInt8], _ index: inout Int, end: Int) -> Node? {
            guard index + 2 <= end else { return nil }
            let tag = bytes[index]
            index += 1
            var count = Int(bytes[index])
            index += 1
            var indefinite = false
            if count == 0x80 {
                indefinite = true
                count = 0
            } else if count > 0x80 {
                let size = count & 0x7F
                guard size <= 4, index + size <= end else { return nil }
                count = 0
                for _ in 0..<size { count = count << 8 | Int(bytes[index]); index += 1 }
            }
            let constructed = tag & 0x20 != 0
            if indefinite {
                // BER, as some encoders produce: children until 00 00.
                guard constructed else { return nil }
                var children: [Node] = []
                while index + 2 <= end, !(bytes[index] == 0 && bytes[index + 1] == 0) {
                    guard let child = parse(bytes, &index, end: end) else { return nil }
                    children.append(child)
                }
                index += 2
                return Node(tag: tag, content: [], children: children)
            }
            guard index + count <= end else { return nil }
            let content = Array(bytes[index..<(index + count)])
            var children: [Node] = []
            if constructed {
                var inner = index
                while inner < index + count {
                    guard let child = parse(bytes, &inner, end: index + count) else { return nil }
                    children.append(child)
                }
            }
            index += count
            return Node(tag: tag, content: content, children: children)
        }
    }
}
