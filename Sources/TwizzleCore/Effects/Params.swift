import Foundation

/// Kinds of user-facing effect parameters. Names follow ISF where possible.
public enum ParamType: String, Codable, CaseIterable {
    case float
    case long      // integer / enumerated choice (VALUES + LABELS)
    case bool
    case event     // momentary trigger (true for one frame)
    case color
    case point2D
    case image     // user-picked image file
    case text      // string rendered to a texture by the engine
    case source    // another live video source

    static func parse(_ s: String) -> ParamType? {
        switch s.lowercased() {
        case "float", "number", "double": return .float
        case "long", "int", "integer", "enum", "menu": return .long
        case "bool", "boolean", "toggle": return .bool
        case "event", "button", "trigger": return .event
        case "color", "colour": return .color
        case "point2d", "point", "vec2", "position": return .point2D
        case "image", "file": return .image
        case "text", "string": return .text
        case "source", "video": return .source
        default: return nil
        }
    }
}

/// A concrete parameter value. Stored in scene configs (Codable).
public enum ParamValue: Codable, Equatable, Hashable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case color([Double])   // rgba 0..1
    case point([Double])   // x,y normalized, origin top-left
    case string(String)

    public var asDouble: Double {
        switch self {
        case let .float(v): return v
        case let .int(v): return Double(v)
        case let .bool(b): return b ? 1 : 0
        case let .color(c): return c.first ?? 0
        case let .point(p): return p.first ?? 0
        case let .string(s): return Double(s) ?? 0
        }
    }

    public var asInt: Int { Int(asDouble.rounded()) }
    public var asBool: Bool { asDouble > 0.5 }

    public var asColor: [Double] {
        switch self {
        case let .color(c):
            let fill: [Double] = [0, 0, 0, 1]
            var r = Array(c.prefix(4))
            while r.count < 4 { r.append(fill[r.count]) }
            return r
        case let .float(v): return [v, v, v, 1]
        default: return [0, 0, 0, 1]
        }
    }

    public var asPoint: [Double] {
        switch self {
        case let .point(p): return p.count >= 2 ? [p[0], p[1]] : [0.5, 0.5]
        case let .color(c): return c.count >= 2 ? [c[0], c[1]] : [0.5, 0.5]
        default: return [0.5, 0.5]
        }
    }

    public var asString: String {
        switch self {
        case let .string(s): return s
        case let .float(v): return String(v)
        case let .int(v): return String(v)
        case let .bool(b): return b ? "true" : "false"
        default: return ""
        }
    }

    /// Four floats for packing into a GPU uniform slot.
    public var packed: SIMD4<Float> {
        switch self {
        case let .float(v): return SIMD4(Float(v), 0, 0, 0)
        case let .int(v): return SIMD4(Float(v), 0, 0, 0)
        case let .bool(b): return SIMD4(b ? 1 : 0, 0, 0, 0)
        case .color:
            let c = asColor
            return SIMD4(Float(c[0]), Float(c[1]), Float(c[2]), Float(c[3]))
        case let .point(p):
            return SIMD4(Float(p.count > 0 ? p[0] : 0.5), Float(p.count > 1 ? p[1] : 0.5), 0, 0)
        case .string: return .zero
        }
    }

    // Compact Codable representation: plain JSON scalars/arrays.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .float(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([Double].self) { self = a.count == 2 ? .point(a) : .color(a); return }
        if let o = try? c.decode([String: [Double]].self) {
            if let p = o["point"] { self = .point(p); return }
            if let col = o["color"] { self = .color(col); return }
        }
        if let o = try? c.decode([String: Double].self), let f = o["float"] { self = .float(f); return }
        self = .float(0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .float(v): try c.encode(["float": v])
        case let .int(v): try c.encode(v)
        case let .bool(b): try c.encode(b)
        case let .color(v): try c.encode(["color": v])
        case let .point(v): try c.encode(["point": v])
        case let .string(s): try c.encode(s)
        }
    }
}

