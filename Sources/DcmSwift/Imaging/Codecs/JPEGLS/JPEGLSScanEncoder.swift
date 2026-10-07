import Foundation

/// Writes JPEG-LS entropy-coded data most significant bit first, stuffing a
/// zero bit after every FFH byte (T.87 9.1).
struct JPEGLSBitWriter {
    private(set) var bytes: [UInt8] = []
    private var accumulator: UInt64 = 0
    private var count = 0
    private var previousWasFF = false

    mutating func write(_ value: Int, bits: Int) {
        guard bits > 0 else { return }
        if bits > 32 {
            write(0, bits: bits - 32)
            write(value, bits: 32)
            return
        }
        accumulator = (accumulator << UInt64(bits)) | (UInt64(truncatingIfNeeded: value) & ((1 << UInt64(bits)) - 1))
        count += bits
        while count >= (previousWasFF ? 7 : 8) { emit(previousWasFF ? 7 : 8) }
    }

    mutating func writeZeros(_ bits: Int) {
        var remaining = bits
        while remaining > 0 {
            let chunk = min(remaining, 32)
            write(0, bits: chunk)
            remaining -= chunk
        }
    }

    private mutating func emit(_ width: Int) {
        let byte = UInt8(truncatingIfNeeded: accumulator >> UInt64(count - width)) & UInt8((1 << width) - 1)
        count -= width
        accumulator &= (1 << UInt64(count)) - 1
        bytes.append(byte)
        previousWasFF = byte == 0xFF
    }

    /// Pads the last byte with zero bits; a final FFH gets a stuffed zero
    /// byte so that a marker can follow.
    mutating func flush() {
        if count > 0 {
            let width = previousWasFF ? 7 : 8
            write(0, bits: width - count)
        }
        if previousWasFF {
            bytes.append(0)
            previousWasFF = false
        }
    }

    mutating func marker(_ code: UInt8) {
        bytes += [0xFF, code]
    }
}

/// Encodes component planes as JPEG-LS scans (T.87 Annex A, encoder side).
struct JPEGLSScanEncoder {
    let width: Int
    let height: Int
    let parameters: JPEGLSStream.CodingParameters
    let restartInterval: Int

    /// Encodes the given components (planes of `width * height` values) as
    /// one scan and returns its entropy-coded data with RST markers.
    func encodeScan(_ planes: [[Int]], interleave: JPEGLSStream.InterleaveMode) -> [UInt8] {
        var writer = JPEGLSBitWriter()
        let sampleInterleaved = interleave == .sample
        var model = JPEGLSContextModel(parameters, runSlots: sampleInterleaved ? 1 : planes.count)
        let buffers = sampleInterleaved
            ? [JPEGLSLineBuffer(width: width, samples: planes.count)]
            : planes.map { _ in JPEGLSLineBuffer(width: width, samples: 1) }
        let source = UnsafeMutablePointer<Int>.allocate(capacity: width * planes.count)
        let qs = UnsafeMutablePointer<Int>.allocate(capacity: 4)
        defer { source.deallocate(); qs.deallocate() }

        var restartIndex = 0
        for row in 0..<height {
            if restartInterval > 0, row > 0, row % restartInterval == 0 {
                writer.flush()
                writer.marker(0xD0 + UInt8(restartIndex % 8))
                restartIndex += 1
                model.resetState()
                buffers.forEach { $0.clear() }
            }
            if sampleInterleaved {
                for x in 0..<width {
                    for (s, plane) in planes.enumerated() { source[x * planes.count + s] = plane[row * width + x] }
                }
                encodeLine(buffers[0], source: source, slot: 0, model: &model, writer: &writer, qs: qs)
            } else {
                for (slot, plane) in planes.enumerated() {
                    for x in 0..<width { source[x] = plane[row * width + x] }
                    encodeLine(buffers[slot], source: source, slot: slot, model: &model, writer: &writer, qs: qs)
                }
            }
        }
        writer.flush()
        return writer.bytes
    }

    private func encodeLine(
        _ buffer: JPEGLSLineBuffer, source: UnsafeMutablePointer<Int>, slot: Int,
        model: inout JPEGLSContextModel, writer: inout JPEGLSBitWriter, qs: UnsafeMutablePointer<Int>
    ) {
        buffer.swap()
        let prev = buffer.previous, cur = buffer.current
        let samples = buffer.samples
        for s in 0..<samples {
            prev[(width + 1) * samples + s] = prev[width * samples + s]
            cur[s] = prev[samples + s]
        }

        var x = 1
        while x <= width {
            var run = true
            for s in 0..<samples {
                let ra = cur[(x - 1) * samples + s], rb = prev[x * samples + s]
                let rc = prev[(x - 1) * samples + s], rd = prev[(x + 1) * samples + s]
                qs[s] = model.context(ra, rb, rc, rd)
                if qs[s] != 0 { run = false }
            }
            if run {
                x += encodeRun(buffer, source: source, at: x, slot: slot, model: &model, writer: &writer)
                continue
            }
            for s in 0..<samples {
                let ra = cur[(x - 1) * samples + s], rb = prev[x * samples + s]
                let rc = prev[(x - 1) * samples + s]
                cur[x * samples + s] = encodeRegular(
                    qs[s], predicted: JPEGLSContextModel.predict(ra, rb, rc),
                    value: source[(x - 1) * samples + s], model: &model, writer: &writer)
            }
            x += 1
        }
    }

