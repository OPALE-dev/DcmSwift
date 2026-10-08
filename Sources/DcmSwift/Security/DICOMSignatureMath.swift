import Foundation

/// RIPEMD-160 (ISO/IEC 10118-3), one of the MAC algorithms PS3.15 C.1
/// requires validators to support, and DCMTK's default.
enum RIPEMD160 {
    private static let left: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12, 1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
    ]
    private static let right: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12, 6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13, 8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
    ]
    private static let leftShifts: [UInt32] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8, 7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5, 11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
    ]
    private static let rightShifts: [UInt32] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6, 9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5, 15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
    ]
    private static let leftConstants: [UInt32] = [0x0000_0000, 0x5A82_7999, 0x6ED9_EBA1, 0x8F1B_BCDC, 0xA953_FD4E]
    private static let rightConstants: [UInt32] = [0x50A2_8BE6, 0x5C4D_D124, 0x6D70_3EF3, 0x7A6D_76E9, 0x0000_0000]

    private static func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch j / 16 {
        case 0: return x ^ y ^ z
        case 1: return (x & y) | (~x & z)
        case 2: return (x | ~y) ^ z
        case 3: return (x & z) | (y & ~z)
        default: return x ^ (y | ~z)
        }
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }

    static func hash(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let bits = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 0, to: 64, by: 8) { message.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        for block in stride(from: 0, to: message.count, by: 64) {
            let x = (0..<16).map { word -> UInt32 in
                let offset = block + word * 4
                return UInt32(message[offset]) | UInt32(message[offset + 1]) << 8
                    | UInt32(message[offset + 2]) << 16 | UInt32(message[offset + 3]) << 24
            }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            var (a2, b2, c2, d2, e2) = (h[0], h[1], h[2], h[3], h[4])
            for j in 0..<80 {
                var t = rotate(a &+ f(j, b, c, d) &+ x[left[j]] &+ leftConstants[j / 16], leftShifts[j]) &+ e
                (a, e, d, c, b) = (e, d, rotate(c, 10), b, t)
                t = rotate(a2 &+ f(79 - j, b2, c2, d2) &+ x[right[j]] &+ rightConstants[j / 16], rightShifts[j]) &+ e2
                (a2, e2, d2, c2, b2) = (e2, d2, rotate(c2, 10), b2, t)
            }
            let t = h[1] &+ c &+ d2
            h[1] = h[2] &+ d &+ e2
            h[2] = h[3] &+ e &+ a2
            h[3] = h[4] &+ a &+ b2
            h[4] = h[0] &+ b &+ c2
            h[0] = t
        }
        return h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32($0 * 8)) } }
    }
}

/// The RSA public operation, s^e mod n, on unsigned integers of 32-bit
/// limbs, least significant first: enough to verify PKCS #1 v1.5
/// signatures whatever their hash function.
struct RSAPublicOperation {
    let modulus: [UInt32]
    let exponent: [UInt32]
    let byteCount: Int

    init?(modulus: [UInt8], exponent: [UInt8]) {
        let modulus = Array(modulus.drop { $0 == 0 })
        guard !modulus.isEmpty else { return nil }
        self.modulus = Self.limbs(modulus)
        self.exponent = Self.limbs(exponent)
        byteCount = modulus.count
    }

    /// s^e mod n as big-endian bytes of the modulus length; nil when s is
    /// not below n.
    func apply(_ signature: [UInt8]) -> [UInt8]? {
        let base = Self.limbs(signature)
        guard Self.compare(base, modulus) < 0 else { return nil }
        var result: [UInt32] = [1]
        for limb in exponent.reversed() {
            for bit in (0..<32).reversed() {
                result = reduce(Self.multiply(result, result))
                if limb >> UInt32(bit) & 1 == 1 { result = reduce(Self.multiply(result, base)) }
            }
        }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for (index, limb) in result.enumerated() {
            for byte in 0..<4 {
                let position = byteCount - 1 - (index * 4 + byte)
                if position >= 0 { bytes[position] = UInt8(truncatingIfNeeded: limb >> UInt32(byte * 8)) }
            }
        }
        return bytes
    }

    static func limbs(_ bytes: [UInt8]) -> [UInt32] {
        var limbs = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (index, byte) in bytes.reversed().enumerated() { limbs[index / 4] |= UInt32(byte) << UInt32(index % 4 * 8) }
        while limbs.count > 1, limbs.last == 0 { limbs.removeLast() }
        return limbs.isEmpty ? [0] : limbs
    }

    static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let a = trimmed(a), b = trimmed(b)
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for index in a.indices.reversed() where a[index] != b[index] { return a[index] < b[index] ? -1 : 1 }
        return 0
    }

    private static func trimmed(_ value: [UInt32]) -> ArraySlice<UInt32> {
        var end = value.count
        while end > 1, value[end - 1] == 0 { end -= 1 }
        return value[0..<end]
    }

    static func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var product = [UInt32](repeating: 0, count: a.count + b.count)
        for i in a.indices {
            var carry: UInt64 = 0
            for j in b.indices {
                let value = UInt64(a[i]) * UInt64(b[j]) + UInt64(product[i + j]) + carry
                product[i + j] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
            }
            product[i + b.count] = UInt32(carry)
        }
        return product
    }

    /// value mod n, bit by bit.
    private func reduce(_ value: [UInt32]) -> [UInt32] {
        var remainder = [UInt32](repeating: 0, count: modulus.count + 1)
        for limb in value.reversed() {
            for bit in (0..<32).reversed() {
                // remainder = remainder * 2 + bit
                var carry = limb >> UInt32(bit) & 1
                for index in remainder.indices {
                    let next = remainder[index] >> 31
                    remainder[index] = remainder[index] << 1 | carry
                    carry = next
                }
                if Self.compare(remainder, modulus) >= 0 { Self.subtract(&remainder, modulus) }
            }
        }
        return Array(Self.trimmed(remainder))
    }

    private static func subtract(_ a: inout [UInt32], _ b: [UInt32]) {
        var borrow: Int64 = 0
        for index in a.indices {
            var value = Int64(a[index]) - borrow - (index < b.count ? Int64(b[index]) : 0)
            borrow = 0
            if value < 0 {
                value += 1 << 32
                borrow = 1
            }
            a[index] = UInt32(value)
        }
    }
}
