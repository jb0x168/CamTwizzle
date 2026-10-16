import Foundation

/// Where a layer's pixels come from. `key` is a stable string form used for
/// sharing capture sessions and for `source` effect parameters.
public struct SourceSpec: Codable, Hashable {
    public enum Kind: String, Codable, CaseIterable {
        case camera, screen, window, syphon, image, movie, pattern
    }

    public var kind: Kind
    /// camera uniqueID, display ID, window ID, Syphon server UUID, file path or pattern name
    public var identifier: String
    /// Human-readable name at the time the source was chosen.
    public var name: String
    public var options: [String: String] = [:]

    public init(kind: Kind, identifier: String, name: String, options: [String: String] = [:]) {
        self.kind = kind
        self.identifier = identifier
        self.name = name
        self.options = options
    }

    public var key: String { "\(kind.rawValue):\(identifier)" }

    enum CodingKeys: String, CodingKey { case kind, identifier, name, options }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? identifier
        options = try c.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
    }

    public static func parse(key: String) -> SourceSpec? {
        guard let i = key.firstIndex(of: ":"), let kind = Kind(rawValue: String(key[..<i])) else { return nil }
        let ident = String(key[key.index(after: i)...])
        return SourceSpec(kind: kind, identifier: ident, name: ident)
    }

    public static let testPattern = SourceSpec(kind: .pattern, identifier: "bars", name: "Test Pattern")
}

public enum FitMode: String, Codable, CaseIterable {
    case fill, fit, stretch
}

public enum BlendMode: String, Codable, CaseIterable {
    case normal, add, screen, multiply, difference, lighten, darken, overlay
    var index: Int { BlendMode.allCases.firstIndex(of: self)! }
}

/// One effect in a stack.
public struct EffectConfig: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var effectID: String
    public var enabled = true
    public var params: [String: ParamValue] = [:]
    /// Optional user label (e.g. "Ogre (subtle)").
    public var label: String?

    public init(effectID: String, params: [String: ParamValue] = [:]) {
        self.effectID = effectID
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case id, effectID, enabled, params, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        effectID = try c.decode(String.self, forKey: .effectID)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        params = try c.decodeIfPresent([String: ParamValue].self, forKey: .params) ?? [:]
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

/// A source placed on the canvas, with its own effect stack.
public struct LayerConfig: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var source: SourceSpec
    public var enabled = true
    public var fit: FitMode = .fill
    public var mirror = false
    /// Normalized crop of the source (left, top, right, bottom insets 0..1).
    public var crop: [Double] = [0, 0, 0, 0]
    /// Placement on the canvas: center (normalized, top-left origin), uniform scale, rotation in degrees.
    public var x = 0.5
    public var y = 0.5
    public var scale = 1.0
    public var rotation = 0.0
    public var opacity = 1.0
    public var blend: BlendMode = .normal
    public var effects: [EffectConfig] = []

    public init(source: SourceSpec) { self.source = source }

    public var isFullFrame: Bool { abs(x - 0.5) < 1e-6 && abs(y - 0.5) < 1e-6 && abs(scale - 1) < 1e-6 && abs(rotation) < 1e-6 }

    enum CodingKeys: String, CodingKey { case id, source, enabled, fit, mirror, crop, x, y, scale, rotation, opacity, blend, effects }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try c.decode(SourceSpec.self, forKey: .source)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        fit = try c.decodeIfPresent(FitMode.self, forKey: .fit) ?? .fill
        mirror = try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? false
        crop = try c.decodeIfPresent([Double].self, forKey: .crop) ?? [0, 0, 0, 0]
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        blend = try c.decodeIfPresent(BlendMode.self, forKey: .blend) ?? .normal
        effects = try c.decodeIfPresent([EffectConfig].self, forKey: .effects) ?? []
    }
}

/// A virtual camera: layers composited onto a canvas, then a master effect stack.
public struct SceneConfig: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var enabled = true
    public var width = 1920
    public var height = 1080
    public var fps = 30
    public var layers: [LayerConfig] = []
    public var effects: [EffectConfig] = []
    /// UID of the CMIO device whose sink stream receives this scene ("" = preview only).
    public var outputDeviceUID: String = ""
    /// Also publish via Syphon (if available).
    public var syphonOutput = false

    public init(name: String) { self.name = name }

    enum CodingKeys: String, CodingKey { case id, name, enabled, width, height, fps, layers, effects, outputDeviceUID, syphonOutput }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Camera"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 1920
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 1080
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        layers = try c.decodeIfPresent([LayerConfig].self, forKey: .layers) ?? []
        effects = try c.decodeIfPresent([EffectConfig].self, forKey: .effects) ?? []
        outputDeviceUID = try c.decodeIfPresent(String.self, forKey: .outputDeviceUID) ?? ""
        syphonOutput = try c.decodeIfPresent(Bool.self, forKey: .syphonOutput) ?? false
    }
}

/// Everything the app persists.
public struct TwizzleDocument: Codable {
    public var scenes: [SceneConfig] = []
    public var version = 1
    public init(scenes: [SceneConfig] = []) { self.scenes = scenes }

    enum CodingKeys: String, CodingKey { case scenes, version }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scenes = try c.decodeIfPresent([SceneConfig].self, forKey: .scenes) ?? []
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}