    /// Error quantization for near-lossless coding and reduction modulo
    /// RANGE (A.4.4, A.4.5).
    private func reduce(_ error: Int, model: JPEGLSContextModel) -> Int {
        var error = error
        if model.near > 0 {
            error = error > 0 ? (model.near + error) / model.step : -(model.near - error) / model.step
        }
        if error < 0 { error += model.range }
        if error >= (model.range + 1) / 2 { error -= model.range }
        return error
    }

    /// Limited-length Golomb code (A.5.3).
    private func encodeMapped(_ k: Int, _ mapped: Int, limit: Int, model: JPEGLSContextModel, writer: inout JPEGLSBitWriter) {
        let high = mapped >> k
        if high < limit - model.quantizedBits - 1 {
            writer.writeZeros(high)
            writer.write(1, bits: 1)
            writer.write(mapped, bits: k)
        } else {
            writer.writeZeros(limit - model.quantizedBits - 1)
            writer.write(1, bits: 1)
            writer.write(mapped - 1, bits: model.quantizedBits)
        }
    }

    private func encodeRegular(
        _ context: Int, predicted: Int, value: Int, model: inout JPEGLSContextModel, writer: inout JPEGLSBitWriter
    ) -> Int {
        let sign = context < 0 ? -1 : 1
        let q = context * sign
        let corrected = model.clamp(predicted + sign * model.c[q])
        let error = reduce(sign * (value - corrected), model: model)
        // Context variables stay far below 2^24 for valid input.
        let k = (try? model.golombParameter(q)) ?? 0
        var mapped = error >= 0 ? 2 * error : -2 * error - 1
        if k == 0, model.near == 0, 2 * model.b[q] + model.n[q] - 1 < 0 {
            mapped = error >= 0 ? 2 * error + 1 : -2 * (error + 1)
        }
        encodeMapped(k, mapped, limit: model.limit, model: model, writer: &writer)
        try? model.update(q, error: error)
        return model.reconstruct(corrected + sign * error * model.step)
    }

    private func encodeRun(
        _ buffer: JPEGLSLineBuffer, source: UnsafeMutablePointer<Int>, at start: Int, slot: Int,
        model: inout JPEGLSContextModel, writer: inout JPEGLSBitWriter
    ) -> Int {
        let prev = buffer.previous, cur = buffer.current
        let samples = buffer.samples
        var length = 0
        scan: while start + length <= width {
            for s in 0..<samples
            where abs(source[(start + length - 1) * samples + s] - cur[(start - 1) * samples + s]) > model.near {
                break scan
            }
            for s in 0..<samples { cur[(start + length) * samples + s] = cur[(start - 1) * samples + s] }
            length += 1
        }
        let endOfLine = start + length > width

        // Run length (A.7.1.1).
        var remaining = length
        while remaining >= 1 << JPEGLSContextModel.runOrder[model.runIndex[slot]] {
            writer.write(1, bits: 1)
            remaining -= 1 << JPEGLSContextModel.runOrder[model.runIndex[slot]]
            model.runIndex[slot] = min(31, model.runIndex[slot] + 1)
        }
        if endOfLine {
            if remaining != 0 { writer.write(1, bits: 1) }
            return length
        }
        writer.write(remaining, bits: JPEGLSContextModel.runOrder[model.runIndex[slot]] + 1)

        // Run interruption sample (A.7.2).
        let end = start + length
        for s in 0..<samples {
            let ra = cur[(start - 1) * samples + s], rb = prev[end * samples + s]
            let value = source[(end - 1) * samples + s]
            let type = samples == 1 && abs(ra - rb) <= model.near ? 1 : 0
            let direction = rb >= ra ? 1 : -1
            let error = reduce(type == 1 ? value - ra : (value - rb) * direction, model: model)
            let k = (try? model.runGolombParameter(type)) ?? 0
            let nn = model.runNn[type], n = model.runN[type]
            let map = (k == 0 && error > 0 && 2 * nn < n) || (error < 0 && 2 * nn >= n) || (error < 0 && k != 0)
            let mapped = 2 * abs(error) - type - (map ? 1 : 0)
            let limit = model.limit - JPEGLSContextModel.runOrder[model.runIndex[slot]] - 1
            encodeMapped(k, mapped, limit: limit, model: model, writer: &writer)
            model.updateRun(type, error: error, mapped: mapped)
            cur[end * samples + s] = type == 1
                ? model.reconstruct(ra + error * model.step)
                : model.reconstruct(rb + error * direction * model.step)
        }
        model.runIndex[slot] = max(0, model.runIndex[slot] - 1)
        return length + 1
    }
}
