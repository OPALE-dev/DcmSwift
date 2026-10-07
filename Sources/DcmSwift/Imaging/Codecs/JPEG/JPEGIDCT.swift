import Foundation

/// The accurate integer inverse DCT of the Independent JPEG Group
/// (`jpeg_idct_islow`, Loeffler, Ligtenberg and Moschytz), reproduced so that
/// DcmSwift decodes lossy JPEG identically to IJG-derived decoders such as
/// libjpeg-turbo, DCMTK, and GDCM.
enum JPEGIDCT {
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

    /// Natural (row-major) order of each zig-zag index (T.81 Figure A.6).
    static let naturalOrder: [Int] = [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
    ]

    /// Transforms one block of dequantized coefficients (natural order) into
    /// level-shifted, range-limited samples written at `output` with the
    /// given row stride. `workspace` holds 64 integers reused across blocks.
    static func inverse(
        _ c: UnsafePointer<Int32>, precision: Int,
        output: UnsafeMutablePointer<UInt16>, stride: Int,
        workspace w: UnsafeMutablePointer<Int>
    ) {
        // IJG uses one fractional pass-1 bit fewer for 12-bit samples.
        let pass1Bits = precision > 8 ? 1 : 2
        let maximum = (1 << precision) - 1
        let center = 1 << (precision - 1)
        let shift1 = constBits - pass1Bits
        let round1 = 1 << (shift1 - 1)

        // Pass 1: columns, results scaled up by 2^pass1Bits.
        for column in 0..<8 {
            if c[8 + column] == 0 && c[16 + column] == 0 && c[24 + column] == 0 && c[32 + column] == 0
                && c[40 + column] == 0 && c[48 + column] == 0 && c[56 + column] == 0 {
                let dc = Int(c[column]) << pass1Bits
                for row in 0..<8 { w[row * 8 + column] = dc }
                continue
            }
            var z2 = Int(c[16 + column]), z3 = Int(c[48 + column])
            var z1 = (z2 + z3) * fix0541196100
            var tmp2 = z1 + z3 * -fix1847759065
            var tmp3 = z1 + z2 * fix0765366865
            z2 = Int(c[column])
            z3 = Int(c[32 + column])
            var tmp0 = (z2 + z3) << constBits
            var tmp1 = (z2 - z3) << constBits
            let tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3
            let tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2

            tmp0 = Int(c[56 + column]); tmp1 = Int(c[40 + column]); tmp2 = Int(c[24 + column]); tmp3 = Int(c[8 + column])
            z1 = tmp0 + tmp3
            z2 = tmp1 + tmp2
            z3 = tmp0 + tmp2
            var z4 = tmp1 + tmp3
            let z5 = (z3 + z4) * fix1175875602
            tmp0 *= fix0298631336; tmp1 *= fix2053119869; tmp2 *= fix3072711026; tmp3 *= fix1501321110
            z1 *= -fix0899976223; z2 *= -fix2562915447; z3 *= -fix1961570560; z4 *= -fix0390180644
            z3 += z5; z4 += z5
            tmp0 += z1 + z3; tmp1 += z2 + z4; tmp2 += z2 + z3; tmp3 += z1 + z4

            w[column] = (tmp10 + tmp3 + round1) >> shift1
            w[56 + column] = (tmp10 - tmp3 + round1) >> shift1
            w[8 + column] = (tmp11 + tmp2 + round1) >> shift1
            w[48 + column] = (tmp11 - tmp2 + round1) >> shift1
            w[16 + column] = (tmp12 + tmp1 + round1) >> shift1
            w[40 + column] = (tmp12 - tmp1 + round1) >> shift1
            w[24 + column] = (tmp13 + tmp0 + round1) >> shift1
            w[32 + column] = (tmp13 - tmp0 + round1) >> shift1
        }

        // Pass 2: rows, removing the pass-1 scaling and the factor 8; the
        // rounding term and level shift are folded in before the shift.
        let shift2 = constBits + pass1Bits + 3
        let offset2 = (1 << (shift2 - 1)) + (center << shift2)
        @inline(__always) func limit(_ value: Int) -> UInt16 {
            let sample = (value + offset2) >> shift2
            return UInt16(sample < 0 ? 0 : (sample > maximum ? maximum : sample))
        }
        for row in 0..<8 {
            let r = w + row * 8
            var z2 = r[2], z3 = r[6]
            var z1 = (z2 + z3) * fix0541196100
            var tmp2 = z1 + z3 * -fix1847759065
            var tmp3 = z1 + z2 * fix0765366865
            var tmp0 = (r[0] + r[4]) << constBits
            var tmp1 = (r[0] - r[4]) << constBits
            let tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3
            let tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2

            tmp0 = r[7]; tmp1 = r[5]; tmp2 = r[3]; tmp3 = r[1]
            z1 = tmp0 + tmp3
            z2 = tmp1 + tmp2
            z3 = tmp0 + tmp2
            var z4 = tmp1 + tmp3
            let z5 = (z3 + z4) * fix1175875602
            tmp0 *= fix0298631336; tmp1 *= fix2053119869; tmp2 *= fix3072711026; tmp3 *= fix1501321110
            z1 *= -fix0899976223; z2 *= -fix2562915447; z3 *= -fix1961570560; z4 *= -fix0390180644
            z3 += z5; z4 += z5
            tmp0 += z1 + z3; tmp1 += z2 + z4; tmp2 += z2 + z3; tmp3 += z1 + z4

            let o = output + row * stride
            o[0] = limit(tmp10 + tmp3); o[7] = limit(tmp10 - tmp3)
            o[1] = limit(tmp11 + tmp2); o[6] = limit(tmp11 - tmp2)
            o[2] = limit(tmp12 + tmp1); o[5] = limit(tmp12 - tmp1)
            o[3] = limit(tmp13 + tmp0); o[4] = limit(tmp13 - tmp0)
        }
    }
}
