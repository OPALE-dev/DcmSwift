import XCTest
@testable import DcmSwift

/// JPEG Lossless (ITU-T T.81 Annex H) qualification. The streams were
/// produced by libjpeg-turbo 3.2.0 (through imagecodecs 2026.8.16) from the
/// listed values, which it decodes losslessly.
final class DcmSwiftJPEGLosslessTests: XCTestCase {

    private struct LosslessVector {
        let name: String
        let rows: Int
        let columns: Int
        let samples: Int
        let bits: Int
        let stream: String
        let values: [Int64]
    }

    func testLibjpegTurboStreamsDecodeExactly() throws {
        let vectors = [
            LosslessVector(
                name: "12-bit predictor 1", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400190000030101010000000000" +
                "0000000000000a0b0c090708ffda00080101000100000a7a9da4fb6f30543126833d7fd3c4d48123c12598ab8a583f60" +
                "6bd2f3a8b54d18d290e64ed59bc74f4e277f017587c97fffd9",
                values: [1192, 3870, 1050, 2560, 1705, 2802, 3291, 3674, 3990, 2368, 1381, 3177, 628, 3414, 730, 922, 1300, 227, 2857, 1229, 627, 1167, 813, 3578, 2759, 3738, 274, 21, 109, 2047]),
            LosslessVector(
                name: "12-bit predictor 2", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400190000030101010000000000" +
                "0000000000000a0b0c080907ffda0008010100020000433d977238e85a717709954986fc76b17797d419ea5e4bcb1fad" +
                "4d3b1ad9dd521f1c9b1eead918ccb9cb540e4e4d741cff00ffd9",
                values: [104, 3363, 405, 538, 3039, 3264, 914, 487, 2396, 1916, 3524, 3344, 2183, 1241, 1320, 1399, 3690, 1140, 1007, 2946, 545, 1043, 3161, 4056, 2133, 1823, 3953, 1958, 305, 2066]),
            LosslessVector(
                name: "12-bit predictor 3", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400180001010101010000000000" +
                "0000000000000b0c0a0809ffda0008010100030000e88eca9ade8d115a5f012b7659e0ece2568a9e3d47a602247a478a" +
                "a67304e5b35f5d4a819933dad392d2955c8e2a82c61fffd9",
                values: [2184, 2386, 10, 2267, 566, 2086, 436, 4077, 214, 3308, 3651, 3246, 763, 2868, 565, 2548, 1942, 1396, 2016, 4050, 3614, 1909, 1928, 881, 2642, 3461, 2686, 656, 3254, 3512]),
            LosslessVector(
                name: "12-bit predictor 4", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc4001a0000030003010000000000" +
                "0000000000000a0b0c0708090dffda0008010100040000e291bc9fac827559c854ced431a9a1e073495881b9f940693d" +
                "0308e94a612915b56952d1cffca4aa348bb7bc895c372d37ffd9",
                values: [1619, 2508, 3521, 469, 3208, 179, 2880, 1821, 1403, 146, 472, 579, 3087, 2108, 1087, 3974, 1138, 1909, 1368, 3311, 2077, 3756, 1943, 3372, 3980, 2577, 1827, 1807, 876, 2105]),
            LosslessVector(
                name: "12-bit predictor 5", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400190000030101010000000000" +
                "0000000000000a0b0c090508ffda0008010100050000057e48a639919ba9401dbdcca4b7dd4137250be1a6f3ccd0c074" +
                "f5b533455dc6b7b76661bc155716cf60cf48f9d48b68c7ffd9",
                values: [1112, 1090, 399, 2035, 3280, 1553, 564, 1013, 3016, 4068, 3822, 48, 2490, 398, 1093, 788, 2359, 3969, 69, 2834, 2025, 3612, 3941, 821, 3698, 2953, 3816, 1513, 211, 2003]),
            LosslessVector(
                name: "12-bit predictor 6", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400180000030101000000000000" +
                "0000000000000a0b0c0608ffda00080101000600003a291b0e5dc7731f5a4e2376009a0c8a4fc649d0bb2bb85aafd807" +
                "d6075058a9b650cd74df1c6f04561f397b3bc40d7cdfffd9",
                values: [2978, 15, 934, 2529, 32, 3399, 2238, 2718, 3118, 632, 1073, 2186, 1589, 1096, 1646, 3952, 1835, 3605, 3681, 762, 2664, 2088, 2424, 3849, 3434, 3469, 1761, 2899, 2065, 2620]),
            LosslessVector(
                name: "12-bit predictor 7", rows: 5, columns: 6, samples: 1, bits: 12,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400180001010101010000000000" +
                "0000000000000b0c0a0809ffda00080101000700007e78312a8aea89b7535e430e13d5c0b96c6bda977352036fda3935" +
                "a514c04eb53c8319b3e93b55eb90fdccf2dfa98131ffd9",
                values: [4071, 172, 2870, 3038, 700, 1939, 1048, 374, 2318, 1001, 1644, 2216, 2955, 2976, 1479, 2079, 433, 2510, 398, 3569, 365, 2809, 3282, 1479, 3203, 2634, 2420, 2450, 3198, 443]),
            LosslessVector(
                name: "8-bit predictor 1", rows: 4, columns: 5, samples: 1, bits: 8,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b080004000501011100ffc400190000030101010000000000" +
                "000000000000040607050803ffda0008010100010000da811d864f35f8f54a5589d5a13b34caf081b847ff00ffd9",
                values: [154, 29, 43, 15, 24, 6, 0, 169, 116, 214, 59, 99, 50, 32, 44, 153, 142, 130, 178, 82]),
            LosslessVector(
                name: "16-bit full range", rows: 4, columns: 5, samples: 1, bits: 16,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b100004000501011100ffc400190001010003010000000000" +
                "0000000000000f0d08090e0cffda0008010100010000e24afc12e8710524c87d1620fa7034849d590b7c6596b06a7ddd" +
                "2e255d182da05cb35a9b5113dbffd9",
                values: [18732, 14788, 32076, 9843, 27227, 25007, 34994, 53499, 53166, 26279, 25185, 24867, 30238, 37708, 14506, 64143, 2749, 25706, 45586, 38665]),
            LosslessVector(
                name: "16-bit category 16", rows: 1, columns: 5, samples: 1, bits: 16,
                stream:
                "ffd8ffe000104a46494600010100000100010000ffc3000b100001000501011100ffc400150001010000000000000000" +
                "0000000000001001ffda000801010001000011ffd9",
                values: [0, 32768, 0, 65535, 32767]),
            LosslessVector(
                name: "RGB 8-bit predictor 6", rows: 3, columns: 4, samples: 3, bits: 8,
                stream:
                "ffd8ffee000e41646f626500640000000000ffc30011080003000403521100471100421100ffc4001a00000203010100" +
                "0000000000000000000007080405060002ffda000c035200470042000600000e8b3d14892753a693016cbf0e4a6c8e42" +
                "50154b4525b1046b9d507716cdb05c123009a6a66e7d1fffd9",
                values: [30, 45, 130, 112, 118, 247, 228, 154, 184, 250, 25, 114, 113, 190, 83, 163, 68, 43, 18, 140, 218, 215, 43, 173, 15, 138, 238, 244, 42, 11, 154, 38, 215, 79, 199, 143]),
        ]
        for vector in vectors {
            let description = DICOMPixelDescription(
                rows: vector.rows, columns: vector.columns, samplesPerPixel: vector.samples,
                photometricInterpretation: vector.samples == 3 ? .rgb : .monochrome2,
                bitsAllocated: vector.bits > 8 ? 16 : 8, bitsStored: vector.bits, highBit: vector.bits - 1,
                isSigned: false, planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
            let decoded = try DICOMJPEGLosslessCodec().decode(hexData(vector.stream), description: description)
            let values = try DICOMNativePixelData(description: decoded.description, decodedFrames: decoded.data)
                .storedValues(frame: 0)
            XCTAssertEqual(values, vector.values, vector.name)
        }
    }

    func testInvalidLosslessStreamsAreRejected() throws {
        let description = DICOMPixelDescription(
            rows: 5, columns: 6, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        let codec = DICOMJPEGLosslessCodec()
        XCTAssertThrowsError(try codec.decode(Data([0xFF, 0xD8, 0xFF, 0xD9]), description: description)) {
            XCTAssertEqual($0 as? DICOMCodecError, .corruptedData("JPEG has no frame header"))
        }
        XCTAssertThrowsError(try codec.decode(Data([0x00, 0x01, 0x02, 0x03]), description: description))

        // A baseline (SOF0) header is not JPEG Lossless.
        let baseline = Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x05, 0x00, 0x06, 0x01, 0x01, 0x11, 0x00,
                             0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xFF, 0xD9])
        XCTAssertThrowsError(try codec.decode(baseline, description: description)) {
            XCTAssertEqual($0 as? DICOMCodecError, .unsupportedImage("SOF0 is not JPEG Lossless with Huffman coding"))
        }

        // Truncating the first vector's entropy-coded data must fail or
        // decode different values, never crash.
        let wrongSize = DICOMPixelDescription(
            rows: 6, columns: 6, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 16, bitsStored: 12, highBit: 11, isSigned: false,
            planarConfiguration: 0, numberOfFrames: 1, isEncapsulated: true)
        let stream = hexData(
            "ffd8ffe000104a46494600010100000100010000ffc3000b0c0005000601011100ffc400190000030101010000000000" +
            "0000000000000a0b0c090708ffda00080101000100000a7a9da4fb6f30543126833d7fd3c4d48123c12598ab8a583f60" +
            "6bd2f3a8b54d18d290e64ed59bc74f4e277f017587c97fffd9")
        XCTAssertThrowsError(try codec.decode(stream, description: wrongSize))
        for length in stride(from: 4, to: stream.count, by: 7) {
            _ = try? codec.decode(stream.prefix(length), description: description)
        }
    }

