import Foundation

/// Rendering Query Parameters (PS3.18 8.3.5.1, 8.3.5.2).
public struct DICOMwebRenderingParameters: Equatable, Sendable {
    public struct Viewport: Equatable, Sendable {
        /// Width and height of the rendered image, in pixels.
        public var width: Int
        public var height: Int
        /// The source region; nil components take their defaults (the
        /// whole image). Negative sizes flip the image.
        public var sourceX: Double?
        public var sourceY: Double?
        public var sourceWidth: Double?
        public var sourceHeight: Double?

        public init(width: Int, height: Int, sourceX: Double? = nil, sourceY: Double? = nil,
                    sourceWidth: Double? = nil, sourceHeight: Double? = nil) {
            self.width = width
            self.height = height
            self.sourceX = sourceX
            self.sourceY = sourceY
            self.sourceWidth = sourceWidth
            self.sourceHeight = sourceHeight
        }

        var hasSourceRegion: Bool { [sourceX, sourceY, sourceWidth, sourceHeight].contains { $0 != nil } }
    }

    public var window: DICOMWindow?
    public var viewport: Viewport?
    /// 1 to 100.
    public var quality: Int?
    public var annotations: [String] = []
    public var iccProfile: [String] = []

    public init(window: DICOMWindow? = nil, viewport: Viewport? = nil, quality: Int? = nil) {
        self.window = window
        self.viewport = viewport
        self.quality = quality
    }

    /// Parses the rendering parameters of a query component; invalid values
    /// throw, which the origin server answers with 400.
    public init(query: String) throws {
        for parameter in query.split(separator: "&") {
            let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(pair[0])
            let value = pair.count > 1 ? (String(pair[1]).removingPercentEncoding ?? "") : ""
            let values = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            switch name {
            case "window":
                let functions: [String: DICOMWindow.Function] = ["linear": .linear, "linear-exact": .linearExact,
                                                                 "sigmoid": .sigmoid]
                guard values.count == 3, let center = Double(values[0]), let width = Double(values[1]),
                      let function = functions[values[2]], width > 0, function != .linear || width >= 1 else {
                    throw DICOMwebHTTPError(400, "window must be center,width,function")
                }
                window = DICOMWindow(center: center, width: width, function: function)
            case "viewport":
                guard (values.count == 2 || values.count == 6), let width = Int(values[0]), let height = Int(values[1]),
                      width > 0, height > 0 else {
                    throw DICOMwebHTTPError(400, "viewport must be vw,vh[,sx,sy,sw,sh]")
                }
                var viewport = Viewport(width: width, height: height)
                if values.count == 6 {
                    func number(_ text: String) throws -> Double? {
                        if text.isEmpty { return nil }
                        guard let value = Double(text) else { throw DICOMwebHTTPError(400, "invalid viewport value \(text)") }
                        return value
                    }
                    viewport.sourceX = try number(values[2]).map(abs)
                    viewport.sourceY = try number(values[3]).map(abs)
                    viewport.sourceWidth = try number(values[4])
                    viewport.sourceHeight = try number(values[5])
                    if viewport.sourceWidth == 0 || viewport.sourceHeight == 0 {
                        throw DICOMwebHTTPError(400, "the viewport source region is empty")
                    }
                }
                self.viewport = viewport
            case "quality":
                guard let quality = Int(value), (1...100).contains(quality) else {
                    throw DICOMwebHTTPError(400, "quality must be an integer from 1 to 100")
                }
                self.quality = quality
            case "annotation":
                guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLetter) }) else {
                    throw DICOMwebHTTPError(400, "annotation must be a list of keywords")
                }
                annotations = values
            case "iccprofile":
                let known: Set<String> = ["no", "yes", "srgb", "adobergb", "rommrgb", "displayp3"]
                guard !values.isEmpty, values.allSatisfy(known.contains) else {
                    throw DICOMwebHTTPError(400, "unknown iccprofile value")
                }
                iccProfile = values
            default:
                continue
            }
        }
    }

    /// Crops and scales an image as the viewport parameter specifies
    /// (PS3.18 8.3.5.1.3): the source region, flipped for negative sizes,
    /// is scaled with its aspect ratio kept to fit inside the viewport.
    public static func apply(_ viewport: Viewport, to image: DICOMRenderedImage) -> DICOMRenderedImage {
        let sx = viewport.sourceX ?? 0, sy = viewport.sourceY ?? 0
        let sw = viewport.sourceWidth ?? (Double(image.width) - sx)
        let sh = viewport.sourceHeight ?? (Double(image.height) - sy)
        let regionWidth = abs(sw), regionHeight = abs(sh)
        guard regionWidth > 0, regionHeight > 0 else { return image }
        let scale = min(Double(viewport.width) / regionWidth, Double(viewport.height) / regionHeight)
        let width = max(1, Int((regionWidth * scale).rounded())), height = max(1, Int((regionHeight * scale).rounded()))
        let channels = image.format.bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * channels)
        for y in 0..<height {
            // Pixel centers map back into the source region.
            var v = (Double(y) + 0.5) / scale - 0.5
            if sh < 0 { v = regionHeight - 1 - v }
            v += sy
            for x in 0..<width {
                var u = (Double(x) + 0.5) / scale - 0.5
                if sw < 0 { u = regionWidth - 1 - u }
                u += sx
                for channel in 0..<channels {
                    pixels[(y * width + x) * channels + channel] = sample(image, u, v, channel)
                }
            }
        }
        return DICOMRenderedImage(width: width, height: height, format: image.format, pixels: pixels)
    }

    /// Bilinear interpolation; positions outside the image are black.
    private static func sample(_ image: DICOMRenderedImage, _ u: Double, _ v: Double, _ channel: Int) -> UInt8 {
        guard u > -1, v > -1, u < Double(image.width), v < Double(image.height) else { return 0 }
        let x0 = Int(floor(u)), y0 = Int(floor(v))
        let fx = u - Double(x0), fy = v - Double(y0)
        func at(_ x: Int, _ y: Int) -> Double {
            let x = min(max(x, 0), image.width - 1), y = min(max(y, 0), image.height - 1)
            return Double(image.pixels[(y * image.width + x) * image.format.bytesPerPixel + channel])
        }
        let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
        let bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
        return UInt8(min(255, max(0, (top * (1 - fy) + bottom * fy).rounded())))
    }
}

