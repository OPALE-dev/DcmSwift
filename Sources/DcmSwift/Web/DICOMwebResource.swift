import Foundation

/// A Target Resource of the Studies Service (PS3.18 10.1.1, 10.4 to 10.6),
/// relative to the service's Base URI.
public struct DICOMwebResource: Hashable, Sendable, CustomStringConvertible {
    /// The Study, Series, and SOP Instance UIDs of the path, outermost first.
    public var study: String?
    public var series: String?
    public var instance: String?
    /// One-based frame numbers of a Frames resource.
    public var frames: [Int]?
    public var kind: Kind

    public enum Kind: String, Hashable, Sendable {
        /// The instances themselves (`/studies/{study}`, and below).
        case instances
        /// A collection searched by the Search Transaction (`/studies`,
        /// `/studies/{study}/series`, `/instances`, ...).
        case search
        case metadata
        case rendered
        case thumbnail
        case bulkdata
        case pixeldata
        /// Frame Pixel Data (`.../frames/{frames}`).
        case frames
    }

    public init(study: String? = nil, series: String? = nil, instance: String? = nil, frames: [Int]? = nil,
                kind: Kind) {
        self.study = study
        self.series = series
        self.instance = instance
        self.frames = frames
        self.kind = kind
    }

    /// The level searched by a search resource.
    public var searchLevel: DICOMwebSearchLevel? { kind == .search ? pathLevel : nil }

    /// For a search: the level named by the last path segment.
    private var pathLevel: DICOMwebSearchLevel?

    /// Parses the path components after the Base URI, such as
    /// `["studies", "1.2.3", "series"]`; nil when it names no resource.
    public init?(pathComponents: [String]) {
        var components = pathComponents.filter { !$0.isEmpty }
        guard !components.isEmpty else { return nil }
        var study: String?, series: String?, instance: String?, frames: [Int]?
        var kind = Kind.instances
        var level: DICOMwebSearchLevel?

        func uid(_ value: String) -> String? { DICOMUniqueIdentifier.isValid(value) ? value : nil }

        let first = components.removeFirst()
        switch first {
        case "studies":
            if components.isEmpty {
                kind = .search
                level = .study
            } else {
                guard let value = uid(components.removeFirst()) else { return nil }
                study = value
            }
        case "series":
            guard components.isEmpty else { return nil }
            kind = .search
            level = .series
        case "instances":
            guard components.isEmpty else { return nil }
            kind = .search
            level = .instance
        default:
            return nil
        }
        while kind != .search, let segment = components.first {
            components.removeFirst()
            switch segment {
            case "series" where series == nil && instance == nil:
                if components.isEmpty {
                    kind = .search
                    level = .series
                } else {
                    guard let value = uid(components.removeFirst()) else { return nil }
                    series = value
                }
            case "instances" where instance == nil && study != nil:
                if components.isEmpty {
                    kind = .search
                    level = .instance
                } else {
                    guard series != nil, let value = uid(components.removeFirst()) else { return nil }
                    instance = value
                }
            case "frames" where instance != nil && frames == nil:
                guard !components.isEmpty else { return nil }
                let numbers = components.removeFirst().split(separator: ",").map { Int($0) }
                guard !numbers.isEmpty, numbers.allSatisfy({ ($0 ?? 0) > 0 }) else { return nil }
                frames = numbers.map { $0! }
                kind = .frames
            case "metadata" where frames == nil, "bulkdata" where frames == nil, "pixeldata" where frames == nil:
                guard components.isEmpty else { return nil }
                kind = Kind(rawValue: segment)!
            case "rendered", "thumbnail":
                guard components.isEmpty else { return nil }
                kind = Kind(rawValue: segment)!
            default:
                return nil
            }
        }
        guard components.isEmpty else { return nil }
        self.init(study: study, series: series, instance: instance, frames: frames, kind: kind)
        self.pathLevel = level
    }

    /// The path below the Base URI, starting with "/".
    public var path: String {
        var path = ""
        switch (kind, pathLevel) {
        case (.search, .study?) where study == nil: return "/studies"
        case (.search, .series?) where study == nil: return "/series"
        case (.search, .instance?) where study == nil: return "/instances"
        default: break
        }
        if let study { path += "/studies/\(study)" }
        if let series { path += "/series/\(series)" }
        if let instance { path += "/instances/\(instance)" }
        if let frames { path += "/frames/" + frames.map(String.init).joined(separator: ",") }
        switch kind {
        case .instances, .frames: break
        case .search:
            if pathLevel == .series { path += "/series" } else if pathLevel == .instance { path += "/instances" }
        case .metadata, .rendered, .thumbnail, .bulkdata, .pixeldata:
            path += "/" + kind.rawValue
        }
        return path
    }

    public var description: String { path }

    // MARK: Constructors

    /// A search of `level`, within a study and series when given.
    public static func search(_ level: DICOMwebSearchLevel, study: String? = nil, series: String? = nil) -> DICOMwebResource {
        var resource = DICOMwebResource(study: study, series: series, kind: .search)
        resource.pathLevel = level
        return resource
    }

    /// The study, series, or instance; `kind` selects a variant such as
    /// `.metadata` or `.rendered`.
    public static func target(
        study: String, series: String? = nil, instance: String? = nil, kind: Kind = .instances
    ) -> DICOMwebResource {
        DICOMwebResource(study: study, series: series, instance: instance, kind: kind)
    }

    /// Frames of an instance, as Frame Pixel Data, or rendered.
    public static func frames(
        _ numbers: [Int], study: String, series: String, instance: String, rendered: Bool = false
    ) -> DICOMwebResource {
        var resource = DICOMwebResource(study: study, series: series, instance: instance, frames: numbers, kind: .frames)
        if rendered { resource.kind = .rendered }
        return resource
    }
}