    // MARK: Encoder

    func testEncoderRoundTripsEveryPredictorAndLayout() throws {
        // Streams from this encoder, including restart intervals and point
        // transforms, were verified locally to decode identically with
        // libjpeg-turbo 3.2.0.
        var state: UInt64 = 7
        func random() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        let codec = DICOMJPEGLosslessCodec()
        for (bits, samples, signed) in [(8, 1, false), (12, 1, false), (16, 1, false), (16, 1, true), (8, 3, false)] {
            let layout = self.layout(rows: 9, columns: 7, samples: samples, bits: bits, signed: signed)
            let cell = bits > 8 ? 2 : 1
            var raw: [UInt8] = []
            for index in 0..<(9 * 7 * samples) {
                let value = (index % 13 == 0 ? random() : index * 29 + random() % 7) & ((1 << bits) - 1)
                raw.append(UInt8(value & 0xFF))
                if cell == 2 { raw.append(UInt8(value >> 8)) }
            }
            for predictor in 1...7 {
                for restartLines in [0, 2] {
                    let stream = try codec.encode(Data(raw), description: layout, predictor: predictor,
                                                  restartLines: restartLines)
                    XCTAssertEqual(stream.count % 2, 0)
                    let decoded = try codec.decode(stream, description: layout)
                    XCTAssertEqual([UInt8](decoded.data), raw, "\(bits)-bit \(samples) predictor \(predictor)")
                }
            }
        }
    }