extension DICOMwebOriginServer {
    /// Default size of a thumbnail when no viewport is given.
    static let thumbnailSize = 128

    /// Rendered and Thumbnail resources (PS3.18 10.4.1.1.3, 10.4.1.1.4):
    /// images as image/jpeg or image/png, and Structured Reports as
    /// text/html or text/plain.
    func renderedResponse(
        _ resource: DICOMwebResource, _ request: DICOMwebHTTPRequest, _ context: DICOMwebRequestContext
    ) async throws -> DICOMwebHTTPResponse {
        guard let retrieve, let study = resource.study else { return Self.report(501, "Retrieve is not supported") }
        let items = try await retrieve.instances(study: study, series: resource.series, instance: resource.instance,
                                                 context: context)
        guard !items.isEmpty else { return Self.report(404, "\(resource.path) does not exist") }
        var parameters = try DICOMwebRenderingParameters(query: request.query)
        let thumbnail = resource.kind == .thumbnail
        if thumbnail {
            guard parameters.viewport?.hasSourceRegion != true else {
                return Self.report(400, "A thumbnail viewport has only a width and a height")
            }
            parameters.viewport = parameters.viewport
                ?? .init(width: Self.thumbnailSize, height: Self.thumbnailSize)
            parameters.annotations = []
        }
        var warnings: [String] = []
        if !parameters.annotations.isEmpty {
            warnings.append("299 \(context.baseURI): The following annotation values are not supported: "
                            + parameters.annotations.joined(separator: ","))
        }
        if parameters.iccProfile.contains(where: { $0 != "no" }) {
            warnings.append("299 \(context.baseURI): ICC profiles are not embedded in rendered images")
        }
        let accept = Self.acceptQueryParameter(request.query)

        // The Text resource category: Structured Reports.
        if let first = items.first, let dataSet = try? DICOMwebTranscoding.dataSet(first),
           !thumbnail, dataSet.sequence(forTagName: "ContentSequence") != nil, let document = SRDocument(withDataset: dataSet) {
            let selected = try negotiateRendered(request, accept: accept, supported: [.html, .plainText], defaultType: .html)
            var headers = DICOMwebMultipart.Headers()
            headers["Content-Type"] = selected.with("charset", "utf-8").description
            headers["Content-Location"] = "\(context.baseURI)\(resource.path)"
            let text = selected == .html ? document.html : document.description
            return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(Data(text.utf8)))
        }

