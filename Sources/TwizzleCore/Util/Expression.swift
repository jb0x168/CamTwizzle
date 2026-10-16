import Foundation

/// A small arithmetic expression language used by node graphs ("=amount*40")
/// and pass sizes ("$WIDTH/2"). Supports + - * / % ^, comparisons, && ||, ?:,
/// unary -, !, parentheses, numeric literals, variables (with dots, e.g.
/// `center.x`) and a set of shader-ish functions.
public struct TwzExpression {
    public let source: String
    private let root: Node

    indirect enum Node {
        case num(Double)
        case variable(String)
        case unary(Character, Node)
        case binary(String, Node, Node)
        case ternary(Node, Node, Node)
        case call(String, [Node])
    }

    public enum ExprError: Error, CustomStringConvertible {
        case syntax(String)
        case unknownFunction(String)
        public var description: String {
            switch self {
            case let .syntax(s): return "expression syntax error: \(s)"
            case let .unknownFunction(f): return "unknown function '\(f)'"
            }
        }
    }

    public init(_ source: String) throws {
        self.source = source
        var p = Parser(Array(source.replacingOccurrences(of: "$", with: "")))
        root = try p.parseExpression()
        p.skipSpace()
        if p.i < p.chars.count { throw ExprError.syntax("unexpected '\(p.chars[p.i])' in \(source)") }
    }

    /// Evaluate with a variable lookup; unknown variables evaluate to 0.
    public func evaluate(_ vars: [String: Double]) -> Double {
        TwzExpression.eval(root, vars)
    }

    /// Names of variables referenced by the expression.
    public var variables: Set<String> {
        var out = Set<String>()
        func walk(_ n: Node) {
            switch n {
            case .num: break
            case let .variable(v): out.insert(v)
            case let .unary(_, a): walk(a)
            case let .binary(_, a, b): walk(a); walk(b)
            case let .ternary(a, b, c): walk(a); walk(b); walk(c)
            case let .call(_, args): args.forEach(walk)
            }
        }
        walk(root)
        return out
    }

    static func lookup(_ name: String, _ vars: [String: Double]) -> Double {
        if let v = vars[name] { return v }
        let lower = name.lowercased()
        if let v = vars[lower] { return v }
        if let v = vars.first(where: { $0.key.lowercased() == lower })?.value { return v }
        switch lower {
        case "pi": return Double.pi
        case "tau": return Double.pi * 2
        case "e": return M_E
        default: return 0
        }
    }

    static func eval(_ n: Node, _ vars: [String: Double]) -> Double {
        switch n {
        case let .num(v): return v
        case let .variable(name): return lookup(name, vars)
        case let .unary(op, a):
            let v = eval(a, vars)
            return op == "-" ? -v : (op == "!" ? (v == 0 ? 1 : 0) : v)
        case let .ternary(c, a, b):
            return eval(c, vars) != 0 ? eval(a, vars) : eval(b, vars)
        case let .binary(op, a, b):
            let x = eval(a, vars)
            if op == "&&" { return (x != 0 && eval(b, vars) != 0) ? 1 : 0 }
            if op == "||" { return (x != 0 || eval(b, vars) != 0) ? 1 : 0 }
            let y = eval(b, vars)
            switch op {
            case "+": return x + y
            case "-": return x - y
            case "*": return x * y
            case "/": return y == 0 ? 0 : x / y
            case "%": return y == 0 ? 0 : x - y * (x / y).rounded(.down)
            case "^": return pow(x, y)
            case "<": return x < y ? 1 : 0
            case ">": return x > y ? 1 : 0
            case "<=": return x <= y ? 1 : 0
            case ">=": return x >= y ? 1 : 0
            case "==": return x == y ? 1 : 0
            case "!=": return x != y ? 1 : 0
            default: return 0
            }
        case let .call(f, args):
            let v = args.map { eval($0, vars) }
            func a(_ i: Int) -> Double { i < v.count ? v[i] : 0 }
            switch f {
            case "sin": return sin(a(0))
            case "cos": return cos(a(0))
            case "tan": return tan(a(0))
            case "asin": return asin(a(0))
            case "acos": return acos(a(0))
            case "atan": return v.count > 1 ? atan2(a(0), a(1)) : atan(a(0))
            case "atan2": return atan2(a(0), a(1))
            case "abs": return abs(a(0))
            case "floor": return floor(a(0))
            case "ceil": return ceil(a(0))
            case "round": return a(0).rounded()
            case "fract": return a(0) - floor(a(0))
            case "sqrt": return sqrt(max(0, a(0)))
            case "pow": return pow(a(0), a(1))
            case "exp": return exp(a(0))
            case "log": return log(a(0))
            case "log2": return log2(a(0))
            case "min": return v.min() ?? 0
            case "max": return v.max() ?? 0
            case "clamp": return min(max(a(0), a(1)), a(2))
            case "mix": return a(0) + (a(1) - a(0)) * a(2)
            case "step": return a(1) < a(0) ? 0 : 1
            case "smoothstep":
                let t = min(max((a(2) - a(0)) / (a(1) - a(0)), 0), 1)
                return t * t * (3 - 2 * t)
            case "sign": return a(0) > 0 ? 1 : (a(0) < 0 ? -1 : 0)
            case "mod": return a(1) == 0 ? 0 : a(0) - a(1) * floor(a(0) / a(1))
            case "rad", "radians": return a(0) * .pi / 180
            case "deg", "degrees": return a(0) * 180 / .pi
            case "random": return Double.random(in: 0..<1)
            case "noise":
                // cheap smooth 1D value noise
                let x = a(0), i = floor(x), f = x - i
                func h(_ n: Double) -> Double { let s = sin(n * 127.1) * 43758.5453; return s - floor(s) }
                let u = f * f * (3 - 2 * f)
                return h(i) * (1 - u) + h(i + 1) * u
            default: return 0
            }
        }
    }

