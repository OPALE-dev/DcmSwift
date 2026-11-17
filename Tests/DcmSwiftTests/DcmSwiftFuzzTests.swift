import XCTest
@testable import DcmSwift

/// Mutation fuzzing of the data set parser, the code that consumes parsed
/// data sets, and the pixel data decoders. Inputs come from deterministic
/// seeds, so every failure is reproducible from its seed and iteration.
///
/// - `DCMSWIFT_FUZZ_ITERATIONS`: mutations per seed (default 40, enough
///   for CI; long runs use thousands, ideally with `--sanitize=address`).
/// - `DCMSWIFT_FUZZ_SEED`: the random seed (default 1).
/// - `DCMSWIFT_FUZZ_CRASH_FILE`: each input is written there before it
///   runs, so that a crash leaves its reproducer behind.
///
/// Reproducers of fixed failures live in CIResources as `fuzz-dataset-*.bin`
/// and `fuzz-codec-*.bin` (run under every codec seed's configuration) and
/// are replayed by `testFuzzRegressionsStayFixed`.
final class DcmSwiftFuzzTests: XCTestCase {
    // MARK: Harness

    override func setUp() {
        super.setUp()
        // Corrupt inputs log parse errors; millions of them would dominate.
        Logger.setMaxLevel(.FATAL)
    }

    override func tearDown() {
        Logger.setMaxLevel(.VERBOSE)
        super.tearDown()
    }

    /// SplitMix64.
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private var iterations: Int {
        ProcessInfo.processInfo.environment["DCMSWIFT_FUZZ_ITERATIONS"].flatMap(Int.init) ?? 40
    }

    private var seed: UInt64 {
        ProcessInfo.processInfo.environment["DCMSWIFT_FUZZ_SEED"].flatMap(UInt64.init) ?? 1
    }

    private let crashFile = ProcessInfo.processInfo.environment["DCMSWIFT_FUZZ_CRASH_FILE"].map(URL.init(fileURLWithPath:))

    /// Values that tend to reach edge cases in lengths, counts, and tags.
    private static let interesting: [UInt32] = [
        0, 1, 2, 3, 4, 7, 8, 0x7F, 0x80, 0xFF, 0x100, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF, 0x1_0000,
        0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFE, 0xFFFF_FFFF,
    ]

    /// One random mutation, or a few stacked.
    static func mutate(_ input: [UInt8], others: [[UInt8]], using random: inout Generator) -> [UInt8] {
        var bytes = input
        for _ in 0..<Int.random(in: 1...4, using: &random) {
            if bytes.isEmpty { bytes = [0] }
            let index = Int.random(in: 0..<bytes.count, using: &random)
            switch Int.random(in: 0..<9, using: &random) {
            case 0:  // Bit flip.
                bytes[index] ^= 1 << UInt8.random(in: 0...7, using: &random)
            case 1:  // Random byte.
                bytes[index] = UInt8.random(in: 0...255, using: &random)
            case 2, 3:  // An interesting 16- or 32-bit value, either byte order.
                let value = interesting.randomElement(using: &random)!
                let width = Bool.random(using: &random) ? 2 : 4
                let big = Bool.random(using: &random)
                for offset in 0..<width where index + offset < bytes.count {
                    let shift = big ? 8 * (width - 1 - offset) : 8 * offset
                    bytes[index + offset] = UInt8(truncatingIfNeeded: value >> shift)
                }
            case 4:  // Delete a range.
                let count = min(Int.random(in: 1...64, using: &random), bytes.count - index)
                bytes.removeSubrange(index..<(index + count))
            case 5:  // Duplicate a range.
                let count = min(Int.random(in: 1...64, using: &random), bytes.count - index)
                bytes.insert(contentsOf: bytes[index..<(index + count)], at: index)
            case 6:  // Truncate.
                bytes.removeSubrange(index...)
            case 7:  // Splice another input.
                if let other = others.randomElement(using: &random), !other.isEmpty {
                    let start = Int.random(in: 0..<other.count, using: &random)
                    let count = min(Int.random(in: 1...256, using: &random), other.count - start)
                    bytes.replaceSubrange(index..<min(bytes.count, index + count), with: other[start..<(start + count)])
                }
            default:  // Fill a range with one value.
                let count = min(Int.random(in: 1...32, using: &random), bytes.count - index)
                let value = UInt8.random(in: 0...255, using: &random)
                for offset in 0..<count { bytes[index + offset] = value }
            }
        }
        return bytes
    }

