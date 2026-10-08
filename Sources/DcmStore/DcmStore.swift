//
//  DcmStore.swift
//
//
//  Created by Rafael Warnault, OPALE on 25/06/2021.
//

import ArgumentParser
import DcmNetworkCommand
import DcmSwift
import Foundation

/// `DcmStore` is a Storage SCU (PS3.4 Annex B): it sends Part 10 files to a
/// remote AE by C-STORE, streamed from disk in their own transfer syntax.
@main
struct DcmStore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send DICOM files to a remote AE (Storage SCU).",
        discussion: """
            Directories are searched recursively. Each file is sent in its own transfer syntax, \
            or converted between uncompressed syntaxes when the remote AE accepts only those. \
            Exits with status 1 if any file is not stored.
            """)

    @OptionGroup var remote: RemoteOptions

    @Argument(help: "Files and directories to send.")
    var paths: [String]

    @OptionGroup var network: NetworkOptions
    @OptionGroup var tls: ClientTLSOptions

    func run() async throws {
        var items: [(path: String, item: DICOMRetrieveItem)] = []
        var skipped = 0
        for path in Self.files(in: paths) {
            do {
                items.append((path, try DICOMRetrieveItem(file: URL(fileURLWithPath: path))))
            } catch {
                skipped += 1
                if network.verbose { printError("skipping \(path): \(error)") }
            }
        }
        guard !items.isEmpty else {
            printError("no DICOM Part 10 file to send" + (skipped > 0 ? " (\(skipped) skipped)" : ""))
            throw ExitCode.failure
        }

        let client = try DICOMClient(configuration: DICOMClientConfiguration(
            aeTitle: remote.callingAET, limits: network.limits, timeouts: network.timeouts,
            tls: try tls.configuration(), logger: network.logger(label: "dcmstore")))
        var stored = 0, warnings = 0, failed = 0
        for batch in Self.batches(items) {
            do {
                try await client.withAssociation(
                    to: remote.node(tls: tls.tls),
                    presentationContexts: DICOMPresentationContextProposal.proposals(for: batch.map(\.item))
                ) { association in
                    for (path, item) in batch {
                        do {
                            let status = try await association.store(item)
                            switch status.category {
                            case .success:
                                stored += 1
                                if network.verbose { print("stored \(path)") }
                            case .warning:
                                warnings += 1
                                print("stored \(path) with warning \(status)")
                            default:
                                failed += 1
                                printError("failed \(path): status \(status)")
                            }
                        } catch let error as DICOMNetworkError {
                            guard case .noPresentationContext = error else { throw error }
                            failed += 1
                            printError("failed \(path): the remote AE accepted no context for its SOP class and transfer syntax")
                        }
                    }
                }
            } catch {
                printError("C-STORE \(remote.description) failed: \(error.commandLineDescription)")
                throw ExitCode.failure
            }
        }
        print("C-STORE \(remote.description): \(stored + warnings) of \(items.count) stored"
              + (warnings > 0 ? ", \(warnings) with warnings" : "") + (failed > 0 ? ", \(failed) failed" : "")
              + (skipped > 0 ? ", \(skipped) non-DICOM files skipped" : ""))
        if failed > 0 { throw ExitCode.failure }
    }

    /// Regular files under the paths, directories searched recursively,
    /// hidden entries skipped.
    static func files(in paths: [String]) -> [String] {
        var files: [String] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                printError("no such file: \(path)")
                continue
            }
            guard isDirectory.boolValue else {
                files.append(path)
                continue
            }
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    files.append(url.path)
                }
            }
        }
        return files
    }

    /// Splits the items so that each association needs at most 128
    /// presentation contexts (PS3.8 9.3.2.2).
    static func batches(_ items: [(path: String, item: DICOMRetrieveItem)]) -> [[(path: String, item: DICOMRetrieveItem)]] {
        // Contexts follow `proposals(for:)`: one per SOP class, plus one per
        // compressed transfer syntax of that class.
        let uncompressed = Set(DICOMTransferSyntaxes.uncompressed + [
            TransferSyntax.explicitVRBigEndian, TransferSyntax.deflatedExplicitVRLittleEndian])
        var batches: [[(path: String, item: DICOMRetrieveItem)]] = []
        var current: [(path: String, item: DICOMRetrieveItem)] = []
        var contexts = Set<String>()
        for entry in items {
            var needed: Set<String> = [entry.item.sopClassUID]
            if !uncompressed.contains(entry.item.transferSyntaxUID) {
                needed.insert(entry.item.sopClassUID + " " + entry.item.transferSyntaxUID)
            }
            let added = needed.subtracting(contexts)
            if !current.isEmpty, contexts.count + added.count > 128 {
                batches.append(current)
                current = []
                contexts = []
            }
            current.append(entry)
            contexts.formUnion(needed)
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }
}