/// Describes one parameter of an effect (parsed from a plugin header).
public struct ParamDescriptor: Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var label: String
    public var type: ParamType
    public var defaultValue: ParamValue
    public var min: Double?
    public var max: Double?
    public var values: [Int] = []
    public var labels: [String] = []
    public var font: String?          // text params
    public var fontSize: Double?      // text params, pixel height of rendered glyphs
    public var help: String?

    public init(name: String, label: String? = nil, type: ParamType, defaultValue: ParamValue,
                min: Double? = nil, max: Double? = nil) {
        self.name = name
        self.label = label ?? ParamDescriptor.prettify(name)
        self.type = type
        self.defaultValue = defaultValue
        self.min = min
        self.max = max
    }

    /// Converts identifiers like `edgeWidth`, `edge_width` or `EDGE_WIDTH` to "Edge Width".
    public static func prettify(_ name: String) -> String {
        var out = ""
        var prevLower = false
        for ch in name {
            if ch == "_" || ch == "-" { out.append(" "); prevLower = false; continue }
            if ch.isUppercase && prevLower { out.append(" ") }
            out.append(ch)
            prevLower = ch.isLowercase || ch.isNumber
        }
        let words = out.split(separator: " ").map { w -> String in
            let s = String(w)
            if s == s.uppercased() && s.count > 1 { return s.prefix(1) + s.dropFirst().lowercased() }
            return s.prefix(1).uppercased() + s.dropFirst()
        }
        return words.joined(separator: " ")
    }

    /// Parse an ISF-style INPUTS entry.
    public static func parse(_ j: JSONValue) throws -> ParamDescriptor {
        guard let name = j["NAME"]?.string, !name.isEmpty else {
            throw PluginError.invalidHeader("input without NAME")
        }
        guard let typeStr = j["TYPE"]?.string, let type = ParamType.parse(typeStr) else {
            throw PluginError.invalidHeader("input '\(name)' has unknown TYPE '\(j["TYPE"]?.string ?? "")'")
        }
        let dflt = j["DEFAULT"]
        var value: ParamValue
        switch type {
        case .float: value = .float(dflt?.double ?? 0)
        case .long: value = .int(Int(dflt?.double ?? 0))
        case .bool, .event: value = .bool(dflt?.bool ?? false)
        case .color:
            let c = dflt?.doubles ?? [1, 1, 1, 1]
            value = .color(Array((c + [1, 1, 1, 1].dropFirst(c.count)).prefix(4)))
        case .point2D:
            let p = dflt?.doubles ?? [0.5, 0.5]
            value = .point(p.count >= 2 ? [p[0], p[1]] : [0.5, 0.5])
        case .image, .text, .source: value = .string(dflt?.string ?? "")
        }
        var d = ParamDescriptor(name: name, label: j["LABEL"]?.string, type: type, defaultValue: value,
                                min: j["MIN"]?.double, max: j["MAX"]?.double)
        if type == .float {
            if d.min == nil { d.min = 0 }
            if d.max == nil { d.max = Swift.max(1, (dflt?.double ?? 0) * 2) }
        }
        if type == .long {
            d.values = j["VALUES"]?.doubles?.map { Int($0) } ?? []
            d.labels = j["LABELS"]?.strings ?? []
            if d.values.isEmpty, !d.labels.isEmpty { d.values = Array(0..<d.labels.count) }
            if d.values.isEmpty, let lo = d.min, let hi = d.max, hi > lo, hi - lo < 64 {
                d.values = Array(Int(lo)...Int(hi))
            }
            if d.labels.count < d.values.count {
                d.labels += d.values.dropFirst(d.labels.count).map { String($0) }
            }
        }
        d.font = j["FONT"]?.string
        d.fontSize = j["FONTSIZE"]?.double ?? j["FONT_SIZE"]?.double
        d.help = j["DESCRIPTION"]?.string ?? j["HELP"]?.string
        return d
    }

    /// Clamp/sanitize a value for this descriptor.
    public func sanitize(_ v: ParamValue?) -> ParamValue {
        guard let v else { return defaultValue }
        switch type {
        case .float:
            var x = v.asDouble
            if x.isNaN { x = defaultValue.asDouble }
            return .float(x)
        case .long: return .int(v.asInt)
        case .bool, .event: return .bool(v.asBool)
        case .color:
            if case .color = v { return .color(v.asColor) }
            return defaultValue
        case .point2D:
            if case .point = v { return .point(v.asPoint) }
            return defaultValue
        case .image, .text, .source:
            if case let .string(s) = v { return .string(s) }
            return defaultValue
        }
    }
}

public enum PluginError: Error, CustomStringConvertible {
    case invalidHeader(String)
    case compile(String)
    case missingResource(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case let .invalidHeader(s): return "Invalid plugin header: \(s)"
        case let .compile(s): return s
        case let .missingResource(s): return "Missing resource: \(s)"
        case let .unsupported(s): return "Unsupported: \(s)"
        }
    }
}