    private func record(_ bytes: [UInt8]) {
        guard let crashFile else { return }
        try? Data(bytes).write(to: crashFile)
    }

    // MARK: Data set seeds

    /// Encodes elements in one transfer syntax: explicit or implicit VR,
    /// little or big endian, with defined or undefined lengths.
    struct Writer {
        var explicit = true
        var bigEndian = false
        var bytes: [UInt8] = []

        mutating func u16(_ value: UInt16) {
            bytes += bigEndian ? [UInt8(value >> 8), UInt8(value & 0xFF)] : [UInt8(value & 0xFF), UInt8(value >> 8)]
        }

        mutating func u32(_ value: UInt32) {
            let le = (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
            bytes += bigEndian ? le.reversed() : le
        }

        mutating func header(_ group: UInt16, _ element: UInt16, _ vr: String, _ length: UInt32) {
            u16(group)
            u16(element)
            if explicit && group != 0xFFFE {
                bytes += Array(vr.utf8)
                if ["OB", "OW", "OF", "OD", "OL", "OV", "SQ", "UC", "UR", "UT", "UN", "SV", "UV"].contains(vr) {
                    bytes += [0, 0]
                    u32(length)
                } else {
                    u16(UInt16(truncatingIfNeeded: length))
                }
            } else {
                u32(length)
            }
        }

        mutating func text(_ group: UInt16, _ element: UInt16, _ vr: String, _ value: [UInt8], pad: UInt8 = 0x20) {
            var value = value
            if value.count % 2 == 1 { value.append(pad) }
            header(group, element, vr, UInt32(value.count))
            bytes += value
        }

        mutating func text(_ group: UInt16, _ element: UInt16, _ vr: String, _ value: String) {
            text(group, element, vr, Array(value.utf8), pad: vr == "UI" ? 0 : 0x20)
        }

        mutating func us(_ group: UInt16, _ element: UInt16, _ values: [UInt16]) {
            header(group, element, "US", UInt32(2 * values.count))
            values.forEach { u16($0) }
        }

        /// A sequence of items, each written by `item`, with undefined or
        /// defined lengths.
        mutating func sequence(_ group: UInt16, _ element: UInt16, undefined: Bool, items: [(inout Writer) -> Void]) {
            var content = Writer(explicit: explicit, bigEndian: bigEndian)
            for item in items {
                var body = Writer(explicit: explicit, bigEndian: bigEndian)
                item(&body)
                content.header(0xFFFE, 0xE000, "", undefined ? 0xFFFF_FFFF : UInt32(body.bytes.count))
                content.bytes += body.bytes
                if undefined { content.header(0xFFFE, 0xE00D, "", 0) }
            }
            if undefined {
                header(group, element, "SQ", 0xFFFF_FFFF)
                bytes += content.bytes
                header(0xFFFE, 0xE0DD, "", 0)
            } else {
                header(group, element, "SQ", UInt32(content.bytes.count))
                bytes += content.bytes
            }
        }
    }

    /// A Part 10 file: File Meta Information in Explicit VR Little Endian,
    /// then the data set.
    static func part10(transferSyntax: String, dataSet: [UInt8]) -> [UInt8] {
        var meta = Writer()
        meta.header(0x0002, 0x0001, "OB", 2)
        meta.bytes += [0, 1]
        meta.text(0x0002, 0x0002, "UI", "1.2.840.10008.5.1.4.1.1.7")
        meta.text(0x0002, 0x0003, "UI", "1.2.826.0.1.95.1")
        meta.text(0x0002, 0x0010, "UI", transferSyntax)
        meta.text(0x0002, 0x0012, "UI", DICOMImplementation.classUID)
        var group = Writer()
        group.header(0x0002, 0x0000, "UL", 4)
        group.u32(UInt32(meta.bytes.count))
        return [UInt8](repeating: 0, count: 128) + Array("DICM".utf8) + group.bytes + meta.bytes + dataSet
    }

