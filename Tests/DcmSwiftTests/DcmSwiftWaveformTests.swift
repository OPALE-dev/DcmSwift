import Foundation
import XCTest
@testable import DcmSwift

/// Waveforms (PS3.3 C.10.9).
final class DcmSwiftWaveformTests: XCTestCase {
    private func element(_ name: String, _ vr: VR.VR, _ value: Any, in item: DataItem, dataSet: DataSet) throws {
        let element = try XCTUnwrap(DataElement(withTagName: name, dataset: dataSet, parent: item), name)
        element.vr = vr
        if let data = value as? Data {
            element.data = data
            element.length = data.count
        } else {
            XCTAssertTrue(element.setValue(value), name)
        }
        item.elements.append(element)
    }

    private func sequence(_ name: String, parent: DataElement? = nil) throws -> DataSequence {
        let sequence = DataSequence(withTag: try XCTUnwrap(DicomSpec.shared.dataTag(forName: name)), parent: parent)
        sequence.vr = .SQ
        sequence.length = -1
        return sequence
    }

    private func item(in sequence: DataSequence) -> DataItem {
        let item = DataItem(withTag: DataTag(withGroup: "fffe", element: "e000"), parent: sequence)
        item.length = -1
        sequence.items.append(item)
        return item
    }

    func testChannelsAndValues() throws {
        let dataSet = DataSet()
        let waveforms = try sequence("WaveformSequence")
        let group = item(in: waveforms)
        try element("NumberOfWaveformChannels", .US, Data([2, 0]), in: group, dataSet: dataSet)
        try element("NumberOfWaveformSamples", .UL, Data([3, 0, 0, 0]), in: group, dataSet: dataSet)
        try element("SamplingFrequency", .DS, "500", in: group, dataSet: dataSet)
        try element("MultiplexGroupLabel", .SH, "RHYTHM", in: group, dataSet: dataSet)
        try element("WaveformBitsAllocated", .US, Data([16, 0]), in: group, dataSet: dataSet)
        try element("WaveformSampleInterpretation", .CS, "SS", in: group, dataSet: dataSet)
        let definitions = try sequence("ChannelDefinitionSequence", parent: group)
        for (sensitivity, correction, baseline) in [("2.5", "1", "0"), ("0.5", "2", "-3")] {
            let channel = item(in: definitions)
            try element("ChannelSensitivity", .DS, sensitivity, in: channel, dataSet: dataSet)
            try element("ChannelSensitivityCorrectionFactor", .DS, correction, in: channel, dataSet: dataSet)
            try element("ChannelBaseline", .DS, baseline, in: channel, dataSet: dataSet)
        }
        group.elements.append(definitions)
        // Interleaved: (1, -1), (2, -2), (-32768, 32767).
        let samples: [Int16] = [1, -1, 2, -2, -32768, 32767]
        try element("WaveformData", .OW, samples.withUnsafeBufferPointer { Data(buffer: $0) }, in: group, dataSet: dataSet)
        dataSet.add(element: waveforms)

        let groups = try DICOMWaveform.groups(in: dataSet)
        XCTAssertEqual(groups.count, 1)
        let waveform = try XCTUnwrap(groups.first)
        XCTAssertEqual(waveform.label, "RHYTHM")
        XCTAssertEqual(waveform.samplingFrequency, 500)
        XCTAssertEqual(waveform.samples(channel: 0), [1, 2, -32768])
        XCTAssertEqual(waveform.samples(channel: 1), [-1, -2, 32767])
        XCTAssertEqual(waveform.values(channel: 0), [2.5, 5, -81920])
        // sample × 0.5 × 2 − 3
        XCTAssertEqual(waveform.values(channel: 1), [-4, -5, 32764])
        XCTAssertEqual(waveform.times, [0, 0.002, 0.004])
    }

    func testSampleInterpretations() {
        XCTAssertEqual(DICOMWaveform.decode(0xFF, .signed8), -1)
        XCTAssertEqual(DICOMWaveform.decode(0xFF, .unsigned8), 255)
        XCTAssertEqual(DICOMWaveform.decode(0xFFFF_FFFF, .signed32), -1)
        XCTAssertEqual(DICOMWaveform.decode(0xFFFF_FFFF, .unsigned32), 4_294_967_295)
        // ITU-T G.711 reference values.
        XCTAssertEqual(DICOMWaveform.muLaw(0xFF), 0)
        XCTAssertEqual(DICOMWaveform.muLaw(0x7F), 0)
        XCTAssertEqual(DICOMWaveform.muLaw(0x80), 32124)
        XCTAssertEqual(DICOMWaveform.muLaw(0x00), -32124)
        XCTAssertEqual(DICOMWaveform.aLaw(0xD5), 8)
        XCTAssertEqual(DICOMWaveform.aLaw(0x55), -8)
        XCTAssertEqual(DICOMWaveform.aLaw(0xAA), 32256)
        XCTAssertEqual(DICOMWaveform.aLaw(0x2A), -32256)
        XCTAssertEqual(DICOMWaveform.Interpretation.allCases.map(\.bitsAllocated), [8, 8, 8, 8, 16, 16, 32, 32, 64, 64])
    }

    func testMissingAttributesAreReported() throws {
        let dataSet = DataSet()
        let waveforms = try sequence("WaveformSequence")
        _ = item(in: waveforms)
        dataSet.add(element: waveforms)
        XCTAssertThrowsError(try DICOMWaveform.groups(in: dataSet))
        XCTAssertTrue(try DICOMWaveform.groups(in: DataSet()).isEmpty)
    }
}
