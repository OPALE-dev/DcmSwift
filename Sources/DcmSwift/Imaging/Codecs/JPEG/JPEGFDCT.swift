import Foundation

/// The accurate integer forward DCT of the Independent JPEG Group
/// (`jpeg_fdct_islow`) and its quantization (`jcdctmgr.c`), reproduced so
/// that DcmSwift compresses exactly like IJG-derived encoders.
enum JPEGFDCT {
    private static let constBits = 13
    private static let fix0298631336 = 2446
    private static let fix0390180644 = 3196
    private static let fix0541196100 = 4433
    private static let fix0765366865 = 6270
    private static let fix0899976223 = 7373
    private static let fix1175875602 = 9633
    private static let fix1501321110 = 12299
    private static let fix1847759065 = 15137
    private static let fix1961570560 = 16069
    private static let fix2053119869 = 16819
    private static let fix2562915447 = 20995
    private static let fix3072711026 = 25172

    /// Transforms an 8x8 block of level-shifted samples (row-major) in place.
    /// Outputs are scaled up by 8, as in IJG.
    static func forward(_ d: UnsafeMutablePointer<Int>, precision: Int) {
        let pass1Bits = precision > 8 ? 1 : 2
        @inline(__always) func descale(_ value: Int, _ bits: Int) -> Int { (value + (1 << (bits - 1))) >> bits }

        // Pass 1: rows, results scaled up by 2^pass1Bits.
        for row in 0..<8 {
            let p = d + row * 8
            let tmp0 = p[0] + p[7], tmp7 = p[0] - p[7]
            let tmp1 = p[1] + p[6], tmp6 = p[1] - p[6]
            let tmp2 = p[2] + p[5], tmp5 = p[2] - p[5]
            let tmp3 = p[3] + p[4], tmp4 = p[3] - p[4]
            let tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3
            let tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2
            p[0] = (tmp10 + tmp11) << pass1Bits
            p[4] = (tmp10 - tmp11) << pass1Bits
            let z1 = (tmp12 + tmp13) * fix0541196100
            p[2] = descale(z1 + tmp13 * fix0765366865, constBits - pass1Bits)
            p[6] = descale(z1 + tmp12 * -fix1847759065, constBits - pass1Bits)
            odd(tmp4, tmp5, tmp6, tmp7, shift: constBits - pass1Bits) { p[7] = $0; p[5] = $1; p[3] = $2; p[1] = $3 }
        }
        // Pass 2: columns, removing the pass-1 scaling.
        for column in 0..<8 {
            let p = d + column
            let tmp0 = p[0] + p[56], tmp7 = p[0] - p[56]
            let tmp1 = p[8] + p[48], tmp6 = p[8] - p[48]
            let tmp2 = p[16] + p[40], tmp5 = p[16] - p[40]
            let tmp3 = p[24] + p[32], tmp4 = p[24] - p[32]
            let tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3
            let tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2
            p[0] = descale(tmp10 + tmp11, pass1Bits)
            p[32] = descale(tmp10 - tmp11, pass1Bits)
            let z1 = (tmp12 + tmp13) * fix0541196100
            p[16] = descale(z1 + tmp13 * fix0765366865, constBits + pass1Bits)
            p[48] = descale(z1 + tmp12 * -fix1847759065, constBits + pass1Bits)
            odd(tmp4, tmp5, tmp6, tmp7, shift: constBits + pass1Bits) { p[56] = $0; p[40] = $1; p[24] = $2; p[8] = $3 }
        }
    }

    /// The odd part shared by both passes: outputs 7, 5, 3, 1.
    @inline(__always)
    private static func odd(
        _ t4: Int, _ t5: Int, _ t6: Int, _ t7: Int, shift: Int, _ store: (Int, Int, Int, Int) -> Void
    ) {
        var z1 = t4 + t7, z2 = t5 + t6, z3 = t4 + t6, z4 = t5 + t7
        let z5 = (z3 + z4) * fix1175875602
        let tmp4 = t4 * fix0298631336, tmp5 = t5 * fix2053119869
        let tmp6 = t6 * fix3072711026, tmp7 = t7 * fix1501321110
        z1 *= -fix0899976223; z2 *= -fix2562915447; z3 *= -fix1961570560; z4 *= -fix0390180644
        z3 += z5; z4 += z5
        let round = 1 << (shift - 1)
        let out7: Int = (tmp4 + z1 + z3 + round) >> shift
        let out5: Int = (tmp5 + z2 + z4 + round) >> shift
        let out3: Int = (tmp6 + z2 + z3 + round) >> shift
        let out1: Int = (tmp7 + z1 + z4 + round) >> shift
        store(out7, out5, out3, out1)
    }

    /// Quantizes DCT outputs (natural order, scaled by 8) with rounding to
    /// nearest, as IJG divides by the quantizer times 8.
    static func quantize(_ d: UnsafePointer<Int>, table: [Int], into output: UnsafeMutablePointer<Int32>) {
        for index in 0..<64 {
            let divisor = table[index] << 3
            let value = d[index]
            let half = divisor >> 1
            let quotient: Int
            if value < 0 {
                quotient = -((half - value) / divisor)
            } else {
                quotient = (value + half) / divisor
            }
            output[index] = Int32(quotient)
        }
    }
}