    /// Data sets covering the parser's paths: value representations,
    /// sequences, private blocks, character sets, native and encapsulated
    /// Pixel Data, in every structural transfer syntax.
    static func dataSetSeeds() -> [[UInt8]] {
        func body(_ writer: inout Writer, encapsulated: Bool, rows: UInt16 = 4, columns: UInt16 = 4) {
            writer.text(0x0008, 0x0005, "CS", "ISO 2022 IR 6\\ISO 2022 IR 87")
            writer.text(0x0008, 0x0016, "UI", "1.2.840.10008.5.1.4.1.1.7")
            writer.text(0x0008, 0x0018, "UI", "1.2.826.0.1.95.1")
            writer.text(0x0008, 0x0020, "DA", "20260101")
            writer.text(0x0008, 0x0030, "TM", "120000.5")
            writer.text(0x0010, 0x0010, "PN", [0x59, 0x61, 0x6D, 0x61, 0x64, 0x61, 0x5E, 0x54, 0x61, 0x72, 0x6F, 0x75,
                                                0x3D, 0x1B, 0x24, 0x42, 0x3B, 0x33, 0x45, 0x44, 0x1B, 0x28, 0x42])
            writer.text(0x0010, 0x0020, "LO", "ID\\SECOND")
            writer.text(0x0010, 0x1010, "AS", "042Y")
            writer.text(0x0018, 0x0050, "DS", "1.5")
            writer.text(0x0020, 0x0013, "IS", "7")
            writer.sequence(0x0040, 0xA730, undefined: true, items: [
                { item in
                    item.text(0x0040, 0xA010, "CS", "CONTAINS")
                    item.sequence(0x0040, 0xA043, undefined: false, items: [
                        { code in
                            code.text(0x0008, 0x0100, "SH", "121071")
                            code.text(0x0008, 0x0102, "SH", "DCM")
                        },
                    ])
                },
                { item in item.text(0x0040, 0xA160, "UT", "Text with \\ backslash") },
            ])
            writer.text(0x0029, 0x0010, "LO", "DCMSWIFT FUZZ")
            writer.text(0x0029, 0x1001, "LO", "private")
            writer.us(0x0028, 0x0002, [1])
            writer.text(0x0028, 0x0004, "CS", "MONOCHROME2")
            writer.text(0x0028, 0x0008, "IS", "1")
            writer.us(0x0028, 0x0010, [rows])
            writer.us(0x0028, 0x0011, [columns])
            writer.us(0x0028, 0x0100, [8])
            writer.us(0x0028, 0x0101, [8])
            writer.us(0x0028, 0x0102, [7])
            writer.us(0x0028, 0x0103, [0])
            let pixels = Int(rows) * Int(columns)
            if encapsulated {
                // RLE Lossless: one segment of literal runs.
                var segment: [UInt8] = []
                for start in stride(from: 0, to: pixels, by: 128) {
                    let count = min(128, pixels - start)
                    segment.append(UInt8(count - 1))
                    segment += (0..<count).map { UInt8(truncatingIfNeeded: start + $0) }
                }
                if segment.count % 2 == 1 { segment.append(0) }
                var frame = [UInt8](repeating: 0, count: 64)
                frame[0] = 1
                frame[4] = 64
                frame += segment
                writer.header(0x7FE0, 0x0010, "OB", 0xFFFF_FFFF)
                writer.header(0xFFFE, 0xE000, "", 4)
                writer.u32(0)
                writer.header(0xFFFE, 0xE000, "", UInt32(frame.count))
                writer.bytes += frame
                writer.header(0xFFFE, 0xE0DD, "", 0)
            } else {
                writer.header(0x7FE0, 0x0010, "OB", UInt32(pixels))
                writer.bytes += (0..<pixels).map { UInt8(truncatingIfNeeded: $0 * 7) }
            }
        }
        var seeds: [[UInt8]] = []
        for (syntax, explicit, big) in [
            (TransferSyntax.explicitVRLittleEndian, true, false), (TransferSyntax.implicitVRLittleEndian, false, false),
            (TransferSyntax.explicitVRBigEndian, true, true),
        ] {
            var writer = Writer(explicit: explicit, bigEndian: big)
            body(&writer, encapsulated: false)
            seeds.append(part10(transferSyntax: syntax, dataSet: writer.bytes))
            // Without File Meta Information, as on the network.
            seeds.append(writer.bytes)
        }
        var rle = Writer()
        body(&rle, encapsulated: true, rows: 8, columns: 32)
        seeds.append(part10(transferSyntax: DICOMRLECodec.transferSyntaxUID, dataSet: rle.bytes))
        var deflated = Writer()
        body(&deflated, encapsulated: false)
        if let compressed = try? DICOMDeflate.compress(Data(deflated.bytes)) {
            seeds.append(part10(transferSyntax: TransferSyntax.deflatedExplicitVRLittleEndian, dataSet: [UInt8](compressed)))
        }
        return seeds
    }

