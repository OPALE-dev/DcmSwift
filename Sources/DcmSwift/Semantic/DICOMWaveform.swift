import Foundation

/// A multiplex group of the Waveform Sequence (5400,0100): channels sampled
/// together (PS3.3 C.10.9).
public struct DICOMWaveform: Sendable {
    public struct Channel: Sendable {
        /// Channel Label (003A,0203).
        public let label: String?
        /// Channel Source Sequence (003A,0208): what the channel measures.
        public let source: DICOMCode?
        /// Channel Sensitivity (003A,0210): the value of one unit of a sample.
        public let sensitivity: Double?
        /// Channel Sensitivity Units Sequence (003A,0211).
        public let units: DICOMCode?
        /// Channel Sensitivity Correction Factor (003A,0212), 1 when absent.
        public let correction: Double
        /// Channel Baseline (003A,0213), 0 when absent.
        public let baseline: Double
        /// Channel Time Skew (003A,0214), in seconds.
        public let timeSkew: Double?
        /// Channel Sample Skew (003A,0215), in samples.
        public let sampleSkew: Double?
        /// Waveform Bits Stored (003A,021A).
        public let bitsStored: Int?
    }

    public enum Interpretation: String, CaseIterable, Sendable {
        case signed8 = "SB", unsigned8 = "UB", muLaw = "MB", aLaw = "AB"
        case signed16 = "SS", unsigned16 = "US", signed32 = "SL", unsigned32 = "UL"
        case signed64 = "SV", unsigned64 = "UV"

        /// Waveform Bits Allocated (5400,1004) of each interpretation.
        public var bitsAllocated: Int {
            switch self {
            case .signed8, .unsigned8, .muLaw, .aLaw: return 8
            case .signed16, .unsigned16: return 16
            case .signed32, .unsigned32: return 32
            case .signed64, .unsigned64: return 64
            }
        }
    }

    /// Multiplex Group Label (003A,0020).
    public let label: String?
    /// Sampling Frequency (003A,001A), in hertz.
    public let samplingFrequency: Double
    /// Number of Waveform Samples (003A,0010) per channel.
    public let sampleCount: Int
    /// Waveform Originality (003A,0004): ORIGINAL or DERIVED.
    public let originality: String?
    /// Multiplex Group Time Offset (0018,1068), in milliseconds.
    public let timeOffset: Double?
    public let interpretation: Interpretation
    public let channels: [Channel]
    /// The samples, channel after channel, as their 64-bit patterns: G.711
    /// samples decoded to 16-bit linear values, signed samples sign-extended.
    private let samples: [[UInt64]]

    public struct DecodingError: Error, CustomStringConvertible {
        public let description: String
    }

    /// The multiplex groups of a data set.
    public static func groups(in dataSet: DataSet) throws -> [DICOMWaveform] {
        guard let sequence = dataSet.element(forTagName: "WaveformSequence") as? DataSequence else { return [] }
        return try sequence.items.enumerated().map { index, item in
            try DICOMWaveform(item: item, index: index)
        }
    }

