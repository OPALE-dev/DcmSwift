import XCTest
import NIOCore
import NIOPosix
import NIOSSL
import NIOConcurrencyHelpers
@testable import DcmSwift

/// DICOM over TLS on the loopback interface (PS3.15 B.12, B.13), with the
/// test certificates of `Scripts/generate-tls-test-certificates.sh`.
final class DcmSwiftNetworkTLSTests: XCTestCase {
    private func pem(_ name: String) throws -> String {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "pem")).path
    }

    private var timeouts: DICOMNetworkTimeouts {
        DICOMNetworkTimeouts(connect: .seconds(5), artim: .seconds(2), idle: .seconds(10))
    }

    /// A TLS server presenting `certificate`; with `clientCA`, it requires
    /// client certificates.
    private func server(
        certificate: String = "tls-server", clientCA: String? = nil, storage: DICOMStorageService? = nil,
        retrieve: DICOMRetrieveService? = nil, clientTLS: DICOMTLSConfiguration? = nil, aeTitle: String = "SCP"
    ) throws -> DICOMServer {
        try DICOMServer(
            configuration: DICOMServerConfiguration(
                aeTitle: aeTitle, host: "127.0.0.1", port: 0, timeouts: timeouts,
                tls: DICOMTLSConfiguration.server(
                    pemCertificateChainFile: pem(certificate), pemPrivateKeyFile: pem(certificate + "-key"),
                    pemClientTrustRootsFile: try clientCA.map(pem)),
                clientTLS: clientTLS),
            storage: storage, retrieve: retrieve)
    }

    private func clientTLS(
        ca: String = "tls-ca", certificate: String? = nil, verification: CertificateVerification = .fullVerification
    ) throws -> DICOMTLSConfiguration {
        try DICOMTLSConfiguration.client(
            pemTrustRootsFile: pem(ca), pemCertificateChainFile: try certificate.map(pem),
            pemPrivateKeyFile: try certificate.map { try pem($0 + "-key") }, verification: verification)
    }

    private func withServer<T>(_ server: DICOMServer, _ body: (Int) async throws -> T) async throws -> T {
        let ready = AsyncStream<Int>.makeStream()
        let task = Task { try await server.run { ready.continuation.yield($0) } }
        var iterator = ready.stream.makeAsyncIterator()
        guard let port = await iterator.next() else { throw DICOMNetworkError.connectionClosed }
        defer { task.cancel() }
        let result = try await body(port)
        task.cancel()
        _ = try? await task.value
        return result
    }

    /// C-ECHO over TLS; returns the peer certificate the client saw.
    @discardableResult
    private func echo(
        port: Int, tls: DICOMTLSConfiguration?, host: String = "127.0.0.1", useTLS: Bool = true
    ) async throws -> NIOSSLCertificate? {
        let client = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "SCU", timeouts: timeouts, tls: tls))
        return try await client.withAssociation(
            to: DICOMRemoteNode(aeTitle: "SCP", host: host, port: port, useTLS: useTLS),
            presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.verification])
        ) { association in
            let status = try await association.echo()
            XCTAssertEqual(status, .success)
            return association.peerCertificate
        }
    }

    private func assertTLSFailure(
        _ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("TLS connection accepted", file: file, line: line)
        } catch let error as DICOMNetworkError {
            switch error {
            case .tls, .connectionClosed, .associationAborted: break
            default: XCTFail("unexpected \(error)", file: file, line: line)
            }
        } catch is NIOSSLError {
            // Trust roots that cannot be loaded (no system bundle on Linux).
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    // MARK: Tests

    func testProfileRestrictsVersionsAndCipherSuites() throws {
        for configuration in [try clientTLS().configuration, try DICOMTLSConfiguration.server(
            pemCertificateChainFile: pem("tls-server"), pemPrivateKeyFile: pem("tls-server-key")).configuration] {
            XCTAssertEqual(configuration.minimumTLSVersion, .tlsv12)
            XCTAssertEqual(configuration.maximumTLSVersion, .tlsv13)
            XCTAssertEqual(configuration.cipherSuiteValues, DICOMTLSConfiguration.cipherSuites)
        }
        // ECDHE with AEAD only (B.13): no CBC, RSA key exchange, or SHA-1.
        for cipher in DICOMTLSConfiguration.cipherSuites {
            XCTAssertTrue([0xC02B, 0xC02C, 0xC02F, 0xC030, 0xCCA8, 0xCCA9].contains(cipher.rawValue), "\(cipher)")
        }
        XCTAssertEqual(try clientTLS().configuration.certificateVerification, .fullVerification)
        XCTAssertThrowsError(try DICOMTLSConfiguration.client(
            pemTrustRootsFile: nil, pemCertificateChainFile: pem("tls-client"), pemPrivateKeyFile: nil))
    }

    func testEchoOverTLSVerifiesTheServer() async throws {
        try await withServer(try server()) { port in
            let certificate = try await echo(port: port, tls: try clientTLS())
            XCTAssertEqual(certificate, try NIOSSLCertificate.fromPEMFile(try pem("tls-server")).first)
            // By host name, against the DNS subject alternative name.
            try await echo(port: port, tls: try clientTLS(), host: "localhost")
            // TLS 1.2 is still accepted.
            var tls12 = try clientTLS()
            tls12.configuration.maximumTLSVersion = .tlsv12
            try await echo(port: port, tls: tls12)
        }
    }

    func testUntrustedWrongHostAndExpiredServersAreRefused() async throws {
        try await withServer(try server()) { port in
            await assertTLSFailure { try await self.echo(port: port, tls: try self.clientTLS(ca: "tls-other-ca")) }
            // The system roots do not include the test CA.
            await assertTLSFailure {
                try await self.echo(port: port, tls: DICOMTLSConfiguration.client())
            }
        }
        try await withServer(try server(certificate: "tls-wrong-host")) { port in
            await assertTLSFailure { try await self.echo(port: port, tls: try self.clientTLS()) }
            // Accepted when host name verification is explicitly relaxed.
            try await echo(port: port, tls: try clientTLS(verification: .noHostnameVerification))
        }
        try await withServer(try server(certificate: "tls-expired")) { port in
            await assertTLSFailure { try await self.echo(port: port, tls: try self.clientTLS()) }
        }
    }

    func testTLSFailuresAreReportedAsTLSErrors() async throws {
        try await withServer(try server()) { port in
            do {
                try await echo(port: port, tls: try clientTLS(ca: "tls-other-ca"))
                XCTFail("untrusted server accepted")
            } catch DICOMNetworkError.tls(let message) {
                XCTAssertFalse(message.isEmpty)
            }
        }
    }

    func testProtocolVersionsAndCipherSuitesOutsideTheProfileAreRefused() async throws {
        try await withServer(try server()) { port in
            // A client limited to TLS 1.1.
            var old = try clientTLS()
            old.configuration.minimumTLSVersion = .tlsv1
            old.configuration.maximumTLSVersion = .tlsv11
            await assertTLSFailure { try await self.echo(port: port, tls: old) }
            // A TLS 1.2 client offering only a CBC suite with SHA-1.
            var cbc = try clientTLS()
            cbc.configuration.maximumTLSVersion = .tlsv12
            cbc.configuration.cipherSuiteValues = [.TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA]
            await assertTLSFailure { try await self.echo(port: port, tls: cbc) }
            // The server still serves conformant clients.
            try await echo(port: port, tls: try clientTLS())
        }
    }

    func testMutualAuthentication() async throws {
        /// Records the client certificate services see.
        final class Recorder: DICOMStorageService, @unchecked Sendable {
            let certificates = NIOLockedValueBox<[NIOSSLCertificate?]>([])
            func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
                certificates.withLockedValue { $0.append(context.peerCertificate) }
                return .success
            }
        }
        let recorder = Recorder()
        try await withServer(try server(clientCA: "tls-ca", storage: recorder)) { port in
            // No client certificate, or one from another CA.
            await assertTLSFailure { try await self.echo(port: port, tls: try self.clientTLS()) }
            await assertTLSFailure {
                try await self.echo(port: port, tls: try self.clientTLS(certificate: "tls-untrusted-client"))
            }
            // A certificate from the trusted CA.
            let tls = try clientTLS(certificate: "tls-client")
            try await echo(port: port, tls: tls)
            let dataSet = DataSet()
            _ = dataSet.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "SOPClassUID")
            _ = dataSet.set(value: "1.2.826.0.1.96.1", forTagName: "SOPInstanceUID")
            let client = try DICOMClient(configuration: DICOMClientConfiguration(aeTitle: "SCU", timeouts: timeouts, tls: tls))
            try await client.withAssociation(
                to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port, useTLS: true),
                presentationContexts: .proposals(abstractSyntaxes: ["1.2.840.10008.5.1.4.1.1.7"])
            ) { association in
                let status = try await association.store(dataSet)
                XCTAssertEqual(status, .success)
            }
        }
        let expected = try NIOSSLCertificate.fromPEMFile(try pem("tls-client")).first
        XCTAssertEqual(recorder.certificates.withLockedValue { $0 }, [expected])
    }

    func testPlainPeersAndTLSServersDoNotMix() async throws {
        try await withServer(try server()) { port in
            // A plain TCP requestor gets no association from a TLS server,
            // and learns why from the TLS alert.
            do {
                try await echo(port: port, tls: nil, useTLS: false)
                XCTFail("plain requestor accepted")
            } catch DICOMNetworkError.tls(let message) {
                XCTAssertTrue(message.contains("expects TLS"), message)
            }
            // A remote node marked TLS needs a TLS configuration.
            do {
                try await echo(port: port, tls: nil, useTLS: true)
                XCTFail("TLS node without configuration")
            } catch DICOMNetworkError.invalidState {}
            try await echo(port: port, tls: try clientTLS())
        }
        // A TLS requestor to a plain server.
        let plain = try DICOMServer(configuration: DICOMServerConfiguration(
            aeTitle: "SCP", host: "127.0.0.1", port: 0, timeouts: timeouts))
        try await withServer(plain) { port in
            await assertTLSFailure { try await self.echo(port: port, tls: try self.clientTLS()) }
            try await echo(port: port, tls: nil, useTLS: false)
        }
    }

    func testMoveToATLSDestination() async throws {
        struct Fixed: DICOMRetrieveService {
            let items: [DICOMRetrieveItem]
            let destination: DICOMRemoteNode
            func retrieve(_ identifier: DataSet, informationModel: String, context: DICOMServiceContext)
                async throws -> [DICOMRetrieveItem] { items }
            func destination(for aeTitle: String) async -> DICOMRemoteNode? { aeTitle == "DEST" ? destination : nil }
        }
        final class Count: DICOMStorageService, @unchecked Sendable {
            let count = NIOLockedValueBox(0)
            func store(_ instance: DICOMReceivedInstance, context: DICOMServiceContext) async throws -> DICOMStatus {
                count.withLockedValue { $0 += 1 }
                return .success
            }
        }
        let dataSet = DataSet()
        _ = dataSet.set(value: "1.2.840.10008.5.1.4.1.1.7", forTagName: "SOPClassUID")
        _ = dataSet.set(value: "1.2.826.0.1.96.2", forTagName: "SOPInstanceUID")
        let item = try DICOMRetrieveItem(dataSet: dataSet)
        let received = Count()
        // The destination requires client certificates; the archive presents
        // its own when it opens the C-MOVE association.
        try await withServer(try server(clientCA: "tls-ca", storage: received, aeTitle: "DEST")) { destinationPort in
            let archive = try server(
                retrieve: Fixed(items: [item], destination: DICOMRemoteNode(
                    aeTitle: "DEST", host: "127.0.0.1", port: destinationPort, useTLS: true)),
                clientTLS: try clientTLS(certificate: "tls-client"))
            try await withServer(archive) { port in
                let client = try DICOMClient(configuration: DICOMClientConfiguration(
                    aeTitle: "SCU", timeouts: timeouts, tls: try clientTLS()))
                let result = try await client.withAssociation(
                    to: DICOMRemoteNode(aeTitle: "SCP", host: "127.0.0.1", port: port, useTLS: true),
                    presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.studyRootMove])
                ) { association in
                    let identifier = DataSet()
                    _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
                    return try await association.move(identifier, destination: "DEST")
                }
                XCTAssertEqual(result.status, .success)
                XCTAssertEqual(result.progress.completed, 1)
            }
        }
        XCTAssertEqual(received.count.withLockedValue { $0 }, 1)
    }
}