    // MARK: Data set target

    private static let limits = DicomReadLimits(
        maximumElementValueLength: 1 << 20, maximumElementCount: 20_000, maximumSequenceDepth: 16,
        maximumItemCount: 20_000, maximumPixelFragmentCount: 1_000, maximumInflatedDataSetLength: 1 << 22)

    /// Parses an input, then uses what it yields as an application would.
    static func exercise(dataSet bytes: [UInt8]) {
        let isPart10 = bytes.count >= 132 && bytes[128..<132].elementsEqual(Array("DICM".utf8))
        var parsed: [DataSet] = []
        if isPart10 {
            let stream = DicomInputStream(data: Data(bytes))
            stream.limits = limits
            if let dataSet = try? stream.readDataset(enforceVR: false) { parsed.append(dataSet) }
        } else {
            // A data set as received on the network, in each structural syntax.
            for syntax in [TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian,
                           TransferSyntax.explicitVRBigEndian] {
                if let dataSet = try? DICOMDataSetCoding.decode(Data(bytes), transferSyntax: syntax, limits: limits) {
                    parsed.append(dataSet)
                }
            }
        }
        parsed.forEach(use)
    }

    /// Uses a parsed data set as an application would.
    static func use(_ dataSet: DataSet) {
        for element in dataSet.allElements.prefix(2_000) {
            _ = dataSet.textValues(forTag: element.name)
            _ = dataSet.personNames(forTag: element.name)
            _ = dataSet.string(forTag: element.name)
            _ = element.description
        }
        _ = dataSet.validateFileMetaInformation()
        for syntax in [TransferSyntax.explicitVRLittleEndian, TransferSyntax.implicitVRLittleEndian,
                       TransferSyntax.explicitVRBigEndian, TransferSyntax.deflatedExplicitVRLittleEndian] {
            if let encoded = try? DICOMDataSetCoding.encode(dataSet, transferSyntax: syntax) {
                _ = try? DICOMDataSetCoding.decode(encoded, transferSyntax: syntax, limits: limits)
            }
        }
        _ = dataSet.toData(vrMethod: .Explicit, byteOrder: .LittleEndian)
        // Pixel Data, when small enough to decode quickly.
        guard let description = try? DICOMPixelDescription(dataset: dataSet),
              description.rows * description.columns * max(1, description.samplesPerPixel)
                * max(1, description.numberOfFrames) <= 1 << 20 else { return }
        if let native = try? DICOMNativePixelData(dataset: dataSet) {
            for frame in 0..<min(description.numberOfFrames, 4) { _ = try? native.frameData(frame) }
        }
        if let encapsulated = try? DICOMEncapsulatedPixelData(dataset: dataSet) {
            for frame in 0..<min(description.numberOfFrames, 4) {
                _ = try? encapsulated.encodedFrame(frame)
                _ = try? encapsulated.decodedFrame(frame)
            }
        }
        _ = try? DICOMImageRenderer(dataset: dataSet)
    }

    // MARK: Codec seeds and target

    struct CodecSeed {
        let name: String
        let bytes: [UInt8]
        let decoder: any DICOMPixelDataDecoder
        let description: DICOMPixelDescription
        let collection: Bool
    }

    private func resource(_ name: String) -> URL? {
        let url = URL(fileURLWithPath: name)
        return Bundle.module.url(forResource: url.deletingPathExtension().lastPathComponent, withExtension: url.pathExtension)
    }

