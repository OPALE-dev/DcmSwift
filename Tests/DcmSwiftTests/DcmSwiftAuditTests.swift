import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import NIOCore
import NIOPosix
import XCTest
@testable import DcmSwift

/// Audit messages (PS3.15 A.5) and their syslog transport (A.6, A.7).
final class DcmSwiftAuditTests: XCTestCase {
    private let source = DICOMAuditSource(id: "ARCHIVE")
    private let local = DICOMAuditMessage.ActiveParticipant.application(aeTitles: ["ARCHIVE"], isRequestor: false)
    private let remote = DICOMAuditMessage.ActiveParticipant.node(aeTitle: "MODALITY", host: "10.0.0.5", isRequestor: true)
    private let patient = DICOMAuditMessage.ParticipantObject.patient(id: "P1", name: "Doe^Jane")
    private let study = DICOMAuditMessage.ParticipantObject.study(
        uid: "1.2.3", sopClasses: [.init(uid: "1.2.840.10008.5.1.4.1.1.2", numberOfInstances: 2)])

    private func document(_ message: DICOMAuditMessage) throws -> AuditXMLNode {
        try XCTUnwrap(AuditXMLNode.parse(message.xml()))
    }

    /// The elements at a path of element names; "//Name" finds them at any
    /// depth.
    private func elements(_ root: AuditXMLNode, _ path: String) -> [AuditXMLNode] {
        if path.hasPrefix("//") {
            let name = String(path.dropFirst(2))
            func all(_ element: AuditXMLNode) -> [AuditXMLNode] {
                element.children.filter { $0.name == name } + element.children.flatMap(all)
            }
            return all(root)
        }
        var current = [root]
        for name in path.split(separator: "/") {
            current = current.flatMap { $0.elements(forName: String(name)) }
        }
        return current
    }

    /// The values of an attribute of the elements at a path.
    private func values(_ root: AuditXMLNode, _ path: String, _ attribute: String) -> [String] {
        elements(root, path).compactMap { $0.attributes[attribute] }
    }

    private func codes(_ element: AuditXMLNode, _ path: String) throws -> [String] {
        values(element, path, "csd-code")
    }

    func testEveryMessageHasTheEventAndCodesOfItsTable() throws {
        let messages: [(DICOMAuditMessage, String, String?, [String])] = [
            (.applicationActivity(started: true, application: local, source: source), "110100", "E", ["110120"]),
            (.applicationActivity(started: false, application: local, source: source), "110100", "E", ["110121"]),
            (.auditLogUsed(by: [remote], logURI: "file:///var/log/audit", source: source), "110101", "R", []),
            (.beginTransferring(sender: local, receiver: remote, studies: [study], patient: patient, source: source),
             "110102", "E", []),
            (.dataExport(exporters: [local], media: .init(userID: "DVD", isRequestor: false,
                                                          mediaType: .dcm("110033")),
                         studies: [study], patients: [patient], source: source), "110106", "R", []),
            (.dataImport(importers: [local], media: .init(userID: "file:///import", isRequestor: false),
                         studies: [study], patients: [patient], source: source), "110107", "C", []),
            (.instancesAccessed(action: .update, by: [local], studies: [study], patient: patient, source: source),
             "110103", "U", []),
            (.instancesTransferred(sender: remote, receiver: local, studies: [study], patient: patient, source: source),
             "110104", "C", []),
            (.studyDeleted(by: [local], studies: [study], patient: patient, source: source), "110105", "D", []),
            (.networkEntry(attached: true, node: local, source: source), "110108", "E", ["110124"]),
            (.query(issuer: remote, responder: local, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.1", query: Data([1, 2]),
                    transferSyntaxUID: TransferSyntax.explicitVRLittleEndian, source: source), "110112", "E", []),
            (.securityAlert(type: .dcm("110126"), reporters: [local], subjects: [(id: "10.0.0.9", isURI: false,
                                                                                    description: "rejected")],
                            source: source), "110113", "E", ["110126"]),
            (.userAuthentication(login: false, user: .init(userID: "jane@example.org", isRequestor: true,
                                                            networkAccessPointID: "10.0.0.5",
                                                            networkAccessPointType: .ipAddress), source: source),
             "110114", "E", ["110123"]),
            (.orderRecord(action: .create, by: [local], patient: patient, source: source), "110109", "C", []),
            (.patientRecord(action: .read, by: [local], patient: patient, source: source), "110110", "R", []),
            (.procedureRecord(action: .update, by: [local], studies: [study], patient: patient, source: source),
             "110111", "U", []),
        ]
        for (message, event, action, types) in messages {
            let root = try document(message)
            XCTAssertEqual(root.name, "AuditMessage")
            let identification = try XCTUnwrap(root.elements(forName: "EventIdentification").first)
            XCTAssertEqual(try codes(identification, "EventID"), [event])
            XCTAssertEqual(identification.attributes["EventActionCode"], action, event)
            XCTAssertEqual(try codes(identification, "EventTypeCode"), types, event)
            XCTAssertNotNil(identification.attributes["EventDateTime"])
            // The meaning comes from PS3.16, not the code itself.
            let meaning = values(identification, "EventID", "originalText").first
            XCTAssertEqual(meaning, DICOMTerminology.shared.dicomCode(event)?.meaning)
            XCTAssertFalse(root.elements(forName: "ActiveParticipant").isEmpty)
            XCTAssertEqual(values(root, "AuditSourceIdentification", "AuditSourceID"), ["ARCHIVE"])
            // A.5.2: no empty attribute.
            let xml = String(decoding: message.xml(), as: UTF8.self)
            XCTAssertFalse(xml.contains("=\"\""), event)
        }
    }

