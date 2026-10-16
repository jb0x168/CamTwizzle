import Foundation

/// A loosely-typed JSON value used for plugin headers and graph descriptions.
/// Object keys are matched case-insensitively so both ISF-style (`"NAME"`) and
/// lower-case (`"name"`) spellings work.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.number(x), .number(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.array(x), .array(y)): return x == y
        case let (.object(x), .object(y)):
            return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed, .json5Allowed])
        return JSONValue(any: obj)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    init(any: Any) {
        switch any {
        case is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSONValue(any: $0) })
        case let d as [String: Any]:
            // JSONSerialization loses key order; sort for determinism.
            self = .object(d.keys.sorted().map { ($0, JSONValue(any: d[$0]!)) })
        default: self = .null
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(pairs) = self else { return nil }
        let lk = key.lowercased()
        return pairs.first(where: { $0.0.lowercased() == lk })?.1
    }

    public subscript(index: Int) -> JSONValue? {
        guard case let .array(a) = self, index >= 0, index < a.count else { return nil }
        return a[index]
    }

    public var string: String? {
        switch self {
        case let .string(s): return s
        case let .number(n): return n == n.rounded() ? String(Int(n)) : String(n)
        case let .bool(b): return b ? "true" : "false"
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case let .number(n): return n
        case let .bool(b): return b ? 1 : 0
        case let .string(s): return Double(s)
        default: return nil
        }
    }

    public var bool: Bool? {
        switch self {
        case let .bool(b): return b
        case let .number(n): return n != 0
        case let .string(s): return ["true", "yes", "1"].contains(s.lowercased())
        default: return nil
        }
    }

    public var array: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    public var doubles: [Double]? {
        array?.compactMap { $0.double }
    }

    public var strings: [String]? {
        if case let .string(s) = self { return [s] }
        return array?.compactMap { $0.string }
    }

    public var objectPairs: [(String, JSONValue)]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var isNull: Bool { if case .null = self { return true } else { return false } }
}