    /// Codec streams of CIResources, each with a transfer syntax and image
    /// description under which the unmutated stream decodes.
    private func codecSeeds() throws -> [CodecSeed] {
        let directory = try XCTUnwrap(resource("jpeg2000-cases.json")).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let families: [(prefix: String, extensions: Set<String>, syntaxes: [String])] = [
            ("jpeg-", ["jpg"], ["1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51", "1.2.840.10008.1.2.4.57",
                                "1.2.840.10008.1.2.4.70", "1.2.840.10008.1.2.4.55", "1.2.840.10008.1.2.4.53",
                                "1.2.840.10008.1.2.4.52", "1.2.840.10008.1.2.4.54", "1.2.840.10008.1.2.4.56",
                                "1.2.840.10008.1.2.4.58"] + (59...66).map { "1.2.840.10008.1.2.4.\($0)" }),
            ("jpegls-", ["jls"], ["1.2.840.10008.1.2.4.80", "1.2.840.10008.1.2.4.81"]),
            ("jpeg2000-", ["j2k", "j2c"], ["1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91", "1.2.840.10008.1.2.4.92",
                                         "1.2.840.10008.1.2.4.93", "1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.203"]),
            ("jpegxl-", ["jxl"], ["1.2.840.10008.1.2.4.110", "1.2.840.10008.1.2.4.111", "1.2.840.10008.1.2.4.112"]),
        ]
        let part2 = try JSONDecoder().decode(
            [[String: AnyDecodable]].self, from: Data(contentsOf: XCTUnwrap(resource("jpeg2000-part2-cases.json"))))
        var seeds: [CodecSeed] = []
        for file in files {
            guard let family = families.first(where: {
                file.hasPrefix($0.prefix) && $0.extensions.contains(URL(fileURLWithPath: file).pathExtension)
            }), !(family.prefix == "jpeg-" && file.hasPrefix("jpegls-")),
               !(family.prefix == "jpeg-" && file.hasPrefix("jpegxl-")) else { continue }
            let bytes = [UInt8](try Data(contentsOf: directory.appendingPathComponent(file)))
            var frames = 1
            if file.hasPrefix("jpeg2000-part2-") {
                let name = String(file.dropFirst("jpeg2000-part2-".count).dropLast(4))
                frames = part2.first { $0["name"]?.string == name }?["frames"]?.int ?? 1
            }
            let geometry = Self.geometry(of: bytes)
            found: for syntax in family.syntaxes {
                guard let decoder = DICOMCodecRegistry.decoder(for: syntax) else { continue }
                for description in Self.descriptions(geometry, frames: frames) {
                    if let collection = decoder as? any DICOMPixelDataCollectionDecoder, frames > 1 {
                        if (try? collection.decodeCollection(Data(bytes), description: description)) != nil {
                            seeds.append(CodecSeed(name: "\(file) as \(syntax)", bytes: bytes, decoder: decoder,
                                                   description: description, collection: true))
                            break found
                        }
                    } else if (try? decoder.decode(Data(bytes), description: description)) != nil {
                        seeds.append(CodecSeed(name: "\(file) as \(syntax)", bytes: bytes, decoder: decoder,
                                               description: description, collection: false))
                        break found
                    }
                }
            }
        }
        return seeds
    }

    /// Rows, columns, components, and precision read from a JPEG, JPEG-LS,
    /// or JPEG 2000 header, or a JPEG XL guess.
    static func geometry(of bytes: [UInt8]) -> [(rows: Int, columns: Int, samples: Int, bits: Int)] {
        func u16(_ at: Int) -> Int { at + 1 < bytes.count ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : 0 }
        func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
        var index = 0
        while index + 4 < bytes.count {
            if bytes[index] == 0xFF {
                let marker = bytes[index + 1]
                // SOFn (not DHT, JPG, DAC) and the JPEG-LS SOF55.
                if (0xC0...0xCF).contains(marker) && ![0xC4, 0xC8, 0xCC].contains(marker) || marker == 0xF7 {
                    return [(u16(index + 5), u16(index + 7), Int(index + 9 < bytes.count ? bytes[index + 9] : 1),
                             Int(bytes[index + 4]))]
                }
                if marker == 0x51 {  // SIZ
                    let components = u16(index + 38)
                    let precision = index + 40 < bytes.count ? Int(bytes[index + 40] & 0x7F) + 1 : 8
                    return [(u32(index + 10) - u32(index + 18), u32(index + 6) - u32(index + 14), components, precision)]
                }
            }
            index += 1
        }
        // JPEG XL: the cases' geometries.
        return [(19, 27, 1, 8), (19, 27, 1, 12), (17, 23, 3, 8), (16, 24, 3, 8), (23, 31, 3, 8)]
    }

