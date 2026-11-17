import Foundation

/// Sequential Huffman DCT encoder matching the IJG integer pipeline.
struct JPEGDCTEncoder {
    private struct Component {
        let horizontal: Int
        let vertical: Int
        let quantizationTable: Int
        let huffmanTable: Int
        let width: Int
        let height: Int
        let stride: Int
        let samples: [Int]
    }

    private struct Block {
        let component: Int
        let coefficients: [Int32]
    }

    private static let lumaQuantization = [
        16, 11, 10, 16, 24, 40, 51, 61,
        12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56,
        14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77,
        24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101,
        72, 92, 95, 98, 112, 100, 103, 99,
    ]

    private static let chromaQuantization = [
        17, 18, 24, 47, 99, 99, 99, 99,
        18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99,
        47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
    ]

    let frame: Data
    let description: DICOMPixelDescription
    let quality: Int
    let subsampling: DICOMJPEGBaselineCodec.Subsampling
    let restartInterval: Int

    func encode() throws -> (data: Data, photometric: DICOMPhotometricInterpretation) {
        let precision = description.bitsStored
        guard description.sampleFormat == .integer, !description.isSigned,
              precision == 8 || precision == 12,
              description.bitsAllocated == (precision == 8 ? 8 : 16),
              description.rows <= 0xFFFF, description.columns <= 0xFFFF else {
            throw DICOMCodecError.unsupportedImage(
                "JPEG DCT encoding needs unsigned 8-bit or 12-bit integer samples and dimensions up to 65535")
        }
        let isMonochrome = description.samplesPerPixel == 1
            && description.photometricInterpretation.isMonochrome
        let isRGB = description.samplesPerPixel == 3
            && description.photometricInterpretation == .rgb
        guard isMonochrome || isRGB else {
            throw DICOMCodecError.unsupportedImage("JPEG DCT encoding accepts MONOCHROME1/2 or RGB frames")
        }
        guard (1...100).contains(quality), (0...0xFFFF).contains(restartInterval) else {
            throw DICOMCodecError.unsupportedImage("JPEG quality must be 1...100 and restart interval 0...65535")
        }

        let stored = try DICOMNativePixelData(description: description.decodedFrame(), decodedFrames: frame)
            .storedValues(frame: 0).map(Int.init)
        let fullPlanes = isRGB ? rgbToYCbCr(stored, precision: precision) : [stored]
        let sampling: [(Int, Int)]
        if isMonochrome {
            sampling = [(1, 1)]
        } else {
            switch subsampling {
            case .s444: sampling = [(1, 1), (1, 1), (1, 1)]
            case .s422: sampling = [(2, 1), (1, 1), (1, 1)]
            case .s420: sampling = [(2, 2), (1, 1), (1, 1)]
            }
        }
        let maximumHorizontal = sampling.map(\.0).max()!
        let maximumVertical = sampling.map(\.1).max()!
        let mcusAcross = (description.columns + 8 * maximumHorizontal - 1) / (8 * maximumHorizontal)
        let mcusDown = (description.rows + 8 * maximumVertical - 1) / (8 * maximumVertical)
        let components = fullPlanes.enumerated().map { index, plane -> Component in
            let horizontalScale = maximumHorizontal / sampling[index].0
            let verticalScale = maximumVertical / sampling[index].1
            let downsampled = downsample(
                plane, width: description.columns, height: description.rows,
                horizontal: horizontalScale, vertical: verticalScale,
                outputWidth: mcusAcross * sampling[index].0 * 8,
                outputHeight: mcusDown * sampling[index].1 * 8)
            return Component(
                horizontal: sampling[index].0, vertical: sampling[index].1,
                quantizationTable: index == 0 ? 0 : 1,
                huffmanTable: index == 0 ? 0 : 1,
                width: downsampled.width, height: downsampled.height,
                stride: downsampled.stride,
                samples: downsampled.samples)
        }

        let quantization = [
            scaledQuantization(Self.lumaQuantization, precision: precision),
            scaledQuantization(Self.chromaQuantization, precision: precision),
        ]
        var mcus = [[Block]]()
        mcus.reserveCapacity(mcusAcross * mcusDown)
        var previousDC = [Int32](repeating: 0, count: components.count)
        let workspace = UnsafeMutablePointer<Int>.allocate(capacity: 64)
        let output = UnsafeMutablePointer<Int32>.allocate(capacity: 64)
        defer { workspace.deallocate(); output.deallocate() }

        for mcuRow in 0..<mcusDown {
            for mcuColumn in 0..<mcusAcross {
                var blocks = [Block]()
                for (componentIndex, component) in components.enumerated() {
                    let realColumns = (component.width + 7) / 8
                    let realRows = (component.height + 7) / 8
                    for blockRow in 0..<component.vertical {
                        for blockColumn in 0..<component.horizontal {
                            let column = mcuColumn * component.horizontal + blockColumn
                            let row = mcuRow * component.vertical + blockRow
                            var coefficients = [Int32](repeating: 0, count: 64)
                            if column >= realColumns || row >= realRows {
                                coefficients[0] = previousDC[componentIndex]
                            } else {
                                for y in 0..<8 {
                                    for x in 0..<8 {
                                        let sourceY = row * 8 + y
                                        let sourceX = column * 8 + x
                                        workspace[y * 8 + x] = component.samples[sourceY * component.stride + sourceX]
                                            - (1 << (precision - 1))
                                    }
                                }
                                JPEGFDCT.forward(workspace, precision: precision)
                                JPEGFDCT.quantize(
                                    workspace, table: quantization[component.quantizationTable], into: output)
                                for index in 0..<64 { coefficients[index] = output[index] }
                                previousDC[componentIndex] = coefficients[0]
                            }
                            blocks.append(Block(component: componentIndex, coefficients: coefficients))
                        }
                    }
                }
                mcus.append(blocks)
            }
        }

        var dcFrequencies = [[Int]](repeating: [Int](repeating: 0, count: 256), count: isMonochrome ? 1 : 2)
        var acFrequencies = dcFrequencies
        var predictions = [Int32](repeating: 0, count: components.count)
        for (mcuIndex, blocks) in mcus.enumerated() {
            if restartInterval > 0 && mcuIndex > 0 && mcuIndex % restartInterval == 0 {
                predictions = predictions.map { _ in 0 }
            }
            for block in blocks {
                let table = components[block.component].huffmanTable
                let difference = Int(block.coefficients[0] - predictions[block.component])
                predictions[block.component] = block.coefficients[0]
                dcFrequencies[table][Self.category(difference)] += 1
                countAC(block.coefficients, frequencies: &acFrequencies[table])
            }
        }
        let dcTables = dcFrequencies.map(JPEGHuffmanEncoder.init(frequencies:))
        let acTables = acFrequencies.map(JPEGHuffmanEncoder.init(frequencies:))

        var bitWriter = JPEGBitWriter()
        predictions = predictions.map { _ in 0 }
        var restartIndex = 0
        for (mcuIndex, blocks) in mcus.enumerated() {
            if restartInterval > 0 && mcuIndex > 0 && mcuIndex % restartInterval == 0 {
                bitWriter.restartMarker(restartIndex)
                restartIndex += 1
                predictions = predictions.map { _ in 0 }
            }
            for block in blocks {
                let table = components[block.component].huffmanTable
                let difference = Int(block.coefficients[0] - predictions[block.component])
                predictions[block.component] = block.coefficients[0]
                Self.write(difference, table: dcTables[table], to: &bitWriter)
                writeAC(block.coefficients, table: acTables[table], to: &bitWriter)
            }
        }
        bitWriter.flush()

        var stream: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ payload: [UInt8]) {
            stream += [0xFF, marker, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)] + payload
        }
        segment(0xE0, Array("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0])
        var dqt = quantizationPayload(quantization[0], identifier: 0)
        if !isMonochrome { dqt += quantizationPayload(quantization[1], identifier: 1) }
        segment(0xDB, dqt)
        var frameHeader: [UInt8] = [
            UInt8(precision), UInt8(description.rows >> 8), UInt8(description.rows & 0xFF),
            UInt8(description.columns >> 8), UInt8(description.columns & 0xFF), UInt8(components.count),
        ]
        for (index, component) in components.enumerated() {
            frameHeader += [
                UInt8(index + 1), UInt8(component.horizontal << 4 | component.vertical),
                UInt8(component.quantizationTable),
            ]
        }
        segment(precision == 8 ? 0xC0 : 0xC1, frameHeader)
        var dht: [UInt8] = []
        for index in dcTables.indices {
            dht += dcTables[index].specification(tableClass: 0, identifier: UInt8(index))
            dht += acTables[index].specification(tableClass: 1, identifier: UInt8(index))
        }
        segment(0xC4, dht)
        if restartInterval > 0 {
            segment(0xDD, [UInt8(restartInterval >> 8), UInt8(restartInterval & 0xFF)])
        }
        var scanHeader: [UInt8] = [UInt8(components.count)]
        for (index, component) in components.enumerated() {
            scanHeader += [UInt8(index + 1), UInt8(component.huffmanTable << 4 | component.huffmanTable)]
        }
        scanHeader += [0, 63, 0]
        segment(0xDA, scanHeader)
        stream += bitWriter.bytes
        stream += [0xFF, 0xD9]
        if stream.count % 2 == 1 { stream.append(0) }

        let photometric: DICOMPhotometricInterpretation
        if isMonochrome {
            photometric = description.photometricInterpretation
        } else {
            photometric = subsampling == .s444 ? .ybrFull : .ybrFull422
        }
        return (Data(stream), photometric)
    }

    private func scaledQuantization(_ base: [Int], precision: Int) -> [Int] {
        let scale = quality < 50 ? 5000 / quality : 200 - 2 * quality
        let maximum = precision == 8 ? 255 : 32767
        return base.map { min(max(($0 * scale + 50) / 100, 1), maximum) }
    }

    private func rgbToYCbCr(_ pixels: [Int], precision: Int) -> [[Int]] {
        let center = 1 << (precision - 1)
        let maximum = (1 << precision) - 1
        var planes = [[Int]](repeating: [], count: 3)
        for index in stride(from: 0, to: pixels.count, by: 3) {
            let r = pixels[index], g = pixels[index + 1], b = pixels[index + 2]
            let y = (19595 * r + 38470 * g + 7471 * b + 32768) >> 16
            let cb = (-11059 * r - 21709 * g + 32768 * b + (center << 16) + 32767) >> 16
            let cr = (32768 * r - 27439 * g - 5329 * b + (center << 16) + 32767) >> 16
            planes[0].append(min(max(y, 0), maximum))
            planes[1].append(min(max(cb, 0), maximum))
            planes[2].append(min(max(cr, 0), maximum))
        }
        return planes
    }

    private func downsample(
        _ input: [Int], width: Int, height: Int, horizontal: Int, vertical: Int,
        outputWidth: Int, outputHeight: Int
    ) -> (samples: [Int], width: Int, height: Int, stride: Int) {
        let logicalWidth = (width + horizontal - 1) / horizontal
        let logicalHeight = (height + vertical - 1) / vertical
        var output = [Int](repeating: 0, count: outputWidth * outputHeight)
        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let x0 = min(x * horizontal, width - 1)
                let x1 = min(x0 + 1, width - 1)
                let y0 = min(y * vertical, height - 1)
                if horizontal == 1 && vertical == 1 {
                    output[y * outputWidth + x] = input[y0 * width + x0]
                } else if vertical == 1 {
                    output[y * outputWidth + x] = (input[y0 * width + x0] + input[y0 * width + x1] + (x & 1)) >> 1
                } else {
                    let y1 = min(y0 + 1, height - 1)
                    let sum = input[y0 * width + x0] + input[y0 * width + x1]
                        + input[y1 * width + x0] + input[y1 * width + x1]
                    output[y * outputWidth + x] = (sum + (x & 1 == 0 ? 1 : 2)) >> 2
                }
            }
        }
        return (output, logicalWidth, logicalHeight, outputWidth)
    }

    private func quantizationPayload(_ table: [Int], identifier: Int) -> [UInt8] {
        let wide = table.contains { $0 > 255 }
        var result: [UInt8] = [UInt8((wide ? 0x10 : 0) | identifier)]
        for zigzag in 0..<64 {
            let value = table[JPEGIDCT.naturalOrder[zigzag]]
            if wide { result += [UInt8(value >> 8), UInt8(value & 0xFF)] } else { result.append(UInt8(value)) }
        }
        return result
    }

    private static func category(_ value: Int) -> Int {
        var magnitude = abs(value)
        var count = 0
        while magnitude > 0 { magnitude >>= 1; count += 1 }
        return count
    }

    private func countAC(_ coefficients: [Int32], frequencies: inout [Int]) {
        var zeroes = 0
        for zigzag in 1..<64 {
            let value = Int(coefficients[JPEGIDCT.naturalOrder[zigzag]])
            if value == 0 { zeroes += 1; continue }
            while zeroes >= 16 { frequencies[0xF0] += 1; zeroes -= 16 }
            frequencies[zeroes << 4 | Self.category(value)] += 1
            zeroes = 0
        }
        if zeroes > 0 { frequencies[0] += 1 }
    }

    private static func write(_ value: Int, table: JPEGHuffmanEncoder, to writer: inout JPEGBitWriter) {
        let size = category(value)
        table.write(size, to: &writer)
        if size > 0 { writer.write(value < 0 ? value - 1 : value, bits: size) }
    }

    private func writeAC(_ coefficients: [Int32], table: JPEGHuffmanEncoder, to writer: inout JPEGBitWriter) {
        var zeroes = 0
        for zigzag in 1..<64 {
            let value = Int(coefficients[JPEGIDCT.naturalOrder[zigzag]])
            if value == 0 { zeroes += 1; continue }
            while zeroes >= 16 { table.write(0xF0, to: &writer); zeroes -= 16 }
            let size = Self.category(value)
            table.write(zeroes << 4 | size, to: &writer)
            writer.write(value < 0 ? value - 1 : value, bits: size)
            zeroes = 0
        }
        if zeroes > 0 { table.write(0, to: &writer) }
    }
}
