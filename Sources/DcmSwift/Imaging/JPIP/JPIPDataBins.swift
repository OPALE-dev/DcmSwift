import Foundation

/// The data-bin classes of JPIP (ISO/IEC 15444-9 A.2.2).
public enum JPIPDataBinClass: Int, Sendable {
    case precinct = 0
    case extendedPrecinct = 1
    case tileHeader = 2
    case tile = 4
    case extendedTile = 5
    case mainHeader = 6
    case metadata = 8
}

/// A message of a JPP-stream or JPT-stream (ISO/IEC 15444-9 A.2).
public enum JPIPMessage: Equatable, Sendable {
    /// A range of a data-bin: `isLast` when it holds the data-bin's last byte.
    case dataBin(classID: Int, codestream: Int, id: Int, offset: Int, data: Data, isLast: Bool)
    /// End of Response (A.3), with its reason code and body.
    case endOfResponse(reason: UInt8, body: Data)
}

/// End of Response reason codes (ISO/IEC 15444-9 Table D.2).
public enum JPIPEndOfResponseReason: UInt8, Sendable {
    case imageDone = 1
    case windowDone = 2
    case windowChange = 3
    case byteLimitReached = 4
    case qualityLimitReached = 5
    case sessionLimitReached = 6
    case responseLimitReached = 7
    case nonSpecified = 0xFF
}

public struct JPIPError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "JPIP: \(message)" }
}

/// Parses JPP-stream and JPT-stream messages as their bytes arrive. Class
/// and codestream index carry over from one message to the next when a
/// message omits them (A.2.1).
public struct JPIPStreamParser: Sendable {
    private var buffer: [UInt8] = []
    private var lastClass = 0
    private var lastCodestream = 0
    /// Upper bound of a message body, against corrupted lengths.
    public var maximumMessageLength = 1 << 30

    public init() {}

    /// Parses the next bytes; returns the complete messages they finish.
    public mutating func feed(_ bytes: some Sequence<UInt8>) throws -> [JPIPMessage] {
        buffer.append(contentsOf: bytes)
        var messages: [JPIPMessage] = []
        var position = 0
        while let (message, next) = try parse(at: position) {
            messages.append(message)
            position = next
        }
        buffer.removeFirst(position)
        return messages
    }

    /// Checks that no partial message remains.
    public func finish() throws {
        guard buffer.isEmpty else { throw JPIPError("the stream ends inside a message") }
    }

    /// A variable-length byte-aligned segment (A.2.1): 7 bits per byte, the
    /// high bit set on all but the last byte. `firstBits` is the number of
    /// value bits in the first byte.
    private func vbas(at position: Int, firstBits: Int = 7) throws -> (value: Int, next: Int)? {
        var value = 0, index = position, bits = firstBits
        while true {
            guard index < buffer.count else { return nil }
            let byte = Int(buffer[index])
            value = (value << bits) | (byte & ((1 << bits) - 1))
            index += 1
            guard value <= Int(Int32.max) else { throw JPIPError("VBAS value overflows") }
            if byte & 0x80 == 0 { return (value, index) }
            bits = 7
            guard index - position < 9 else { throw JPIPError("VBAS too long") }
        }
    }

    private mutating func parse(at position: Int) throws -> (JPIPMessage, Int)? {
        guard position < buffer.count else { return nil }
        let first = buffer[position]
        if first == 0 {
            // End of Response: 0x00, the reason, then a VBAS body length.
            guard position + 2 <= buffer.count else { return nil }
            let reason = buffer[position + 1]
            guard let (length, start) = try vbas(at: position + 2) else { return nil }
            guard length <= maximumMessageLength else { throw JPIPError("End of Response body too long") }
            guard start + length <= buffer.count else { return nil }
            return (.endOfResponse(reason: reason, body: Data(buffer[start..<(start + length)])), start + length)
        }
        // Bin-ID: bits 6-5 say whether Class and CSn follow, bit 4 marks the
        // last byte of the data-bin, bits 3-0 start the in-class identifier.
        let indicator = Int(first >> 5) & 3
        guard indicator != 0 else { throw JPIPError("invalid Bin-ID indicator") }
        let isLast = first & 0x10 != 0
        var id = Int(first & 0x0F), next = position + 1
        if first & 0x80 != 0 {
            guard let (rest, after) = try vbas(at: next) else { return nil }
            // The continuation bytes extend the 4 bits of the first byte.
            var digits = 0, probe = next
            while probe < after { digits += 1; probe += 1 }
            id = (id << (7 * digits)) | rest
            next = after
        }
        var classID = lastClass, codestream = lastCodestream
        if indicator >= 2 {
            guard let (value, after) = try vbas(at: next) else { return nil }
            classID = value
            next = after
        }
        if indicator == 3 {
            guard let (value, after) = try vbas(at: next) else { return nil }
            codestream = value
            next = after
        }
        guard let (offset, afterOffset) = try vbas(at: next), let (length, afterLength) = try vbas(at: afterOffset) else {
            return nil
        }
        next = afterLength
        // Extended classes carry an auxiliary value.
        if classID % 2 == 1 {
            guard let (_, after) = try vbas(at: next) else { return nil }
            next = after
        }
        guard length <= maximumMessageLength else { throw JPIPError("message body too long") }
        guard next + length <= buffer.count else { return nil }
        lastClass = classID
        lastCodestream = codestream
        let data = Data(buffer[next..<(next + length)])
        return (.dataBin(classID: classID, codestream: codestream, id: id, offset: offset, data: data, isLast: isLast),
                next + length)
    }
}

