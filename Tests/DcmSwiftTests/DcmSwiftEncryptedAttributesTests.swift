import Foundation
import SwiftASN1
import X509
import XCTest
import _CryptoExtras
@testable import DcmSwift

/// Encrypted Attributes (PS3.3 C.12.1.1.4) and their use in
/// de-identification (PS3.15 E.1.1).
final class DcmSwiftEncryptedAttributesTests: XCTestCase {
    /// An RSA key and a certificate for it, as PEM.
    private static func credentials(_ name: String) -> (key: String, certificate: String) {
        let key = try! _RSA.Signing.PrivateKey(keySize: .bits2048)
        let privateKey = Certificate.PrivateKey(key)
        let subject = try! DistinguishedName { CommonName(name) }
        let certificate = try! Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: privateKey.publicKey,
            notValidBefore: Date().addingTimeInterval(-3600), notValidAfter: Date().addingTimeInterval(86400),
            issuer: subject, subject: subject, signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: Certificate.Extensions(), issuerPrivateKey: privateKey)
        return (key.pemRepresentation, try! certificate.serializeAsPEM().pemString)
    }

    private static let first = credentials("First recipient")
    private static let second = credentials("Second recipient")

    func testDeidentificationKeepsTheOriginalsEncrypted() throws {
        let dataSet = DcmSwiftIODValidationTests.secondaryCaptureImage()
        var deidentifier = try DICOMDeidentifier(key: Data("key".utf8))
        deidentifier.encryptionRecipients = [
            try DICOMEncryptionRecipient(certificatePEM: Self.first.certificate),
            try DICOMEncryptionRecipient(certificatePEM: Self.second.certificate, keyTransport: .oaep),
        ]
        deidentifier.deidentify(dataSet)
        XCTAssertEqual(dataSet.string(forTag: "PatientName"), "")
        let sequence = try XCTUnwrap(dataSet.element(forTagName: "EncryptedAttributesSequence") as? DataSequence)
        XCTAssertEqual(sequence.items.count, 1)
        XCTAssertEqual(sequence.items.first?.element(withName: "EncryptedContentTransferSyntaxUID")?.textValues,
                       [TransferSyntax.explicitVRLittleEndian])

        // Each recipient opens it.
        for recipient in [Self.first, Self.second] {
            let originals = try DICOMEncryptedAttributes.decrypt(dataSet, privateKeyPEM: recipient.key)
            let values = Dictionary(uniqueKeysWithValues: originals.map { ($0.name, $0.textValues?.first ?? "") })
            XCTAssertEqual(values["PatientName"], "Doe^Jane")
            XCTAssertEqual(values["SOPInstanceUID"], "1.2.826.0.1.3680043.10.1.1")
            // Only removed or changed attributes are kept.
            XCTAssertNil(values["Modality"])
        }
        XCTAssertThrowsError(try DICOMEncryptedAttributes.decrypt(dataSet, privateKeyPEM: Self.credentials("Other").key))

        // Restoration puts the values back.
        XCTAssertGreaterThan(try DICOMEncryptedAttributes.restore(dataSet, privateKeyPEM: Self.first.key), 0)
        XCTAssertEqual(dataSet.string(forTag: "PatientName"), "Doe^Jane")
        XCTAssertEqual(dataSet.string(forTag: "SOPInstanceUID"), "1.2.826.0.1.3680043.10.1.1")
    }

    func testEnvelopeStructure() throws {
        let recipient = try DICOMEncryptionRecipient(certificatePEM: Self.first.certificate)
        let envelope = try DICOMEncryptedAttributes.envelope(Data("content".utf8), recipients: [recipient])
        // ContentInfo { envelopedData, [0] EnvelopedData { version 0, SET
        // OF KeyTransRecipientInfo, EncryptedContentInfo } }.
        let info = try XCTUnwrap(CMSDER.Node.parse([UInt8](envelope)))
        XCTAssertEqual(info.children.first?.oid, "1.2.840.113549.1.7.3")
        let enveloped = try XCTUnwrap(info.children.last?.children.first)
        XCTAssertEqual(enveloped.children.map(\.tag), [0x02, 0x31, 0x30])
        XCTAssertEqual(enveloped.children[2].children[1].children.first?.oid, "2.16.840.1.101.3.4.1.42")
        let key = try _RSA.Encryption.PrivateKey(pemRepresentation: Self.first.key)
        XCTAssertEqual(try DICOMEncryptedAttributes.open([UInt8](envelope), key: key), Data("content".utf8))
    }

    func testDERObjectIdentifiers() {
        for oid in ["1.2.840.113549.1.7.3", "2.16.840.1.101.3.4.1.42", "1.2.840.113549.1.1.7"] {
            XCTAssertEqual(CMSDER.Node.parse(CMSDER.oid(oid))?.oid, oid)
        }
        XCTAssertEqual(CMSDER.integer([0x80]), [0x02, 0x02, 0x00, 0x80])
        XCTAssertEqual(CMSDER.length(300), [0x82, 0x01, 0x2C])
    }
}
