//
//  DcmSign.swift
//
//  Signs DICOM files and verifies their Digital Signatures.
//

import ArgumentParser
import DcmSwift
import Foundation

@main
struct DcmSign: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Verify the Digital Signatures of DICOM files, or sign them (PS3.15 Annex C).",
        discussion: """
            Without --key, every signature of each file, in Sequence Items too, is verified; \
            the exit status is 1 when one is not valid. With --key and --certificate, the \
            file is signed with the Base RSA Digital Signature Profile and written to --output.
            """)

    @Argument(help: "DICOM files")
    var paths: [String]

    @Option(help: "PEM file of the RSA private key to sign with")
    var key: String?

    @Option(help: "PEM file of the signer's X.509 certificate")
    var certificate: String?

    @Option(help: "MAC algorithm: SHA1, SHA256, SHA384, or SHA512")
    var algorithm: String = "SHA256"

    @Option(name: .customLong("tag"), help: "A Data Element to sign, as gggg,eeee; repeatable (default: all that may be signed)")
    var tags: [String] = []

    @Option(name: .shortAndLong, help: "Signed file, with one input file")
    var output: String?

    mutating func run() throws {
        if let key {
            guard let certificate, let output, paths.count == 1 else {
                throw ValidationError("signing needs --certificate, --output, and one file")
            }
            guard let algorithm = DICOMMACAlgorithm(rawValue: algorithm.uppercased()) else {
                throw ValidationError("unknown MAC algorithm \(self.algorithm)")
            }
            let signer = try DICOMDigitalSigner(
                privateKeyPEM: String(contentsOfFile: key, encoding: .utf8),
                certificatePEM: String(contentsOfFile: certificate, encoding: .utf8), algorithm: algorithm)
            guard let file = DicomFile(forPath: paths[0]), let dataSet = file.dataset else {
                throw ValidationError("cannot read \(paths[0]) as DICOM")
            }
            let selected = tags.isEmpty ? nil : tags.map { $0.replacingOccurrences(of: ",", with: "") }
            let uid = try signer.sign(dataSet, tags: selected)
            guard file.write(atPath: output) else { throw ValidationError("cannot write \(output)") }
            print("\(output): signed, Digital Signature UID \(uid)")
            return
        }
        var failed = false
        for path in paths {
            guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
                print("\(path): cannot be read as DICOM")
                failed = true
                continue
            }
            let results = DICOMSignatureVerification.verify(dataSet)
            if results.isEmpty { print("\(path): no Digital Signature") }
            for result in results {
                let location = result.path.isEmpty ? "top level" : result.path.joined(separator: " > ")
                print("\(path): \(location) \(result.algorithm) \(result.status) [\(result.uid)] \(result.signer ?? "")")
                if result.status != .valid { failed = true }
            }
        }
        if failed { throw ExitCode.failure }
    }
}
