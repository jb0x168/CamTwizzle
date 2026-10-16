import Foundation

/// ISF (Interactive Shader Format, isf.video) support: GLSL fragment shaders
/// with a JSON header, as used by VDMX, Resolume, Millumin, CoGe… — the
/// closest thing the Quartz Composer era has to a modern successor.
///
/// The GLSL is translated to Metal with a few text rewrites and wrapped in a
/// struct whose members are ISF's uniforms/images, so helper functions can
/// keep referring to them as globals.
extension ShaderProgram {
    func generateISF() -> String {
        var s = ShaderProgram.prelude
        s += "#undef PI\n#undef TAU\n"
        s += """
        inline float radians(float d) { return d * 0.0174532925199; }
        inline float2 radians(float2 d) { return d * 0.0174532925199; }
        inline float3 radians(float3 d) { return d * 0.0174532925199; }
        inline float degrees(float r) { return r * 57.2957795131; }
        inline float2 degrees(float2 r) { return r * 57.2957795131; }
        inline float distance(float a, float b) { return abs(a - b); }
        template <typename T> inline auto lessThan(T a, T b) { return a < b; }
        template <typename T> inline auto lessThanEqual(T a, T b) { return a <= b; }
        template <typename T> inline auto greaterThan(T a, T b) { return a > b; }
        template <typename T> inline auto greaterThanEqual(T a, T b) { return a >= b; }
        template <typename T> inline auto equal(T a, T b) { return a == b; }
        template <typename T> inline auto notEqual(T a, T b) { return a != b; }
        inline float3 mod(float3 x, float3 y) { return x - y * floor(x / y); }
        inline float4 mod(float4 x, float4 y) { return x - y * floor(x / y); }
        inline float2 atan(float2 y, float2 x) { return float2(atan2(y.x, x.x), atan2(y.y, x.y)); }
        constexpr sampler isf_sampler(filter::linear, address::clamp_to_edge);
        struct TwzParamsBuffer { float4 v[\(max(1, params.count))]; };

        struct ISFShader {
            float TIME; float TIMEDELTA; float4 DATE; int FRAMEINDEX; int PASSINDEX; float2 RENDERSIZE;
            float2 isf_FragNormCoord; float2 vv_FragNormCoord; float4 gl_FragCoord; float4 gl_FragColor;
            texture2d<float> inputImage;

        """
        for n in textureNames { s += "    texture2d<float> \(n);\n" }
        if isfStartImageAlias { s += "    texture2d<float> startImage;\n" }
        for p in params {
            switch p.type {
            case .float: s += "    float \(p.name);\n"
            case .long: s += "    int \(p.name);\n"
            case .bool, .event: s += "    bool \(p.name);\n"
            case .color: s += "    float4 \(p.name);\n"
            case .point2D: s += "    float2 \(p.name);\n"
            default: break   // textures declared above
            }
        }
        s += """
            float4 IMG_NORM_PIXEL(texture2d<float> t, float2 c) const { return t.sample(isf_sampler, float2(c.x, 1.0 - c.y)); }
            float4 IMG_PIXEL(texture2d<float> t, float2 c) const { float2 z = float2(t.get_width(), t.get_height()); return t.sample(isf_sampler, float2(c.x / z.x, 1.0 - c.y / z.y)); }
            float4 IMG_THIS_NORM_PIXEL(texture2d<float> t) const { return IMG_NORM_PIXEL(t, isf_FragNormCoord); }
            float4 IMG_THIS_PIXEL(texture2d<float> t) const { return IMG_NORM_PIXEL(t, isf_FragNormCoord); }
            float2 IMG_SIZE(texture2d<float> t) const { return float2(t.get_width(), t.get_height()); }
            float4 texture2D(texture2d<float> t, float2 c) const { return IMG_NORM_PIXEL(t, c); }
            float4 texture2D(texture2d<float> t, float2 c, float bias) const { return IMG_NORM_PIXEL(t, c); }
            float4 texture2DRect(texture2d<float> t, float2 c) const { return IMG_PIXEL(t, c); }

        """
        let uniforms = Set(params.map(\.name) + textureNames + ["inputImage"])
        // A companion .vs computes varyings; run its main() per fragment first (varyings are linear).
        var vsMembers = ""
        var vsBody = ""
        let vsURL = url.deletingPathExtension().appendingPathExtension("vs")
        if let vs = try? String(contentsOf: vsURL, encoding: .utf8) {
            let (decls, body) = ISFTranslator.vertexShader(vs, uniforms: uniforms)
            vsMembers = decls
            vsBody = body
        }
        s += vsMembers
        s += "    void isf_vs_main() {\n" + vsBody + "\n    }\n"
        let body = ISFTranslator.translate(ISFTranslator.stripHeader(source), uniforms: uniforms)
        let fileName = url.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        s += "#line \(ISFTranslator.headerLineCount(source) + 1) \"\(fileName)\"\n"
        s += body
        s += "\n#line 1 \"<twizzle isf wrapper>\"\n};\n"
        s += """
        fragment float4 twz_fragment(TwzVOut in [[stage_in]],
                                     constant TwzGlobals& G [[buffer(0)]],
                                     constant TwzParamsBuffer& PB [[buffer(1)]],
                                     texture2d<float> twz_tex0 [[texture(0)]],
                                     texture2d<float> twz_tex1 [[texture(1)]]
        """
        for (i, _) in textureNames.enumerated() { s += ",\n    texture2d<float> twz_tex\(i + 2) [[texture(\(i + 2))]]" }
        s += """
        ) {
            ISFShader s;
            s.TIME = G.timing.x;
            s.TIMEDELTA = G.timing.y;
            s.FRAMEINDEX = int(G.timing.z);
            s.PASSINDEX = int(G.timing.w);
            s.RENDERSIZE = G.size.xy;
            s.DATE = float4(G.date.x, G.date.y, G.date.z, G.date.w);
            s.isf_FragNormCoord = float2(in.uv.x, 1.0 - in.uv.y);
            s.vv_FragNormCoord = s.isf_FragNormCoord;
            s.gl_FragCoord = float4(in.position.x, G.size.y - in.position.y, 0.0, 1.0);
            s.gl_FragColor = float4(0.0);
            s.inputImage = twz_tex0;

        """
        if isfStartImageAlias { s += "    s.startImage = twz_tex0;\n" }
        for (i, n) in textureNames.enumerated() { s += "    s.\(n) = twz_tex\(i + 2);\n" }
        for (i, p) in params.enumerated() {
            switch p.type {
            case .float: s += "    s.\(p.name) = PB.v[\(i)].x;\n"
            case .long: s += "    s.\(p.name) = int(round(PB.v[\(i)].x));\n"
            case .bool, .event: s += "    s.\(p.name) = PB.v[\(i)].x > 0.5;\n"
            case .color: s += "    s.\(p.name) = PB.v[\(i)];\n"
            case .point2D:
                // UI points are normalized with a top-left origin; ISF wants bottom-left (pixels or normalized).
                if isfPixelPoints.contains(p.name) {
                    s += "    s.\(p.name) = float2(PB.v[\(i)].x, 1.0 - PB.v[\(i)].y) * G.size.xy;\n"
                } else {
                    s += "    s.\(p.name) = float2(PB.v[\(i)].x, 1.0 - PB.v[\(i)].y);\n"
                }
            default: break
            }
        }
        s += "    s.isf_vs_main();\n    s.main();\n    return s.gl_FragColor;\n}\n"
        return s
    }
}