    init(item: DataItem, index: Int) throws {
        func element(_ name: String) -> DataElement? { item.element(withName: name) }
        func number(_ element: DataElement?) -> Double? {
            guard let element else { return nil }
            if let text = element.textValues?.first { return Double(text.trimmingCharacters(in: .whitespaces)) }
            if let value = element.uint16Values?.first { return Double(value) }
            if let value = element.uint32Values?.first { return Double(value) }
            return nil
        }
        func integer(_ name: String) -> Int? { number(element(name)).map { Int($0) } }
        guard let channelCount = integer("NumberOfWaveformChannels"), channelCount > 0,
              let sampleCount = integer("NumberOfWaveformSamples"), sampleCount >= 0,
              let bits = integer("WaveformBitsAllocated"),
              let interpretationText = element("WaveformSampleInterpretation")?.textValues?.first,
              let interpretation = Interpretation(rawValue: interpretationText),
              let data = element("WaveformData")?.data else {
            throw DecodingError(description: "multiplex group \(index) lacks its channels, samples, or Waveform Data")
        }
        guard bits == interpretation.bitsAllocated else {
            throw DecodingError(description: "multiplex group \(index): \(bits) bits do not fit \(interpretationText)")
        }
        let width = bits / 8
        guard data.count >= channelCount * sampleCount * width else {
            throw DecodingError(description: "multiplex group \(index): Waveform Data is shorter than its samples")
        }
        let bigEndian = element("WaveformData")?.byteOrder == .BigEndian && width > 1
        var samples = [[UInt64]](repeating: [], count: channelCount)
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for channel in 0..<channelCount { samples[channel].reserveCapacity(sampleCount) }
            for sample in 0..<sampleCount {
                for channel in 0..<channelCount {
                    let offset = (sample * channelCount + channel) * width
                    var raw: UInt64 = 0
                    for byte in 0..<width {
                        let value = UInt64(buffer[offset + (bigEndian ? width - 1 - byte : byte)])
                        raw |= value << UInt64(byte * 8)
                    }
                    samples[channel].append(UInt64(bitPattern: Self.decode(raw, interpretation)))
                }
            }
        }
        self.samples = samples
        self.interpretation = interpretation
        self.sampleCount = sampleCount
        samplingFrequency = number(element("SamplingFrequency")) ?? 0
        label = element("MultiplexGroupLabel")?.textValues?.first
        originality = element("WaveformOriginality")?.textValues?.first
        timeOffset = number(element("MultiplexGroupTimeOffset"))
        let definitions = (element("ChannelDefinitionSequence") as? DataSequence)?.items ?? []
        channels = (0..<channelCount).map { index in
            guard index < definitions.count else {
                return Channel(label: nil, source: nil, sensitivity: nil, units: nil, correction: 1, baseline: 0,
                               timeSkew: nil, sampleSkew: nil, bitsStored: nil)
            }
            let definition = definitions[index]
            func value(_ name: String) -> DataElement? { definition.element(withName: name) }
            func code(_ name: String) -> DICOMCode? {
                (value(name) as? DataSequence)?.items.first.flatMap(DICOMCode.init(item:))
            }
            return Channel(
                label: value("ChannelLabel")?.textValues?.first, source: code("ChannelSourceSequence"),
                sensitivity: number(value("ChannelSensitivity")), units: code("ChannelSensitivityUnitsSequence"),
                correction: number(value("ChannelSensitivityCorrectionFactor")) ?? 1,
                baseline: number(value("ChannelBaseline")) ?? 0, timeSkew: number(value("ChannelTimeSkew")),
                sampleSkew: number(value("ChannelSampleSkew")), bitsStored: number(value("WaveformBitsStored")).map { Int($0) })
        }
    }

    /// The samples of a channel, as stored; G.711 samples decoded. Unsigned
    /// 64-bit samples above Int64.max are given as Int64.max.
    public func samples(channel: Int) -> [Int64] {
        guard interpretation == .unsigned64 else { return samples[channel].map { Int64(bitPattern: $0) } }
        return samples[channel].map { $0 > UInt64(Int64.max) ? Int64.max : Int64($0) }
    }

    /// The values of a channel in its units: sample × Channel Sensitivity ×
    /// Channel Sensitivity Correction Factor + Channel Baseline (C.10.9.1.4).
    public func values(channel: Int) -> [Double] {
        let definition = channels[channel]
        let scale = (definition.sensitivity ?? 1) * definition.correction
        let unsigned = interpretation == .unsigned64
        return samples[channel].map { (unsigned ? Double($0) : Double(Int64(bitPattern: $0))) * scale + definition.baseline }
    }

    /// The time of each sample, in seconds from the multiplex group start.
    public var times: [Double] {
        guard samplingFrequency > 0 else { return [] }
        return (0..<sampleCount).map { Double($0) / samplingFrequency }
    }

    static func decode(_ raw: UInt64, _ interpretation: Interpretation) -> Int64 {
        switch interpretation {
        case .signed8: return Int64(Int8(truncatingIfNeeded: raw))
        case .unsigned8: return Int64(UInt8(truncatingIfNeeded: raw))
        case .muLaw: return Int64(muLaw(UInt8(truncatingIfNeeded: raw)))
        case .aLaw: return Int64(aLaw(UInt8(truncatingIfNeeded: raw)))
        case .signed16: return Int64(Int16(truncatingIfNeeded: raw))
        case .unsigned16: return Int64(UInt16(truncatingIfNeeded: raw))
        case .signed32: return Int64(Int32(truncatingIfNeeded: raw))
        case .unsigned32: return Int64(UInt32(truncatingIfNeeded: raw))
        case .signed64: return Int64(bitPattern: raw)
        case .unsigned64: return Int64(bitPattern: raw)
        }
    }

    /// ITU-T G.711 mu-law to 16-bit linear.
    static func muLaw(_ code: UInt8) -> Int16 {
        let value = ~code
        let exponent = Int((value >> 4) & 0x07)
        let magnitude = ((Int(value & 0x0F) << 3) + 0x84) << exponent
        return Int16(value & 0x80 != 0 ? 0x84 - magnitude : magnitude - 0x84)
    }

    /// ITU-T G.711 A-law to 16-bit linear.
    static func aLaw(_ code: UInt8) -> Int16 {
        let value = code ^ 0x55
        let exponent = Int((value >> 4) & 0x07)
        let mantissa = Int(value & 0x0F)
        let magnitude = exponent == 0 ? (mantissa << 4) + 8 : ((mantissa << 4) + 0x108) << (exponent - 1)
        return Int16(value & 0x80 != 0 ? magnitude : -magnitude)
    }
}