    static let knownFunctions: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "abs", "floor", "ceil", "round", "fract",
        "sqrt", "pow", "exp", "log", "log2", "min", "max", "clamp", "mix", "step", "smoothstep", "sign",
        "mod", "rad", "radians", "deg", "degrees", "random", "noise",
    ]

    struct Parser {
        let chars: [Character]
        var i = 0
        init(_ c: [Character]) { chars = c }

        mutating func skipSpace() { while i < chars.count, chars[i].isWhitespace { i += 1 } }
        mutating func peek(_ s: String) -> Bool {
            skipSpace()
            let sc = Array(s)
            guard i + sc.count <= chars.count else { return false }
            return Array(chars[i..<(i + sc.count)]) == sc
        }
        mutating func eat(_ s: String) -> Bool {
            if peek(s) { i += s.count; return true }
            return false
        }

        mutating func parseExpression() throws -> Node { try parseTernary() }

        mutating func parseTernary() throws -> Node {
            let c = try parseOr()
            if eat("?") {
                let a = try parseTernary()
                guard eat(":") else { throw ExprError.syntax("expected ':'") }
                let b = try parseTernary()
                return .ternary(c, a, b)
            }
            return c
        }

        mutating func parseOr() throws -> Node {
            var l = try parseAnd()
            while eat("||") { l = .binary("||", l, try parseAnd()) }
            return l
        }

        mutating func parseAnd() throws -> Node {
            var l = try parseCompare()
            while eat("&&") { l = .binary("&&", l, try parseCompare()) }
            return l
        }

        mutating func parseCompare() throws -> Node {
            var l = try parseAdd()
            while true {
                if eat("<=") { l = .binary("<=", l, try parseAdd()) }
                else if eat(">=") { l = .binary(">=", l, try parseAdd()) }
                else if eat("==") { l = .binary("==", l, try parseAdd()) }
                else if eat("!=") { l = .binary("!=", l, try parseAdd()) }
                else if eat("<") { l = .binary("<", l, try parseAdd()) }
                else if eat(">") { l = .binary(">", l, try parseAdd()) }
                else { return l }
            }
        }

        mutating func parseAdd() throws -> Node {
            var l = try parseMul()
            while true {
                if eat("+") { l = .binary("+", l, try parseMul()) }
                else if eat("-") { l = .binary("-", l, try parseMul()) }
                else { return l }
            }
        }

        mutating func parseMul() throws -> Node {
            var l = try parseUnary()
            while true {
                if eat("*") { l = .binary("*", l, try parseUnary()) }
                else if eat("/") { l = .binary("/", l, try parseUnary()) }
                else if eat("%") { l = .binary("%", l, try parseUnary()) }
                else { return l }
            }
        }

        mutating func parseUnary() throws -> Node {
            if eat("-") { return .unary("-", try parseUnary()) }
            if eat("+") { return try parseUnary() }
            if eat("!") { return .unary("!", try parseUnary()) }
            return try parsePow()
        }

        mutating func parsePow() throws -> Node {
            let base = try parsePrimary()
            if eat("^") { return .binary("^", base, try parseUnary()) }
            return base
        }

        mutating func parsePrimary() throws -> Node {
            skipSpace()
            guard i < chars.count else { throw ExprError.syntax("unexpected end") }
            let c = chars[i]
            if eat("(") {
                let e = try parseExpression()
                guard eat(")") else { throw ExprError.syntax("expected ')'") }
                return e
            }
            if c.isNumber || c == "." {
                let start = i
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    let save = i
                    i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
                    if i < chars.count, chars[i].isNumber {
                        while i < chars.count, chars[i].isNumber { i += 1 }
                    } else { i = save }
                }
                guard let v = Double(String(chars[start..<i])) else { throw ExprError.syntax("bad number") }
                return .num(v)
            }
            if c.isLetter || c == "_" {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "." { i += 1 }
                let name = String(chars[start..<i])
                if eat("(") {
                    var args: [Node] = []
                    if !eat(")") {
                        repeat { args.append(try parseExpression()) } while eat(",")
                        guard eat(")") else { throw ExprError.syntax("expected ')' after arguments") }
                    }
                    let lname = name.lowercased()
                    guard TwzExpression.knownFunctions.contains(lname) else { throw ExprError.unknownFunction(name) }
                    return .call(lname, args)
                }
                if name.lowercased() == "true" { return .num(1) }
                if name.lowercased() == "false" { return .num(0) }
                return .variable(name)
            }
            throw ExprError.syntax("unexpected '\(c)'")
        }
    }
}