enum ISFTranslator {
    static func headerLineCount(_ text: String) -> Int {
        guard let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) else { return 0 }
        return text[text.startIndex..<end.upperBound].filter { $0 == "\n" }.count
    }

    static func stripHeader(_ text: String) -> String {
        guard let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) else { return text }
        return String(text[end.upperBound...])
    }

    static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Rewrites GLSL into Metal-compatible C++ that lives inside the ISFShader struct.
    static func translate(_ glsl: String, uniforms: Set<String>) -> String {
        var s = glsl
        // Preprocessor/version/precision noise
        s = regexReplace(s, #"^\s*#version.*$"#, "")
        s = regexReplace(s, #"\b__VERSION__\b"#, "120")
        s = regexReplace(s, #"^\s*precision\s+\w+\s+\w+\s*;"#, "")
        s = regexReplace(s, #"\b(highp|mediump|lowp|flat|smooth|noperspective)\s+"#, "")
        // Drop redundant uniform declarations of ISF inputs; keep others as members.
        s = regexReplace(s, #"^\s*varying\s+[^;]+;"#, "")
        if let re = try? NSRegularExpression(pattern: #"^\s*uniform\s+\w+\s+(\w+)\s*;"#, options: [.anchorsMatchLines]) {
            let ns = s as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                if !uniforms.contains(name) {
                    out += regexReplace(ns.substring(with: m.range), #"\buniform\s+"#, "")
                }
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            s = out
        }
        s = regexReplace(s, #"\buniform\s+"#, "")
        // Types
        s = regexReplace(s, #"\bvec([234])\b"#, "float$1")
        s = regexReplace(s, #"\bivec([234])\b"#, "int$1")
        s = regexReplace(s, #"\buvec([234])\b"#, "uint$1")
        s = regexReplace(s, #"\bbvec([234])\b"#, "bool$1")
        s = regexReplace(s, #"\bmat([234])\b"#, "float$1x$1")
        s = regexReplace(s, #"\bmat([234])x([234])\b"#, "float$1x$2")
        s = regexReplace(s, #"\bsampler2D(Rect)?\b"#, "texture2d<float>")
        // Built-ins with different names
        s = regexReplace(s, #"\binversesqrt\s*\("#, "rsqrt(")
        s = regexReplace(s, #"\bdFdx\s*\("#, "dfdx(")
        s = regexReplace(s, #"\bdFdy\s*\("#, "dfdy(")
        s = regexReplace(s, #"\bgl_FragData\[0\]"#, "gl_FragColor")
        s = regexReplace(s, #"\.stpq\b"#, ".xyzw")
        s = regexReplace(s, #"\.stp\b"#, ".xyz")
        s = regexReplace(s, #"\.st\b"#, ".xy")
        // Parameter qualifiers: out/inout -> thread reference, in -> nothing
        s = regexReplace(s, #"([(,]\s*)(?:inout|out)\s+(\w+)\s+(\w+)"#, "$1thread $2& $3")
        s = regexReplace(s, #"([(,]\s*)in\s+(\w+)\s+(\w+)"#, "$1$2 $3")
        s = regexReplace(s, #"([(,]\s*)const\s+in\s+(\w+)\s+(\w+)"#, "$1const $2 $3")
        // GLSL array constructors: float[3](a, b, c) -> {a, b, c}
        s = rewriteArrayConstructors(s)
        s = removePrototypes(s)
        // `const` at struct scope needs a type and initializer — GLSL `const float x = 1.0;` already has both.
        return s
    }

    /// Translate an ISF vertex shader into (member declarations for its varyings, body of its main).
    static func vertexShader(_ vs: String, uniforms: Set<String>) -> (String, String) {
        var src = translate(stripHeader(vs), uniforms: uniforms)
        var decls = ""
        var seen = Set<String>()
        // varying/out declarations (either GLSL dialect)
        if let re = try? NSRegularExpression(pattern: #"^\s*(?:varying|out)\s+(\w+)\s+(\w+)\s*(\[\s*\d+\s*\])?\s*;"#, options: [.anchorsMatchLines]) {
            let ns = vs as NSString
            for m in re.matches(in: vs, range: NSRange(location: 0, length: ns.length)) {
                let ty = ns.substring(with: m.range(at: 1))
                let name = ns.substring(with: m.range(at: 2))
                let arr = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
                if seen.insert(name).inserted {
                    decls += "    \(translate(ty, uniforms: []).trimmingCharacters(in: .whitespacesAndNewlines)) \(name)\(arr);\n"
                }
            }
        }
        src = regexReplace(src, #"^\s*(?:out|varying)\s+\w+\s+\w+\s*(\[\s*\d+\s*\])?\s*;"#, "")
        // keep only the body of main()
        guard let r = src.range(of: #"void\s+main\s*\(\s*(void)?\s*\)\s*\{"#, options: .regularExpression) else { return (decls, "") }
        var depth = 1
        var i = r.upperBound
        while i < src.endIndex && depth > 0 {
            if src[i] == "{" { depth += 1 } else if src[i] == "}" { depth -= 1 }
            if depth > 0 { i = src.index(after: i) }
        }
        var body = String(src[r.upperBound..<i])
        body = regexReplace(body, #"\bisf_vertShaderInit\s*\(\s*\)\s*;"#, "")
        body = regexReplace(body, #"\bvv_vertShaderInit\s*\(\s*\)\s*;"#, "")
        body = regexReplace(body, #"\bgl_Position\s*=[^;]*;"#, "")
        // helper functions defined in the .vs (other than main) are also needed
        let helpers = String(src[src.startIndex..<r.lowerBound])
        return (decls + helpers, body)
    }

    /// Function prototypes (`vec4 f(vec2 p);`) at file scope can't be repeated inside a struct.
    static func removePrototypes(_ s: String) -> String {
        guard let proto = try? NSRegularExpression(pattern: #"^\s*[A-Za-z_][\w<>]*\s+[A-Za-z_]\w*\s*\([^;{}]*\)\s*;\s*$"#) else { return s }
        var depth = 0
        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let first = trimmed.split(separator: " ").first.map(String.init) ?? ""
            let isKeyword = ["return", "else", "case", "if", "while", "for", "do", "goto"].contains(first)
            if depth == 0, !isKeyword, proto.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                out.append("")   // keep line numbers stable
            } else {
                out.append(line)
            }
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        }
        return out.joined(separator: "\n")
    }

    /// Replace `type[N](...)` with `{...}` (matching parentheses).
    static func rewriteArrayConstructors(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\b(float|int|uint|bool|float[234]|int[234]|uint[234]|bool[234]|float[234]x[234])\s*\[\s*\d*\s*\]\s*\("#) else { return s }
        var chars = Array(s)
        var str = s
        while let m = re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            let ns = str as NSString
            let openIndex = m.range.location + m.range.length - 1
            var depth = 0
            var close = -1
            var i = openIndex
            chars = Array(ns as String)
            let utf16 = Array(str.utf16)
            while i < utf16.count {
                if utf16[i] == 40 { depth += 1 } else if utf16[i] == 41 { depth -= 1; if depth == 0 { close = i; break } }
                i += 1
            }
            guard close > 0 else { break }
            let inner = ns.substring(with: NSRange(location: openIndex + 1, length: close - openIndex - 1))
            str = ns.replacingCharacters(in: NSRange(location: m.range.location, length: close - m.range.location + 1), with: "{" + inner + "}")
        }
        _ = chars
        return str
    }
}
