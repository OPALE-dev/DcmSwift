//
//  DcmEcho.swift
//
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import ArgumentParser
import DcmNetworkCommand
import DcmSwift
import Foundation

/// `DcmEcho` is a Verification SCU (PS3.4 Annex A): it sends C-ECHO
/// requests to a remote AE.
@main
struct DcmEcho: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send C-ECHO requests to a remote AE (Verification SCU).",
        discussion: "Exits with status 1 if the association or any C-ECHO fails.")

    @OptionGroup var remote: RemoteOptions
    @OptionGroup var network: NetworkOptions
    @OptionGroup var tls: ClientTLSOptions

    @Option(name: .long, help: "Number of C-ECHO requests on the association.")
    var `repeat` = 1

    func validate() throws {
        guard `repeat` >= 1 else { throw ValidationError("--repeat must be at least 1") }
    }

    func run() async throws {
        let client = try DICOMClient(configuration: DICOMClientConfiguration(
            aeTitle: remote.callingAET, limits: network.limits, timeouts: network.timeouts,
            tls: try tls.configuration(), logger: network.logger(label: "dcmecho")))
        let start = Date()
        do {
            let statuses = try await client.withAssociation(
                to: remote.node(tls: tls.tls),
                presentationContexts: .proposals(abstractSyntaxes: [DICOMSOPClass.verification])
            ) { association in
                var statuses: [DICOMStatus] = []
                for _ in 0..<`repeat` { statuses.append(try await association.echo()) }
                return statuses
            }
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let failed = statuses.filter { !$0.isSuccess }
            if failed.isEmpty {
                print("C-ECHO \(remote.description): success (\(statuses.count) in \(elapsed) ms)")
            } else {
                printError("C-ECHO \(remote.description): \(failed.count) of \(statuses.count) failed, status \(failed[0])")
                throw ExitCode.failure
            }
        } catch let exit as ExitCode {
            throw exit
        } catch {
            printError("C-ECHO \(remote.description) failed: \(error.commandLineDescription)")
            throw ExitCode.failure
        }
    }
}
