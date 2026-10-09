//
//  DcmServer.swift
//
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import ArgumentParser
import DcmNetworkCommand
import DcmSwift
import Foundation

/// `DcmServer` is an SCP for verification and, with a storage directory,
/// for storage and query/retrieve over the instances in that directory.
@main
struct DcmServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Serve verification, storage, query/retrieve, Storage Commitment, Modality Worklist, and MPPS.",
        discussion: """
            Without --storage-directory, only C-ECHO is served. With it, received instances are written \
            there as <SOPInstanceUID>.dcm, in their received transfer syntax, and the Part 10 files found \
            there at start-up and received later answer C-FIND, C-MOVE, and C-GET. Storage Commitment \
            commits the instances present in the directory; results go on the requesting association, \
            or to the --destination of the requestor's AE title once it is released. With --http-port, \
            the same directory is also served over DICOMweb (QIDO-RS, WADO-RS, STOW-RS), with TLS when \
            --tls-certificate is given. With --worklist-directory, the worklist items found there at each \
            query (Part 10 files, bare data sets such as DCMTK .wl files, or DICOM JSON) answer Modality \
            Worklist C-FIND. With --mpps-directory, Modality Performed Procedure Steps are created, \
            set, and retrieved, kept there as DICOM JSON, and notified to each --mpps-notify AE. \
            Each --ian-destination receives an Instance Availability Notification for the instances \
            stored, per study, once none has arrived for --ian-delay seconds; with --ian-directory, \
            notifications are also received and kept there. With --event-log-directory, procedural \
            and substance administration events (Application Event Logging) are checked and kept there.
            """)

    @Option(name: .shortAndLong, help: "Local AE title.")
    var aet = "DCMSERVER"

    @Option(name: .long, help: "Address to listen on.")
    var host = "0.0.0.0"

    @Option(name: .shortAndLong, help: "Port to listen on.")
    var port = 11112

    @Option(name: .shortAndLong, help: "Directory where instances are stored and retrieved from.")
    var storageDirectory: String?

    @Option(name: .long, help: "Directory of Modality Worklist items, read at each query.")
    var worklistDirectory: String?

    @Option(name: .long, help: "Directory of Modality Performed Procedure Steps, kept as DICOM JSON.")
    var mppsDirectory: String?

    @Option(name: .long, help: "An SCU of MPPS notifications, as AET=host:port; repeatable.")
    var mppsNotify: [String] = []

    @Option(name: .long, help: "An SCP of Instance Availability Notification, as AET=host:port; repeatable.")
    var ianDestination: [String] = []

    @Option(name: .long, help: "Seconds without a new instance of a study before its availability is notified.")
    var ianDelay: Double = 5

    @Option(name: .long, help: "Directory where received Instance Availability Notifications are kept.")
    var ianDirectory: String?

    @Option(name: .long, help: "Directory where Application Event Logging events are kept.")
    var eventLogDirectory: String?

    @Option(name: .long, help: "Port of the DICOMweb service over the storage directory (default: none).")
    var httpPort: Int?

    @Option(name: .long, help: "Path of the DICOMweb service.")
    var httpBasePath = "/dicomweb"

    @Option(name: .long, help: "Scheme and authority of the DICOMweb service in Retrieve URLs, such as https://pacs.example.org (default: from the Host header).")
    var httpPublicOrigin: String?

    @Option(name: .customLong("validate"), help: "What to do with received instances that do not conform to their IOD in PS3.3: off, warn (store, Status B007), or reject (Status A900).")
    var validationPolicy: DICOMIODValidationPolicy = .off

    @Option(name: .long, help: "A C-MOVE destination or Storage Commitment SCU, as AET=host:port; repeatable.")
    var destination: [String] = []

    @Option(name: .long, help: "A calling AE title allowed to associate; repeatable (default: any).")
    var allowCallingAET: [String] = []

    @Flag(name: .long, help: "Accept associations whatever the called AE title.")
    var acceptAnyCalledAET = false

    @Option(name: .long, help: "Associations served at once.")
    var maxAssociations = 32

    @Flag(name: .long, help: "Reach C-MOVE destinations with TLS.")
    var destinationTLS = false

    @Option(name: .customLong("destination-tls-ca"), help: "PEM file of the CA certificates trusted for C-MOVE destinations.")
    var destinationTLSCA: String?

    @Option(name: .long, help: "PEM certificate chain presented to C-MOVE destinations.")
    var destinationTLSCertificate: String?

    @Option(name: .long, help: "PEM private key of --destination-tls-certificate.")
    var destinationTLSKey: String?

    @Option(name: .long, help: "Syslog collector of audit messages (PS3.15 A.5), as tls://host[:6514] or udp://host[:514]; repeatable.")
    var audit: [String] = []

    @Option(name: .customLong("audit-tls-ca"), help: "PEM file of the CA certificates trusted for tls:// audit collectors (default: the system's).")
    var auditTLSCA: String?

    @Option(name: .long, help: "PEM certificate chain presented to tls:// audit collectors.")
    var auditTLSCertificate: String?

    @Option(name: .long, help: "PEM private key of --audit-tls-certificate.")
    var auditTLSKey: String?

    @Option(name: .long, help: "AuditSourceID of the audit messages (default: the AE title).")
    var auditSourceID: String?

    @OptionGroup var network: NetworkOptions
    @OptionGroup var tls: ServerTLSOptions

    func validate() throws {
        guard DICOMApplicationEntityTitle.isValid(aet) else { throw ValidationError("invalid AE title \(aet)") }
        guard (0...65535).contains(port) else { throw ValidationError("invalid port \(port)") }
        guard maxAssociations >= 1 else { throw ValidationError("--max-associations must be at least 1") }
        _ = try destinations()
        _ = try Self.nodes(mppsNotify, option: "--mpps-notify", tls: false)
        _ = try Self.nodes(ianDestination, option: "--ian-destination", tls: false)
        if !ianDestination.isEmpty, storageDirectory == nil {
            throw ValidationError("--ian-destination needs --storage-directory")
        }
        guard ianDelay >= 0 else { throw ValidationError("--ian-delay cannot be negative") }
        if !mppsNotify.isEmpty, mppsDirectory == nil { throw ValidationError("--mpps-notify needs --mpps-directory") }
        if !destination.isEmpty, storageDirectory == nil {
            throw ValidationError("--destination needs --storage-directory")
        }
        if let httpPort {
            guard storageDirectory != nil else { throw ValidationError("--http-port needs --storage-directory") }
            guard (0...65535).contains(httpPort) else { throw ValidationError("invalid HTTP port \(httpPort)") }
        }
        if !destinationTLS, destinationTLSCA != nil || destinationTLSCertificate != nil || destinationTLSKey != nil {
            throw ValidationError("destination TLS options need --destination-tls")
        }
        _ = try auditCollectors()
    }

    /// The collectors of --audit, as (TLS, host, port).
    func auditCollectors() throws -> [(tls: Bool, host: String, port: Int?)] {
        try audit.map { value in
            guard let components = URLComponents(string: value), let scheme = components.scheme,
                  ["tls", "udp"].contains(scheme), let host = components.host, !host.isEmpty else {
                throw ValidationError("--audit expects tls://host[:port] or udp://host[:port], not \(value)")
            }
            return (scheme == "tls", host, components.port)
        }
    }

    func auditRecorder() throws -> DICOMAuditRecorder? {
        let collectors = try auditCollectors()
        guard !collectors.isEmpty else { return nil }
        return DICOMAuditRecorders(try collectors.map { collector in
            let transport: DICOMAuditSyslogSender.Transport = collector.tls
                ? .tls(try DICOMTLSConfiguration.client(
                    pemTrustRootsFile: auditTLSCA, pemCertificateChainFile: auditTLSCertificate,
                    pemPrivateKeyFile: auditTLSKey))
                : .udp
            return DICOMAuditSyslogSender(host: collector.host, port: collector.port, transport: transport,
                                          appName: "DcmServer")
        })
    }

    func destinations() throws -> [String: DICOMRemoteNode] {
        Dictionary(try Self.nodes(destination, option: "--destination", tls: destinationTLS).map { ($0.aeTitle, $0) },
                   uniquingKeysWith: { _, last in last })
    }

    /// Nodes given as AET=host:port.
    static func nodes(_ values: [String], option: String, tls: Bool) throws -> [DICOMRemoteNode] {
        try values.map { value in
            let parts = value.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let colon = parts[1].lastIndex(of: ":"),
                  let port = Int(parts[1][parts[1].index(after: colon)...]), (1...65535).contains(port),
                  DICOMApplicationEntityTitle.isValid(String(parts[0])) else {
                throw ValidationError("\(option) expects AET=host:port, not \(value)")
            }
            return DICOMRemoteNode(aeTitle: String(parts[0]), host: String(parts[1][..<colon]), port: port, useTLS: tls)
        }
    }

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let logger = network.logger(label: "dcmserver")
        var configuration = DICOMServerConfiguration(
            aeTitle: aet, host: host, port: port, acceptsAnyCalledAETitle: acceptAnyCalledAET,
            allowedCallingAETitles: allowCallingAET.isEmpty ? nil : Set(allowCallingAET),
            maximumAssociations: maxAssociations, limits: network.limits, timeouts: network.timeouts,
            tls: try tls.configuration(), clientTLS: destinationTLS ? try DICOMTLSConfiguration.client(
                pemTrustRootsFile: destinationTLSCA, pemCertificateChainFile: destinationTLSCertificate,
                pemPrivateKeyFile: destinationTLSKey) : nil,
            logger: logger)
        configuration.logger.logLevel = network.verbose ? .debug : .info
        let audit = try auditRecorder()
        let auditSource = DICOMAuditSource(id: auditSourceID ?? aet)
        configuration.audit = audit
        configuration.auditSource = auditSource

        let worklist = worklistDirectory.map {
            DICOMModalityWorklist(directory: URL(fileURLWithPath: $0, isDirectory: true))
        }
        if let directory = worklist?.directory {
            print("\(DICOMModalityWorklist.items(in: directory).count) worklist items in \(directory.path)")
        }
        var normalized: [String: DICOMNormalizedService] = [:]
        if let mppsDirectory {
            let directory = URL(fileURLWithPath: mppsDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let recipients = try Self.nodes(mppsNotify, option: "--mpps-notify", tls: false)
            let notifier = recipients.isEmpty ? nil : DICOMPerformedProcedureStepNotifier(
                client: try DICOMClient(configuration: DICOMClientConfiguration(
                    aeTitle: aet, limits: network.limits, timeouts: network.timeouts, logger: logger)),
                recipients: recipients)
            let service = DICOMPerformedProcedureStepService(index: DICOMFileArchiveIndex(directory: directory)) { event, uid, _ in
                await notifier?.send(event, instance: uid)
            }
            for sopClass in DICOMPerformedProcedureStepService.sopClasses { normalized[sopClass] = service }
            print("\(try await service.instanceUIDs().count) performed procedure steps in \(directory.path)")
        }
        if let ianDirectory {
            let index = DICOMFileArchiveIndex(directory: URL(fileURLWithPath: ianDirectory, isDirectory: true))
            normalized[DICOMSOPClass.instanceAvailabilityNotification] = DICOMInstanceAvailabilityService(index: index) {
                notification, context in
                let count = notification.series.reduce(0) { $0 + $1.instances.count }
                print("\(context.callingAETitle): \(count) instances available in study \(notification.studyInstanceUID)")
            }
        }
        if let eventLogDirectory {
            let service = DICOMEventLoggingService(
                index: DICOMFileArchiveIndex(directory: URL(fileURLWithPath: eventLogDirectory, isDirectory: true))
            ) { sopClass, _, context in
                let kind = sopClass == DICOMSOPClass.proceduralEventLogging ? "procedural event" : "substance administration"
                print("\(context.callingAETitle): \(kind) logged")
            }
            for sopClass in DICOMEventLoggingService.sopClasses { normalized[sopClass] = service }
        }
        let ianRecipients = try Self.nodes(ianDestination, option: "--ian-destination", tls: false)
        let availability = ianRecipients.isEmpty ? nil : DICOMInstanceAvailabilityNotifier(
            client: try DICOMClient(configuration: DICOMClientConfiguration(
                aeTitle: aet, limits: network.limits, timeouts: network.timeouts, logger: logger)),
            recipients: ianRecipients, retrieveAETitle: aet, delay: ianDelay)
        let server: DICOMServer
        var web: DICOMwebServer?
        if let storageDirectory {
            let directory = URL(fileURLWithPath: storageDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let archive = DICOMArchive(directory: directory)
            let indexed = try await archive.scan()
            print("\(indexed) instances in \(directory.path)")
            let services = DICOMArchiveServices(
                archive: archive, destinations: try destinations(), validation: validationPolicy, audit: audit,
                auditSource: auditSource, availability: availability)
            server = try DICOMServer(
                configuration: configuration, storage: services, query: services, worklist: worklist,
                retrieve: services, storageCommitment: services, normalized: normalized)
            if let httpPort {
                var network = DICOMwebServerNetworkConfiguration(
                    host: host, port: httpPort, tls: try tls.configuration(), publicOrigin: httpPublicOrigin, logger: logger)
                network.logger.logLevel = configuration.logger.logLevel
                web = try DICOMwebServer(
                    origin: DICOMwebOriginServer(configuration: .init(basePath: httpBasePath),
                                                 search: services, retrieve: services, store: services),
                    network: network)
            }
        } else {
            server = try DICOMServer(configuration: configuration, worklist: worklist, normalized: normalized)
        }
        let banner = "\(configuration.aeTitle) listening on \(configuration.host)"
        let secure = configuration.tls != nil ? " (TLS)" : ""
        let basePath = httpBasePath
        let application = DICOMAuditMessage.ActiveParticipant.application(aeTitles: [aet], isRequestor: false)
        let user = DICOMAuditMessage.ActiveParticipant(userID: NSUserName(), isRequestor: true)
        await audit?.record(.applicationActivity(started: true, application: application, launchers: [user],
                                                 source: auditSource))
        func stopped() async {
            await audit?.record(.applicationActivity(started: false, application: application, launchers: [user],
                                                     source: auditSource))
        }
        // SIGINT and SIGTERM stop the services, so that the stop is audited.
        let services = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await server.run { port in
                        print("\(banner):\(port)\(secure)")
                    }
                }
                if let web {
                    group.addTask {
                        try await web.run { port in
                            let scheme = web.network.tls != nil ? "https" : "http"
                            print("DICOMweb at \(scheme)://\(web.network.host):\(port)\(basePath)")
                        }
                    }
                }
                // The first service to stop stops the other.
                try await group.next()
                group.cancelAll()
            }
        }
        var signals: [DispatchSourceSignal] = []
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number)
            source.setEventHandler { services.cancel() }
            source.resume()
            signals.append(source)
        }
        defer { signals.forEach { $0.cancel() } }
        do {
            try await services.value
        } catch is CancellationError {
        } catch {
            await stopped()
            throw error
        }
        await stopped()
    }
}

extension DICOMIODValidationPolicy: ExpressibleByArgument {}
