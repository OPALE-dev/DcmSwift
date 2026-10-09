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
        abstract: "Serve verification, storage, query/retrieve, Storage Commitment, and Modality Worklist.",
        discussion: """
            Without --storage-directory, only C-ECHO is served. With it, received instances are written \
            there as <SOPInstanceUID>.dcm, in their received transfer syntax, and the Part 10 files found \
            there at start-up and received later answer C-FIND, C-MOVE, and C-GET. Storage Commitment \
            commits the instances present in the directory; results go on the requesting association, \
            or to the --destination of the requestor's AE title once it is released. With --http-port, \
            the same directory is also served over DICOMweb (QIDO-RS, WADO-RS, STOW-RS), with TLS when \
            --tls-certificate is given. With --worklist-directory, the worklist items found there at each \
            query (Part 10 files, bare data sets such as DCMTK .wl files, or DICOM JSON) answer Modality \
            Worklist C-FIND.
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
        var nodes: [String: DICOMRemoteNode] = [:]
        for value in destination {
            let parts = value.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let colon = parts[1].lastIndex(of: ":"),
                  let port = Int(parts[1][parts[1].index(after: colon)...]), (1...65535).contains(port),
                  DICOMApplicationEntityTitle.isValid(String(parts[0])) else {
                throw ValidationError("--destination expects AET=host:port, not \(value)")
            }
            let title = String(parts[0])
            nodes[title] = DICOMRemoteNode(
                aeTitle: title, host: String(parts[1][..<colon]), port: port, useTLS: destinationTLS)
        }
        return nodes
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
        let server: DICOMServer
        var web: DICOMwebServer?
        if let storageDirectory {
            let directory = URL(fileURLWithPath: storageDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let archive = DICOMDirectoryArchive(directory: directory)
            let indexed = await archive.scan()
            print("\(indexed) instances in \(directory.path)")
            let services = DICOMDirectoryArchiveServices(
                archive: archive, destinations: try destinations(), validation: validationPolicy, audit: audit,
                auditSource: auditSource)
            server = try DICOMServer(
                configuration: configuration, storage: services, query: services, worklist: worklist,
                retrieve: services, storageCommitment: services)
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
            server = try DICOMServer(configuration: configuration, worklist: worklist)
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