        // Frames to render: all frames of every image, or the requested
        // frames; a thumbnail stands for its resource with one frame.
        var frames: [(dataSet: DataSet, frame: Int, location: String)] = []
        for item in thumbnail ? Array(items.prefix(1)) : items {
            let dataSet = try DICOMwebTranscoding.dataSet(item)
            guard let description = try? DICOMPixelDescription(dataset: dataSet) else { continue }
            let numbers = resource.frames ?? Array(1...max(1, description.numberOfFrames))
            for number in thumbnail ? Array(numbers.prefix(1)) : numbers {
                guard number <= description.numberOfFrames else {
                    return Self.report(404, "Frame \(number) does not exist")
                }
                frames.append((dataSet, number - 1, "\(context.baseURI)\(resource.path)"))
            }
        }
        guard !frames.isEmpty else { return Self.report(404, "\(resource.path) holds no renderable image") }

        let single = frames.count == 1
        var supported: [DICOMwebMediaType] = [.multipartRelated(.jpeg), .multipartRelated(.png)]
        if single { supported = [.jpeg, .png] + supported }
        let selected = try negotiateRendered(request, accept: accept, supported: supported,
                                             defaultType: single ? .jpeg : .multipartRelated(.jpeg))
        let format = selected.relatedType ?? selected
        func encode(_ entry: (dataSet: DataSet, frame: Int, location: String)) throws -> Data {
            let renderer = try DICOMImageRenderer(dataset: entry.dataSet)
            var options = DICOMRenderingOptions()
            if let window = parameters.window { options.voi = .window(window) }
            var image = try renderer.render(frame: entry.frame, options: options)
            if let viewport = parameters.viewport { image = DICOMwebRenderingParameters.apply(viewport, to: image) }
            return format == .png ? try image.pngData() : try image.jpegData(quality: parameters.quality ?? 90)
        }

        var headers = DICOMwebMultipart.Headers()
        if !warnings.isEmpty { headers["Warning"] = warnings.joined(separator: ", ") }
        if !selected.isMultipartRelated {
            headers["Content-Type"] = format.description
            headers["Content-Location"] = frames[0].location
            let body = request.method == "HEAD" ? Data() : try encode(frames[0])
            return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(body))
        }
        var writer = DICOMwebMultipart.Writer()
        var body = Data()
        var partHeaders = DICOMwebMultipart.Headers()
        partHeaders["Content-Type"] = format.description
        if request.method != "HEAD" {
            for entry in frames {
                partHeaders["Content-Location"] = entry.location
                body += writer.part(partHeaders, body: try encode(entry))
            }
            body += writer.close()
        }
        headers["Content-Type"] = DICOMwebMediaType.multipartRelated(format, boundary: writer.boundary).description
        return DICOMwebHTTPResponse(status: 200, headers: headers, body: .data(body))
    }

    /// Negotiation among Rendered Media Types; a transfer-syntax parameter is
    /// not permitted with them (PS3.18 8.7.4).
    private func negotiateRendered(
        _ request: DICOMwebHTTPRequest, accept: [DICOMwebAcceptRange], supported: [DICOMwebMediaType],
        defaultType: DICOMwebMediaType
    ) throws -> DICOMwebMediaType {
        let header = request.headers["Accept"].map(DICOMwebAcceptRange.parse)
        if (accept + (header ?? [])).contains(where: { $0.range.transferSyntax != nil && !DICOMwebContentNegotiation.isDICOM($0.range) }) {
            throw DICOMwebHTTPError(400, "A transfer-syntax parameter is not permitted with rendered media types")
        }
        switch DICOMwebContentNegotiation.select(query: accept, header: header, supported: supported,
                                                 defaultType: defaultType, defaultTransferSyntax: nil) {
        case .selected(let type): return type
        case .notAcceptable:
            throw DICOMwebHTTPError(406, "Acceptable media types: " + supported.map(\.description).joined(separator: ", "))
        case .badRequest(let message): throw DICOMwebHTTPError(400, message)
        }
    }
}