    func testTransferMessagesFollowTheirTables() throws {
        let root = try document(.instancesTransferred(
            sender: remote, receiver: local, studies: [study], patient: patient, source: source))
        // Source and destination roles; the study with its SOP Class; the
        // patient with ID type Patient Number.
        XCTAssertEqual(try codes(root, "ActiveParticipant/RoleIDCode"), ["110153", "110152"])
        XCTAssertEqual(values(root, "ActiveParticipant", "AlternativeUserID"), ["AETITLES=MODALITY", "AETITLES=ARCHIVE"])
        XCTAssertEqual(values(root, "ActiveParticipant", "NetworkAccessPointTypeCode").first, "2")
        XCTAssertEqual(try codes(root, "ParticipantObjectIdentification/ParticipantObjectIDTypeCode"), ["110180", "2"])
        XCTAssertEqual(values(root, "ParticipantObjectIdentification", "ParticipantObjectTypeCodeRole"), ["3", "1"])
        XCTAssertEqual(values(root, "//SOPClass", "NumberOfInstances"), ["2"])
        XCTAssertEqual(elements(root, "//ParticipantObjectName").last?.text, "Doe^Jane")

        // Query: the Data Set in base 64, with its Transfer Syntax.
        let query = try document(.query(issuer: remote, responder: local, sopClassUID: "1.2.840.10008.5.1.4.1.2.2.1",
                                        query: Data("query".utf8), transferSyntaxUID: "1.2.840.10008.1.2.1",
                                        source: source))
        XCTAssertEqual(elements(query, "//ParticipantObjectQuery").first?.text,
                       Data("query".utf8).base64EncodedString())
        XCTAssertEqual(values(query, "//ParticipantObjectDetail", "type"), ["TransferSyntax"])
    }