    func testPointTransformDiscardsOnlyTheLowBits() throws {
        let layout = self.layout(rows: 2, columns: 4, samples: 1, bits: 12, signed: false)
        let values = [4095, 0, 1234, 3, 2048, 2047, 17, 4000]
        let raw = Data(values.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        let codec = DICOMJPEGLosslessCodec()
        let stream = try codec.encode(raw, description: layout, predictor: 4, pointTransform: 3)
        let decoded = try codec.decode(stream, description: layout)
        let stored = try DICOMNativePixelData(description: decoded.description, decodedFrames: decoded.data)
            .storedValues(frame: 0)
        XCTAssertEqual(stored, values.map { Int64(($0 >> 3) << 3) })
    }

    func testOptimizedHuffmanCodesNeverExceedSixteenBits() throws {
        // Fibonacci frequencies produce a maximally deep Huffman tree.
        var frequencies = [Int](repeating: 0, count: 256)
        var (a, b) = (1, 1)
        for symbol in 0..<17 {
            frequencies[symbol] = a
            (a, b) = (b, a + b)
        }
        let encoder = JPEGHuffmanEncoder(frequencies: frequencies)
        XCTAssertEqual(encoder.values.count, 17)
        XCTAssertEqual(encoder.counts.count, 16)
        // Kraft sum below 2^16: every code fits and the all-ones code is free.
        let kraft = encoder.counts.enumerated().reduce(0) { $0 + Int($1.element) << (15 - $1.offset) }
        XCTAssertLessThan(kraft, 1 << 16)
        XCTAssertNoThrow(try JPEGHuffmanTable(counts: encoder.counts, values: encoder.values))
    }

    func testEncoderRejectsUnsupportedLayouts() {
        let codec = DICOMJPEGLosslessCodec()
        let wide = DICOMPixelDescription(
            rows: 1, columns: 1, samplesPerPixel: 1, photometricInterpretation: .monochrome2,
            bitsAllocated: 32, bitsStored: 32, highBit: 31, isSigned: false, planarConfiguration: 0, numberOfFrames: 1)
        XCTAssertThrowsError(try codec.encode(Data(count: 4), description: wide))
        let layout = self.layout(rows: 1, columns: 1, samples: 1, bits: 8, signed: false)
        XCTAssertThrowsError(try codec.encode(Data([1]), description: layout, predictor: 8))
        XCTAssertThrowsError(try codec.encode(Data([1]), description: layout, pointTransform: 8))
    }

    private func layout(rows: Int, columns: Int, samples: Int, bits: Int, signed: Bool) -> DICOMPixelDescription {
        DICOMPixelDescription(
            rows: rows, columns: columns, samplesPerPixel: samples,
            photometricInterpretation: samples == 3 ? .rgb : .monochrome2,
            bitsAllocated: bits > 8 ? 16 : 8, bitsStored: bits, highBit: bits - 1, isSigned: signed,
            planarConfiguration: 0, numberOfFrames: 1)
    }

    private func hexData(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }
}