/// The data-bins received so far, assembled from their message ranges
/// (ISO/IEC 15444-9 C.4, the client cache).
public struct JPIPCache: Sendable {
    struct Key: Hashable, Sendable {
        let classID: Int
        let codestream: Int
        let id: Int
    }

    struct Bin: Sendable {
        var bytes: [UInt8] = []
        /// Received ranges, merged.
        var ranges: [Range<Int>] = []
        /// The data-bin length, once its last byte arrived.
        var length: Int?

        var isComplete: Bool { length.map { ranges == [0..<$0] || $0 == 0 } ?? false }

        /// The bytes received from the start without a gap.
        var prefix: Data {
            guard let first = ranges.first, first.lowerBound == 0 else { return Data() }
            return Data(bytes[first])
        }

        mutating func add(offset: Int, data: Data, isLast: Bool) {
            let end = offset + data.count
            if bytes.count < end { bytes.append(contentsOf: [UInt8](repeating: 0, count: end - bytes.count)) }
            bytes.replaceSubrange(offset..<end, with: data)
            if isLast { length = end }
            guard !data.isEmpty else { return }
            ranges.append(offset..<end)
            ranges.sort { $0.lowerBound < $1.lowerBound }
            var merged: [Range<Int>] = []
            for range in ranges {
                if let last = merged.last, range.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
                } else {
                    merged.append(range)
                }
            }
            ranges = merged
        }
    }

    private(set) var bins: [Key: Bin] = [:]
    /// The largest data-bin accepted, against offsets that would make the
    /// cache allocate unbounded memory.
    public var maximumDataBinLength: Int
    /// The most bytes all data-bins may hold together.
    public var maximumTotalLength: Int
    private var totalLength = 0

    public init(maximumDataBinLength: Int = 1 << 28, maximumTotalLength: Int = 1 << 31) {
        self.maximumDataBinLength = maximumDataBinLength
        self.maximumTotalLength = maximumTotalLength
    }

    public mutating func add(_ message: JPIPMessage) throws {
        guard case .dataBin(let classID, let codestream, let id, let offset, let data, let isLast) = message else { return }
        guard offset + data.count <= maximumDataBinLength else {
            throw JPIPError("a data-bin exceeds \(maximumDataBinLength) bytes")
        }
        // Extended classes hold the same data as their plain counterpart.
        let plain = classID == JPIPDataBinClass.extendedPrecinct.rawValue ? JPIPDataBinClass.precinct.rawValue
            : classID == JPIPDataBinClass.extendedTile.rawValue ? JPIPDataBinClass.tile.rawValue : classID
        let key = Key(classID: plain, codestream: codestream, id: id)
        let before = bins[key]?.bytes.count ?? 0
        totalLength += max(0, offset + data.count - before)
        guard totalLength <= maximumTotalLength else { throw JPIPError("the data-bins exceed \(maximumTotalLength) bytes") }
        bins[key, default: Bin()].add(offset: offset, data: data, isLast: isLast)
    }

    /// The contents of a data-bin received from its start, and whether the
    /// whole data-bin is there.
    public func dataBin(_ classID: JPIPDataBinClass, codestream: Int, id: Int) -> (data: Data, isComplete: Bool)? {
        guard let bin = bins[Key(classID: classID.rawValue, codestream: codestream, id: id)] else { return nil }
        return (bin.prefix, bin.isComplete)
    }

    /// The codestream indices that have a main header data-bin.
    public var codestreams: [Int] {
        Set(bins.keys.filter { $0.classID == JPIPDataBinClass.mainHeader.rawValue }.map(\.codestream)).sorted()
    }

    /// Whether any tile data-bin was received (a JPT-stream).
    func hasTiles(codestream: Int) -> Bool {
        bins.keys.contains { $0.classID == JPIPDataBinClass.tile.rawValue && $0.codestream == codestream }
    }
}
