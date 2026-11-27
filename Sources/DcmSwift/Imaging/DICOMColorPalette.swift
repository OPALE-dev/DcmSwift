//
//  DICOMColorPalette.swift
//  DcmSwift
//
//  A color palette applied to a grayscale image after its VOI: the output
//  of the VOI, 0 to 255, is the index of an entry of 8-bit red, green and
//  blue. The well-known palettes of PS3.6 annex B, by their SOP Instance
//  UID, and the Supplemental Palette Color Lookup Table of an image
//  (PS3.3 C.8.16.2.1.1, C.7.9) are both palettes.
//

import Foundation

/// A palette of 256 colors indexed by the output of the VOI.
public struct DICOMColorPalette: Equatable, Sendable {
    /// The well-known color palettes of PS3.6 annex B.
    public enum WellKnown: String, CaseIterable, Sendable {
        case hotIron = "1.2.840.10008.1.5.1"
        case pet = "1.2.840.10008.1.5.2"
        case hotMetalBlue = "1.2.840.10008.1.5.3"
        case pet20Step = "1.2.840.10008.1.5.4"
        case spring = "1.2.840.10008.1.5.5"
        case summer = "1.2.840.10008.1.5.6"
        case fall = "1.2.840.10008.1.5.7"
        case winter = "1.2.840.10008.1.5.8"

        /// Its SOP Instance UID (PS3.6 table B.1-1).
        public var uid: String { rawValue }

        /// Its Content Label (0070,0080), as PS3.6 gives it.
        public var contentLabel: String {
            switch self {
            case .hotIron: "HOT_IRON"
            case .pet: "PET"
            case .hotMetalBlue: "HOT_METAL_BLUE"
            case .pet20Step: "PET_20_STEP"
            case .spring: "SPRING"
            case .summer: "SUMMER"
            case .fall: "FALL"
            case .winter: "WINTER"
            }
        }

        /// Whether PS3.6 gives it as Segmented Palette Color Lookup Table Data.
        public var isSegmented: Bool { [.spring, .summer, .fall, .winter].contains(self) }

        /// Its name in PS3.6.
        public var name: String {
            switch self {
            case .hotIron: "Hot Iron"
            case .pet: "PET"
            case .hotMetalBlue: "Hot Metal Blue"
            case .pet20Step: "PET 20 Step"
            case .spring: "Spring"
            case .summer: "Summer"
            case .fall: "Fall"
            case .winter: "Winter"
            }
        }
    }

    /// Where the palette comes from.
    public enum Source: Equatable, Sendable {
        case wellKnown(WellKnown)
        /// Red, Green and Blue Palette Color Lookup Table of a grayscale
        /// image, normal or segmented.
        case supplemental
    }

    public let source: Source
    /// 256 entries of each channel.
    public let red: [UInt8]
    public let green: [UInt8]
    public let blue: [UInt8]

    /// The color of an entry, 0 to 255.
    public func color(at index: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let index = min(max(index, 0), 255)
        return (red[index], green[index], blue[index])
    }

    /// A well-known palette, from the tables of PS3.6 annex B.
    public init(_ palette: WellKnown) {
        source = .wellKnown(palette)
        let channels: [[UInt8]]
        switch palette {
        case .hotIron: channels = Self.hotIronTable
        case .pet: channels = Self.petTable
        case .hotMetalBlue: channels = Self.hotMetalBlueTable
        case .pet20Step: channels = Self.pet20StepTable
        case .spring: channels = Self.expand(Self.springSegments)
        case .summer: channels = Self.expand(Self.summerSegments)
        case .fall: channels = Self.expand(Self.fallSegments)
        case .winter: channels = Self.expand(Self.winterSegments)
        }
        (red, green, blue) = (channels[0], channels[1], channels[2])
    }

    /// The well-known palette of a SOP Instance UID; nil for another UID.
    public init?(uid: String) {
        guard let palette = WellKnown(rawValue: uid.trimmingCharacters(in: .whitespaces.union(["\0"]))) else { return nil }
        self.init(palette)
    }

    /// The Supplemental Palette Color Lookup Table of a grayscale image:
    /// Red, Green and Blue descriptors and data, normal or segmented. Nil
    /// when the image has none; throws when it is not usable.
    ///
    /// Entries are taken for the outputs 0 to 255 of the VOI, the first
    /// mapped value of the descriptor first, as the renderer does for
    /// PALETTE COLOR; 16-bit entries keep their most significant byte.
    public init?(supplementalIn dataset: DataSet) throws {
        let scope = DICOMAttributeScope(dataset: dataset)
        guard scope.element("RedPaletteColorLookupTableDescriptor") != nil else { return nil }
        let tables = try ["Red", "Green", "Blue"].map { color -> DICOMLookupTable in
            let name = "\(color)PaletteColorLookupTableDescriptor"
            guard let descriptor = scope.element(name) else { throw DICOMPixelDataError.missingAttribute(name) }
            return try DICOMLookupTable(
                descriptor: descriptor,
                data: scope.element("\(color)PaletteColorLookupTableData"),
                segmentedData: scope.element("Segmented\(color)PaletteColorLookupTableData"),
                signedFirstValue: false,
                allowedBits: 8...16,
                name: name)
        }
        let channels = tables.map { table in
            (0..<256).map { index -> UInt8 in
                let entry = table.entry(for: index)
                return table.bitsPerEntry > 8 ? UInt8(truncatingIfNeeded: entry >> UInt16(table.bitsPerEntry - 8)) : UInt8(truncatingIfNeeded: entry)
            }
        }
        source = .supplemental
        (red, green, blue) = (channels[0], channels[1], channels[2])
    }

    /// Colors a grayscale image; an RGB image is returned as is.
    public func apply(to image: DICOMRenderedImage) -> DICOMRenderedImage {
        guard image.format == .gray8 else { return image }
        var pixels = [UInt8](repeating: 0, count: image.pixels.count * 3)
        for (index, gray) in image.pixels.enumerated() {
            let entry = Int(gray)
            pixels[index * 3] = red[entry]
            pixels[index * 3 + 1] = green[entry]
            pixels[index * 3 + 2] = blue[entry]
        }
        return DICOMRenderedImage(width: image.width, height: image.height, format: .rgb8, pixels: pixels)
    }

    private static func expand(_ segments: [[UInt16]]) -> [[UInt8]] {
        // The tables of PS3.6 expand to 256 entries; checked by the tests.
        segments.map { words in
            ((try? DICOMLookupTable.expandSegments(words, count: 256, name: "Segmented Palette")) ?? [UInt16](repeating: 0, count: 256))
                .map { UInt8(clamping: $0) }
        }
    }
}