    static func descriptions(
        _ geometries: [(rows: Int, columns: Int, samples: Int, bits: Int)], frames: Int
    ) -> [DICOMPixelDescription] {
        var descriptions: [DICOMPixelDescription] = []
        for geometry in geometries where geometry.rows > 0 && geometry.columns > 0 {
            // Part 2 collections hold frames as components.
            let samples = frames > 1 ? max(1, geometry.samples / frames) : max(1, geometry.samples)
            let photometrics: [DICOMPhotometricInterpretation] = samples == 3
                ? [.rgb, .ybrFull422, .ybrFull, .ybrICT, .ybrRCT] : [.monochrome2]
            for photometric in photometrics {
                for bits in Set([geometry.bits, 8, 12, 16]) where bits >= 1 && bits <= 16 {
                    for signed in [false, true] {
                        descriptions.append(DICOMPixelDescription(
                            rows: geometry.rows, columns: geometry.columns, samplesPerPixel: samples,
                            photometricInterpretation: photometric, bitsAllocated: bits > 8 ? 16 : 8,
                            bitsStored: bits, highBit: bits - 1, isSigned: signed, planarConfiguration: 0,
                            numberOfFrames: frames, isEncapsulated: true))
                    }
                }
            }
        }
        return descriptions
    }

    static func exercise(_ seed: CodecSeed, _ bytes: [UInt8]) {
        if seed.collection, let collection = seed.decoder as? any DICOMPixelDataCollectionDecoder {
            _ = try? collection.decodeCollection(Data(bytes), description: seed.description)
        } else {
            _ = try? seed.decoder.decode(Data(bytes), description: seed.description)
        }
    }

    // MARK: Tests

    func testFuzzDataSetParser() {
        let seeds = Self.dataSetSeeds()
        XCTAssertGreaterThanOrEqual(seeds.count, 8)
        // The seeds themselves parse.
        for (index, seed) in seeds.enumerated() {
            if seed.count >= 132, seed[128..<132].elementsEqual(Array("DICM".utf8)) {
                let stream = DicomInputStream(data: Data(seed))
                XCTAssertNoThrow(try stream.readDataset(enforceVR: false), "seed \(index)")
            }
        }
        var random = Generator(state: seed)
        for (index, input) in seeds.enumerated() {
            for iteration in 0..<iterations {
                let mutated = Self.mutate(input, others: seeds, using: &random)
                record(mutated)
                Self.exercise(dataSet: mutated)
                if iteration % 1000 == 999 { print("data set seed \(index): \(iteration + 1) inputs") }
            }
        }
    }

    func testFuzzPixelDataDecoders() throws {
        let seeds = try codecSeeds()
        // Every family contributes seeds.
        for family in ["jpeg-", "jpegls-", "jpeg2000-", "jpeg2000-part2-", "jpegxl-"] {
            XCTAssertTrue(seeds.contains { $0.name.hasPrefix(family) }, "no \(family) seed")
        }
        let streams = seeds.map(\.bytes)
        var random = Generator(state: seed)
        for seed in seeds {
            for _ in 0..<iterations {
                let mutated = Self.mutate(seed.bytes, others: streams, using: &random)
                record(mutated)
                Self.exercise(seed, mutated)
            }
        }
        print("fuzzed \(seeds.count) codec seeds, \(iterations) inputs each")
    }

    func testFuzzRegressionsStayFixed() throws {
        let directory = try XCTUnwrap(resource("jpeg2000-cases.json")).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("fuzz-") && $0.hasSuffix(".bin") }.sorted()
        let codecs = try codecSeeds()
        for file in files {
            let bytes = [UInt8](try Data(contentsOf: directory.appendingPathComponent(file)))
            if file.hasPrefix("fuzz-codec-") {
                // Codec reproducers run under every seed's configuration.
                codecs.forEach { Self.exercise($0, bytes) }
            } else {
                Self.exercise(dataSet: bytes)
            }
        }
        XCTAssertFalse(files.isEmpty)
    }
}

/// Just enough JSON decoding for the case manifests.
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = NSNull()
        }
    }

    var int: Int? { value as? Int }
    var string: String? { value as? String }
}
