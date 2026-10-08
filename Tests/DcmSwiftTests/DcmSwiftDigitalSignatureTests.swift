import Crypto
import Foundation
import SwiftASN1
import X509
import XCTest
import _CryptoExtras
@testable import DcmSwift

/// Digital Signatures (PS3.3 C.12.1.1.3, PS3.15 Annex C).
final class DcmSwiftDigitalSignatureTests: XCTestCase {
    /// An RSA key and a self-signed certificate for it, as PEM.
    private static let credentials: (key: String, certificate: String) = {
        let key = try! _RSA.Signing.PrivateKey(keySize: .bits2048)
        let privateKey = Certificate.PrivateKey(key)
        let name = try! DistinguishedName { CommonName("DcmSwift Tests") }
        let now = Date()
        let certificate = try! Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: privateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-3600), notValidAfter: now.addingTimeInterval(86400),
            issuer: name, subject: name, signatureAlgorithm: .sha256WithRSAEncryption, extensions: Certificate.Extensions(),
            issuerPrivateKey: privateKey)
        return (key.pemRepresentation, try! certificate.serializeAsPEM().pemString)
    }()

    private func signer(_ algorithm: DICOMMACAlgorithm = .sha256) throws -> DICOMDigitalSigner {
        try DICOMDigitalSigner(privateKeyPEM: Self.credentials.key, certificatePEM: Self.credentials.certificate,
                               algorithm: algorithm)
    }

    func testRIPEMD160() {
        // The test vectors of the RIPEMD-160 specification.
        func hex(_ text: String) -> String {
            RIPEMD160.hash(Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertEqual(hex(""), "9c1185a5c5e9fc54612808977ee8f548b2258d31")
        XCTAssertEqual(hex("abc"), "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc")
        XCTAssertEqual(hex("message digest"), "5d0689ef49d2fae572b881b123a85ffa21595f36")
        XCTAssertEqual(hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "12a053384a9c0c88e405a06c27dcf49ada62eb2b")
    }

    func testRSAPublicOperationMatchesSwiftCrypto() throws {
        // A PKCS #1 v1.5 signature of swift-crypto, opened by the public
        // operation, is 00 01 FF..FF 00 DigestInfo.
        let key = try _RSA.Signing.PrivateKey(pemRepresentation: Self.credentials.key)
        let digest = SHA256.hash(data: Data("DcmSwift".utf8))
        let signature = try key.signature(for: digest, padding: .insecurePKCS1v1_5)
        let (modulus, exponent) = try XCTUnwrap(DICOMSignatureVerification.rsaComponents(Array(key.publicKey.pkcs1DERRepresentation)))
        let opened = try XCTUnwrap(RSAPublicOperation(modulus: modulus, exponent: exponent)?.apply(Array(signature.rawRepresentation)))
        XCTAssertEqual(Array(opened.prefix(2)), [0x00, 0x01])
        XCTAssertEqual(Array(opened.suffix(51)), DICOMMACAlgorithm.sha256.digestInfoPrefix + Array(digest))
    }

    func testSignAndVerify() throws {
        let dataSet = DcmSwiftIODValidationTests.secondaryCaptureImage()
        for algorithm in [DICOMMACAlgorithm.sha1, .sha256, .sha384, .sha512] {
            try signer(algorithm).sign(dataSet)
        }
        let results = DICOMSignatureVerification.verify(dataSet)
        XCTAssertEqual(results.map(\.status), Array(repeating: .valid, count: 4))
        XCTAssertEqual(results.map(\.algorithm), ["SHA1", "SHA256", "SHA384", "SHA512"])
        XCTAssertEqual(results.first?.signer, "CN=DcmSwift Tests")
        XCTAssertTrue(results.first?.signedTags.contains("7FE00010") ?? false)
        // The macro's own sequences are not signed.
        XCTAssertFalse(results.first?.signedTags.contains("4FFE0001") ?? true)
        let parameters = dataSet.datasetElements.first { $0.tagCode().uppercased() == "4FFE0001" } as? DataSequence
        XCTAssertEqual(parameters?.items.count, 4)

        // Changing a signed attribute breaks every signature.
        _ = dataSet.set(value: "Doe^John", forTagName: "PatientName")
        XCTAssertEqual(DICOMSignatureVerification.verify(dataSet).map(\.status), Array(repeating: .invalid, count: 4))
    }

    func testSignSomeTagsAndItems() throws {
        let dataSet = DcmSwiftIODValidationTests.secondaryCaptureImage()
        try signer().sign(dataSet, tags: ["00080016", "00080018", "7FE00010"])
        // Attributes outside the signed list may change.
        _ = dataSet.set(value: "Doe^John", forTagName: "PatientName")
        XCTAssertEqual(DICOMSignatureVerification.verify(dataSet).map(\.signedTags), [["00080016", "00080018", "7FE00010"]])
        XCTAssertEqual(DICOMSignatureVerification.verify(dataSet).map(\.status), [.valid])
        XCTAssertThrowsError(try signer().sign(dataSet, tags: ["00189999"]), "absent attribute")

        // A Sequence Item signed on its own, and the Sequence signed with
        // the data set: both cover the Item's attributes.
        let sequence = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: "ReferencedInstanceSequence")))
        sequence.vr = .SQ
        sequence.length = -1
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        let uid = try XCTUnwrap(DataElement(withTagName: "ReferencedSOPInstanceUID", dataset: dataSet, parent: item))
        uid.vr = .UI
        XCTAssertTrue(uid.setValue("1.2.3.4"))
        item.elements.append(uid)
        sequence.items.append(item)
        dataSet.add(element: sequence)
        try signer().sign(item, dataSet: dataSet)
        try signer().sign(dataSet, tags: ["0008114A"])
        let results = DICOMSignatureVerification.verify(dataSet)
        XCTAssertEqual(results.map(\.path), [[], [], ["0008114A"]])
        XCTAssertEqual(results.map(\.status), [.valid, .valid, .valid])
        XCTAssertTrue(uid.setValue("1.2.3.5"))
        XCTAssertEqual(DICOMSignatureVerification.verify(dataSet).map(\.status), [.valid, .invalid, .invalid])
    }

    func testRefusals() throws {
        XCTAssertThrowsError(try signer(.md5))
        XCTAssertThrowsError(try signer(.ripemd160))
        // A certificate that does not hold the key's public key.
        let other = try _RSA.Signing.PrivateKey(keySize: .bits2048).pemRepresentation
        XCTAssertThrowsError(try DICOMDigitalSigner(privateKeyPEM: other, certificatePEM: Self.credentials.certificate))
        // Without signatures, nothing to verify.
        XCTAssertTrue(DICOMSignatureVerification.verify(DcmSwiftIODValidationTests.secondaryCaptureImage()).isEmpty)
        XCTAssertTrue(DICOMSignatureVerification.verify(DataSet()).isEmpty)
    }
}
