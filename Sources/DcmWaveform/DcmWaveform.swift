//
//  DcmWaveform.swift
//
//  Prints the waveforms of a DICOM file, or exports their samples.
//

import ArgumentParser
import DcmSwift
import Foundation

@main
struct DcmWaveform: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the multiplex groups and channels of a waveform instance, or export their samples.")

    @Argument(help: "DICOM file")
    var path: String

    @Option(help: "Export the values of this multiplex group (from 1) as CSV: time, then one column per channel")
    var csv: Int?

    @Flag(help: "Export every multiplex group as JSON, with the stored samples and the values")
    var json = false

    mutating func run() throws {
        guard let file = DicomFile(forPath: path), let dataSet = file.dataset else {
            throw ValidationError("cannot read \(path) as DICOM")
        }
        let groups = try DICOMWaveform.groups(in: dataSet)
        if json {
            let object = groups.map { group -> [String: Any] in
                [
                    "samplingFrequency": group.samplingFrequency, "interpretation": group.interpretation.rawValue,
                    "samples": group.channels.indices.map { group.samples(channel: $0) },
                    "values": group.channels.indices.map { group.values(channel: $0) },
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            FileHandle.standardOutput.write(data)
            return
        }
        if let csv {
            guard (1...groups.count).contains(csv) else { throw ValidationError("there are \(groups.count) multiplex groups") }
            let group = groups[csv - 1]
            let names = group.channels.enumerated().map { index, channel in
                channel.label ?? channel.source?.meaning ?? "channel \(index + 1)"
            }
            print((["time (s)"] + names).joined(separator: ","))
            let values = group.channels.indices.map { group.values(channel: $0) }
            for (index, time) in group.times.enumerated() {
                print(([String(time)] + values.map { String($0[index]) }).joined(separator: ","))
            }
            return
        }
        for (index, group) in groups.enumerated() {
            print("Multiplex group \(index + 1)\(group.label.map { " \($0)" } ?? ""): \(group.channels.count) channels, "
                  + "\(group.sampleCount) samples at \(group.samplingFrequency) Hz, \(group.interpretation.rawValue)")
            for (number, channel) in group.channels.enumerated() {
                let name = channel.label ?? channel.source?.meaning ?? "channel \(number + 1)"
                let unit = channel.units?.value ?? ""
                print("  \(number + 1). \(name): sensitivity \(channel.sensitivity.map { String($0) } ?? "-") \(unit)")
            }
        }
    }
}