    func testEscapingAndDates() {
        XCTAssertEqual(DICOMAuditMessage.escape("a<b & \"c\"\u{1}"), "a&lt;b &amp; &quot;c&quot;")
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(DICOMAuditMessage.dateTimeString(date), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(DICOMAuditMessage.host(of: "[IPv4]127.0.0.1/127.0.0.1:55432"), "127.0.0.1")
        XCTAssertEqual(DICOMAuditMessage.host(of: "[IPv6]::1/::1:55432"), "::1")
        XCTAssertNil(DICOMAuditMessage.host(of: "unknown"))
    }

    func testSyslogMessage() throws {
        let audit = DICOMAuditMessage.networkEntry(attached: true, node: local, source: source)
        let syslog = DICOMSyslogMessage(audit: audit, hostname: "archive host", appName: "DcmServer", processID: "42",
                                        timestamp: Date(timeIntervalSince1970: 0))
        let encoded = syslog.encoded()
        let header = "<85>1 1970-01-01T00:00:00.000Z archivehost DcmServer 42 DICOM+RFC3881 - "
        XCTAssertEqual(String(decoding: encoded.prefix(header.utf8.count), as: UTF8.self), header)
        XCTAssertEqual(Array(encoded.dropFirst(header.utf8.count).prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(encoded.suffix(audit.xml().count), audit.xml())
    }

    func testUDPSender() async throws {
        let received = AsyncStream<Data>.makeStream()
        let channel = try await DatagramBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(DatagramCollector(continuation: received.continuation))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        defer { channel.close(promise: nil) }
        let port = try XCTUnwrap(channel.localAddress?.port)
        let sender = DICOMAuditSyslogSender(host: "127.0.0.1", port: port, transport: .udp, appName: "DcmSwiftTests")
        try await sender.send(.networkEntry(attached: true, node: local, source: source))
        var iterator = received.stream.makeAsyncIterator()
        let next = await iterator.next()
        let datagram = try XCTUnwrap(next)
        let text = String(decoding: datagram, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("<85>1 "), text)
        XCTAssertTrue(text.contains(" DcmSwiftTests ") && text.contains(" DICOM+RFC3881 - "))
        XCTAssertTrue(text.contains("<EventID csd-code=\"110108\""))
    }

    func testArchiveServicesAudit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dcmswift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = AuditCollector()
        let services = DICOMDirectoryArchiveServices(
            archive: DICOMDirectoryArchive(directory: directory), audit: recorder, auditSource: source)
        let item = try DICOMRetrieveItem(dataSet: DcmSwiftIODValidationTests.secondaryCaptureImage())
        let instance = DICOMReceivedInstance(
            sopClassUID: item.sopClassUID, sopInstanceUID: item.sopInstanceUID, transferSyntaxUID: item.transferSyntaxUID,
            payload: item.payload, moveOriginatorAETitle: nil, moveOriginatorMessageID: nil, sourceAETitle: "")
        let context = DICOMwebRequestContext(remoteAddress: "[IPv4]10.0.0.5/10.0.0.5:4000", baseURI: "/dicomweb")
        _ = try await services.store(instance, context: context)
        _ = try await services.store(instance, context: context)
        let identifier = DataSet()
        _ = identifier.set(value: "", forTagName: "PatientID")
        _ = identifier.set(value: "STUDY", forTagName: "QueryRetrieveLevel")
        _ = try await services.search(identifier, level: .study, query: DICOMwebSearchQuery(), context: context)
        _ = try await services.instances(study: "1.2.826.0.1.3680043.10.1.2", series: nil, instance: nil, context: context)

        let messages = await recorder.messages
        XCTAssertEqual(messages.map(\.eventID.code), ["110104", "110104", "110112", "110104"])
        // Created the first time, read when the archive already held it,
        // read again when retrieved.
        XCTAssertEqual(messages.map { $0.action?.rawValue }, ["C", "R", "E", "R"])
        XCTAssertEqual(messages[0].objects.map(\.id), ["1.2.826.0.1.3680043.10.1.2", "P1"])
        XCTAssertEqual(messages[0].participants.first?.networkAccessPointID, "10.0.0.5")
        XCTAssertEqual(messages[0].objects.first?.descriptions.first?.sopClasses.first?.uid,
                       DcmSwiftIODValidationTests.secondaryCapture)
    }
}

private actor AuditCollector: DICOMAuditRecorder {
    var messages: [DICOMAuditMessage] = []
    func record(_ message: DICOMAuditMessage) { messages.append(message) }
}

private final class DatagramCollector: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    let continuation: AsyncStream<Data>.Continuation

    init(continuation: AsyncStream<Data>.Continuation) {
        self.continuation = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var envelope = unwrapInboundIn(data)
        continuation.yield(Data(envelope.data.readBytes(length: envelope.data.readableBytes) ?? []))
    }
}

/// An element of an XML document, read with XMLParser, which every platform
/// has (XMLDocument is not on iOS).
final class AuditXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [AuditXMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func elements(forName name: String) -> [AuditXMLNode] { children.filter { $0.name == name } }

    static func parse(_ data: Data) -> AuditXMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        return parser.parse() ? builder.root : nil
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: AuditXMLNode?
        var stack: [AuditXMLNode] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let node = AuditXMLNode(name: name, attributes: attributes)
            stack.last?.children.append(node)
            if root == nil { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }
    }
}
