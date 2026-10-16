import Foundation
import Metal

/// "Twizzle shader" plugins: a Metal Shading Language file that starts with an
/// ISF-style JSON header in a block comment. The file defines
///
///     float4 effect(Twz t) { ... }
///
/// and the engine generates the surrounding entry points, uniforms and the
/// `Twz` context struct (see docs/PLUGINS.md).
final class ShaderProgram: EffectProgram {
    struct Pass {
        var target: String?
        var persistent = false
        var float = false
        var float32 = false
        var widthExpr: TwzExpression?
        var heightExpr: TwzExpression?
        var scale: Double = 1
    }

    struct Glyphs {
        var name: String
        var chars: [String]
        var font: String
        var size: Double
    }

    struct BundledImage {
        var name: String
        var url: URL
    }

    enum Dialect { case twizzle, isf }

    let url: URL
    let source: String
    let header: JSONValue
    let dialect: Dialect
    let params: [ParamDescriptor]
    /// ISF: point2D inputs given in pixels (vs normalized), and unsupported (audio) image inputs.
    private(set) var isfPixelPoints: Set<String> = []
    private(set) var isfBlankTextures: [String] = []
    /// ISF transitions: `startImage` is the effect input, `endImage` becomes a live source.
    private(set) var isfStartImageAlias = false
    let passes: [Pass]
    let glyphs: [Glyphs]
    let images: [BundledImage]
    /// Named textures in binding order (index = 2 + position).
    let textureNames: [String]

    private var library: MTLLibrary?
    private var fragment: MTLFunction?
    private var pipelines: [UInt: MTLRenderPipelineState] = [:]
    private var compileError: Error?
    private let lock = NSLock()
    private(set) var generatedSource = ""

    static let reservedNames: Set<String> = [
        "uv", "pos", "size", "inputSize", "texel", "aspect", "time", "dt", "frame", "pass", "date", "random",
        "face", "faceCount", "faceRoll", "faceYaw", "leftEye", "rightEye", "mouth", "nose", "input", "mask", "p",
        "sample", "sampleNearest", "sampleRepeat", "sampleMirror", "load", "offset", "place", "placeAt", "placedWidth", "maskAt",
        "centered", "drawText", "edge", "grad", "blur", "blurAt",
        "float", "int", "bool", "half", "uint", "texture", "sampler", "constant", "device", "thread", "kernel",
        "vertex", "fragment", "struct", "return", "if", "else", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "true", "false", "using", "namespace", "metal", "effect", "Twz",
    ]

    static func isValidIdentifier(_ s: String) -> Bool {
        guard let first = s.first, first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && s.allSatisfy { $0.isASCII }
    }

    /// Extract the leading `/*{ ... }*/` JSON header.
    static func splitHeader(_ text: String) throws -> JSONValue {
        let trimmed = text.drop(while: { $0.isWhitespace })
        guard trimmed.hasPrefix("/*") else { throw PluginError.invalidHeader("file must start with a /*{ JSON }*/ header") }
        guard let end = trimmed.range(of: "*/") else { throw PluginError.invalidHeader("unterminated header comment") }
        let json = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<end.lowerBound]
        do { return try JSONValue.parse(String(json)) } catch {
            throw PluginError.invalidHeader("header JSON: \((error as NSError).userInfo[NSDebugDescriptionErrorKey] ?? error)")
        }
    }

    init(url: URL, text: String, dialect: Dialect = .twizzle) throws {
        self.url = url
        source = text
        self.dialect = dialect
        header = try ShaderProgram.splitHeader(text)

        var params: [ParamDescriptor] = []
        var pixelPoints = Set<String>()
        var blank: [String] = []
        for j in header["INPUTS"]?.array ?? [] {
            if dialect == .isf, let ty = j["TYPE"]?.string?.lowercased(), ty.hasPrefix("audio"), let n = j["NAME"]?.string {
                blank.append(n)   // audio waveform/FFT inputs aren't supported: bind an empty texture
                continue
            }
            var p = try ParamDescriptor.parse(j)
            if dialect == .isf, p.type == .image, p.name == "startImage" {
                isfStartImageAlias = true
                continue
            }
            if dialect == .isf, p.type == .image, p.name == "endImage" {
                p.type = .source
                p.label = "Transition To"
                p.defaultValue = .string("pattern:plasma")
            }
            if dialect == .isf, p.type == .point2D {
                // ISF points are often in pixels; normalize using MAX (or assume 1920×1080).
                let mx = j["MAX"]?.doubles ?? []
                let d = j["DEFAULT"]?.doubles ?? [0.5, 0.5]
                let scale = mx.count >= 2 && (mx[0] > 1.5 || mx[1] > 1.5) ? [mx[0], mx[1]] : ((d.first ?? 0) > 1.5 ? [1920.0, 1080.0] : [1.0, 1.0])
                if scale[0] > 1.5 { pixelPoints.insert(p.name) }
                let nd = [d.count > 0 ? d[0] / scale[0] : 0.5, 1.0 - (d.count > 1 ? d[1] / scale[1] : 0.5)]
                p.defaultValue = .point(nd)
            }
            // ISF's implicit inputImage is our `input`.
            if p.name == "inputImage" { continue }
            guard ShaderProgram.isValidIdentifier(p.name) else { throw PluginError.invalidHeader("bad input name '\(p.name)'") }
            if [.image, .text, .source].contains(p.type), ShaderProgram.reservedNames.contains(p.name) {
                throw PluginError.invalidHeader("input name '\(p.name)' is reserved")
            }
            params.append(p)
        }
        self.params = params
        isfPixelPoints = pixelPoints
        isfBlankTextures = blank
        let persistentBuffers = Set(header["PERSISTENT_BUFFERS"]?.strings ?? (header["PERSISTENT_BUFFERS"]?.objectPairs?.map(\.0) ?? []))

        var passes: [Pass] = []
        for j in header["PASSES"]?.array ?? [] {
            var p = Pass()
            p.target = j["TARGET"]?.string
            p.persistent = j["PERSISTENT"]?.bool ?? false
            if let t = p.target, persistentBuffers.contains(t) { p.persistent = true }
            p.float = j["FLOAT"]?.bool ?? false
            p.float32 = j["FLOAT32"]?.bool ?? false
            if let w = j["WIDTH"]?.string { p.widthExpr = try TwzExpression(w) }
            if let h = j["HEIGHT"]?.string { p.heightExpr = try TwzExpression(h) }
            p.scale = j["SCALE"]?.double ?? 1
            if let t = p.target, !ShaderProgram.isValidIdentifier(t) || (dialect == .twizzle && ShaderProgram.reservedNames.contains(t)) {
                throw PluginError.invalidHeader("bad pass TARGET '\(t)'")
            }
            passes.append(p)
        }
        if passes.isEmpty { passes = [Pass()] }
        for (i, p) in passes.enumerated() where p.target == nil && i != passes.count - 1 {
            throw PluginError.invalidHeader("pass \(i) needs a TARGET (only the last pass may omit it)")
        }
        self.passes = passes

        var glyphs: [Glyphs] = []
        for j in header["GLYPHS"]?.array ?? [] {
            guard let name = j["NAME"]?.string, ShaderProgram.isValidIdentifier(name) else {
                throw PluginError.invalidHeader("GLYPHS entry needs a valid NAME")
            }
            var chars: [String]
            if let a = j["CHARS"]?.array { chars = a.compactMap { $0.string } } else {
                chars = (j["CHARS"]?.string ?? " .:-=+*#%@").map { String($0) }
            }
            if let range = j["RANGE"]?.doubles, range.count == 2 {
                chars += (Int(range[0])...Int(range[1])).compactMap { UnicodeScalar($0).map { String(Character($0)) } }
            }
            glyphs.append(Glyphs(name: name, chars: chars, font: j["FONT"]?.string ?? "Menlo-Bold", size: j["SIZE"]?.double ?? 48))
        }
        self.glyphs = glyphs

        var images: [BundledImage] = []
        if dialect == .isf, let imported = header["IMPORTED"] {
            // ISF v2: {"name": {"PATH": "x.png"}} ; v1: [{"NAME": "name", "PATH": "x.png"}]
            let entries: [(String, JSONValue)] = imported.objectPairs ?? (imported.array ?? []).compactMap { e in e["NAME"]?.string.map { ($0, e) } }
            for (name, e) in entries {
                if let path = e["PATH"]?.string ?? e.string {
                    images.append(BundledImage(name: name, url: url.deletingLastPathComponent().appendingPathComponent(path)))
                }
            }
        }
        for j in header["IMAGES"]?.array ?? [] {
            guard let name = j["NAME"]?.string, ShaderProgram.isValidIdentifier(name), let path = j["PATH"]?.string else {
                throw PluginError.invalidHeader("IMAGES entry needs NAME and PATH")
            }
            images.append(BundledImage(name: name, url: url.deletingLastPathComponent().appendingPathComponent(path)))
        }
        self.images = images

        var names: [String] = []
        for p in passes { if let t = p.target, !names.contains(t) { names.append(t) } }
        names += glyphs.map(\.name)
        names += images.map(\.name)
        names += params.filter { [.image, .text, .source].contains($0.type) }.map(\.name)
        names += blank
        guard Set(names).count == names.count else { throw PluginError.invalidHeader("duplicate texture names: \(names)") }
        textureNames = names
    }

    // MARK: Code generation

    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    #ifndef PI
    #define PI 3.14159265358979
    #endif
    #define TAU 6.28318530717959

    struct TwzVOut { float4 position [[position]]; float2 uv; };

    struct TwzGlobals {
        float4 size;      // pass w,h ; input w,h
        float4 timing;    // time, dt, frame, pass
        float4 date;      // year, month, day, seconds of day
        float4 random;
        float4 face;      // x,y,w,h normalized, top-left origin
        float4 faceInfo;  // count, roll, yaw, confidence
        float4 eyes;      // left.xy right.xy
        float4 mouthNose; // mouth.xy nose.xy
    };

    constexpr sampler twz_linear(filter::linear, address::clamp_to_edge);
    constexpr sampler twz_nearest(filter::nearest, address::clamp_to_edge);
    constexpr sampler twz_repeat(filter::linear, address::repeat);
    constexpr sampler twz_mirrored(filter::linear, address::mirrored_repeat);

    // ---- GLSL compatibility -------------------------------------------------
    inline float mod(float x, float y) { return x - y * floor(x / y); }
    inline float2 mod(float2 x, float y) { return x - y * floor(x / y); }
    inline float2 mod(float2 x, float2 y) { return x - y * floor(x / y); }
    inline float3 mod(float3 x, float y) { return x - y * floor(x / y); }
    inline float4 mod(float4 x, float y) { return x - y * floor(x / y); }
    inline float atan(float y, float x) { return atan2(y, x); }

    // ---- helper library ---------------------------------------------------
    inline float3 posterize(float3 c, float levels) { return floor(c * levels + 0.5) / levels; }
    inline float gauss(float x, float sigma) { return exp(-(x * x) / (2.0 * sigma * sigma)); }
    inline float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }
    inline float luma(float4 c) { return dot(c.rgb, float3(0.299, 0.587, 0.114)); }
    inline float3 rgb2hsv(float3 c) {
        float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        float e = 1.0e-10;
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
    }
    inline float3 hsv2rgb(float3 c) {
        float3 p = abs(fract(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
        return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
    }
    inline float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
    inline float hash12(float2 p) { float3 p3 = fract(float3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
    inline float2 hash22(float2 p) { float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
    inline float3 hash32(float2 p) { float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yxz + 33.33); return fract((p3.xxy + p3.yzz) * p3.zyx); }
    inline float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash12(i), hash12(i + float2(1, 0)), u.x), mix(hash12(i + float2(0, 1)), hash12(i + float2(1, 1)), u.x), u.y);
    }
    inline float fbm(float2 p, int octaves) {
        float v = 0.0, a = 0.5;
        for (int i = 0; i < octaves; i++) { v += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
        return v;
    }
    inline float2 rotate2d(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }
    inline float4 over(float4 top, float4 bottom) {   // straight-alpha "over"
        float a = top.a + bottom.a * (1.0 - top.a);
        float3 c = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 1e-5);
        return float4(c, a);
    }
    inline float4 overPremul(float4 top, float4 bottom) { return top + bottom * (1.0 - top.a); }
    inline float3 blendScreen(float3 b, float3 l) { return 1.0 - (1.0 - b) * (1.0 - l); }
    inline float3 blendOverlay(float3 b, float3 l) { return mix(2.0 * b * l, 1.0 - 2.0 * (1.0 - b) * (1.0 - l), step(0.5, b)); }
    inline float3 blendSoftLight(float3 b, float3 l) { return mix(2.0 * b * l + b * b * (1.0 - 2.0 * l), sqrt(b) * (2.0 * l - 1.0) + 2.0 * b * (1.0 - l), step(0.5, l)); }
    inline float sdCircle(float2 p, float r) { return length(p) - r; }
    inline float sdBox(float2 p, float2 b) { float2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
    inline float sdRoundBox(float2 p, float2 b, float r) { return sdBox(p, b - r) - r; }
    inline float3 palette(float t, float3 a, float3 b, float3 c, float3 d) { return a + b * cos(TAU * (c * t + d)); }
    /// Coverage (0..1) of glyph `index` from a horizontal strip atlas of `count` cells.
    inline float glyphAt(texture2d<float> atlas, int count, int index, float2 cellUV) {
        float n = float(max(count, 1));
        float cw = float(atlas.get_width()) / n;
        float2 c = clamp(cellUV, float2(0.5 / cw, 0.5 / float(atlas.get_height())), float2(1.0 - 0.5 / cw, 1.0 - 0.5 / float(atlas.get_height())));
        float2 auv = float2((float(clamp(index, 0, count - 1)) + c.x) / n, c.y);
        return atlas.sample(twz_linear, auv).a;
    }
    /// Full color (e.g. emoji) of glyph `index`, straight alpha.
    inline float4 glyphColorAt(texture2d<float> atlas, int count, int index, float2 cellUV) {
        float n = float(max(count, 1));
        float cw = float(atlas.get_width()) / n;
        float2 c = clamp(cellUV, float2(0.5 / cw, 0.5 / float(atlas.get_height())), float2(1.0 - 0.5 / cw, 1.0 - 0.5 / float(atlas.get_height())));
        float2 auv = float2((float(clamp(index, 0, count - 1)) + c.x) / n, c.y);
        return atlas.sample(twz_linear, auv);
    }

    """

    func generate() -> String {
        if dialect == .isf { return generateISF() }
        var s = ShaderProgram.prelude
        // Glyph counts
        for g in glyphs { s += "constant int \(g.name)_COUNT = \(g.chars.count);\n" }
        // Params struct
        s += "struct TwzParams {\n"
        var anyParam = false
        for p in params {
            switch p.type {
            case .float: s += "    float \(p.name);\n"
            case .long: s += "    int \(p.name);\n"
            case .bool, .event: s += "    bool \(p.name);\n"
            case .color: s += "    float4 \(p.name);\n"
            case .point2D: s += "    float2 \(p.name);\n"
            case .image, .text, .source: s += "    float2 \(p.name)_size;\n"
            }
            anyParam = true
        }
        if !anyParam { s += "    int _unused;\n" }
        s += "};\n"
        s += "struct TwzParamsBuffer { float4 v[\(max(1, params.count))]; };\n"
        // Context struct
        s += """
        struct Twz {
            float2 uv;         // 0..1 in the current pass target, (0,0) = top-left
            float2 pos;        // pixel position in the current pass target
            float2 size;       // current pass target size (pixels)
            float2 inputSize;  // input image size (pixels)
            float2 texel;      // 1 / inputSize
            float aspect;      // size.x / size.y
            float time;        // seconds since this effect instance started
            float dt;          // seconds since last frame
            int frame;         // frame counter for this instance
            int pass;          // current pass index
            float4 date;       // year, month, day, seconds since midnight
            float4 random;     // fresh random numbers each frame
            float4 face;       // primary face rect x,y,w,h (normalized; valid if faceCount > 0)
            int faceCount;
            float faceRoll;    // radians
            float faceYaw;     // radians
            float2 leftEye, rightEye, mouth, nose;
            texture2d<float> input;
            texture2d<float> mask;   // person segmentation (r), white if unavailable

        """
        for n in textureNames { s += "    texture2d<float> \(n);\n" }
        s += """
            TwzParams p;

            float4 sample(float2 uv) const { return input.sample(twz_linear, uv); }
            float4 sample(texture2d<float> tex, float2 uv) const { return tex.sample(twz_linear, uv); }
            float4 sampleNearest(texture2d<float> tex, float2 uv) const { return tex.sample(twz_nearest, uv); }
            float4 sampleRepeat(texture2d<float> tex, float2 uv) const { return tex.sample(twz_repeat, uv); }
            float4 sampleMirror(texture2d<float> tex, float2 uv) const { return tex.sample(twz_mirrored, uv); }
            /// Sample the input at pixel coordinates (pixel centers at +0.5).
            float4 load(float2 px) const { return input.sample(twz_linear, px / inputSize); }
            float4 load(texture2d<float> tex, float2 px) const { return tex.sample(twz_linear, px / float2(tex.get_width(), tex.get_height())); }
            /// Sample the input offset from the current uv by `dpx` input pixels.
            float4 offset(float2 dpx) const { return input.sample(twz_linear, uv + dpx * texel); }
            float maskAt(float2 q) const { return mask.sample(twz_linear, q).r; }
            /// uv re-centered on (0,0) with x scaled by aspect (circles stay round).
            float2 centered() const { return (uv - 0.5) * float2(aspect, 1.0); }
            float2 centered(float2 q) const { return (q - 0.5) * float2(aspect, 1.0); }
            /// Color of `tex` drawn centered at `center` (normalized), `height` = fraction of output height. 0 outside.
            float4 place(texture2d<float> tex, float2 center, float height) const { return placeAt(tex, uv, center, height); }
            float4 placeAt(texture2d<float> tex, float2 q, float2 center, float height) const {
                float2 ts = float2(tex.get_width(), tex.get_height());
                float2 sz = float2(height * ts.x / ts.y / aspect, height);
                float2 l = (q - center) / sz + 0.5;
                if (any(l < 0.0) || any(l > 1.0)) return float4(0.0);
                return tex.sample(twz_linear, l);
            }
            /// Width (as a fraction of output width) of `tex` drawn at `height`.
            float placedWidth(texture2d<float> tex, float height) const {
                return height * float(tex.get_width()) / float(tex.get_height()) / aspect;
            }
            /// Draw a (white) text texture tinted `color` with a drop shadow over `base`.
            float4 drawText(float4 base, texture2d<float> tex, float2 center, float height, float4 color, float4 shadow) const {
                float2 so = float2(0.05 * height / aspect, 0.05 * height);
                float sa = placeAt(tex, uv - so, center, height).a * shadow.a;
                float3 c = mix(base.rgb, shadow.rgb, sa);
                float a = placeAt(tex, uv, center, height).a * color.a;
                return float4(mix(c, color.rgb, a), base.a);
            }
            /// Sobel edge magnitude of the input's luma, `px` = sample spacing in input pixels.
            float edge(float px) const {
                float tl = luma(offset(float2(-px, -px)).rgb), tc = luma(offset(float2(0, -px)).rgb), tr = luma(offset(float2(px, -px)).rgb);
                float ml = luma(offset(float2(-px, 0)).rgb), mr = luma(offset(float2(px, 0)).rgb);
                float bl = luma(offset(float2(-px, px)).rgb), bc = luma(offset(float2(0, px)).rgb), br = luma(offset(float2(px, px)).rgb);
                float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
                float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
                return sqrt(gx * gx + gy * gy);
            }
            /// Luma gradient (dx, dy) of the input at the current uv.
            float2 grad(float px) const {
                return float2(luma(offset(float2(px, 0)).rgb) - luma(offset(float2(-px, 0)).rgb),
                              luma(offset(float2(0, px)).rgb) - luma(offset(float2(0, -px)).rgb)) * 0.5;
            }
            /// Cheap blur of the input around `q` (radius in input pixels, 13 taps).
            float4 blurAt(float2 q, float radius) const {
                const float2 k[12] = { float2(1,0), float2(-1,0), float2(0,1), float2(0,-1), float2(0.7,0.7), float2(-0.7,0.7),
                                       float2(0.7,-0.7), float2(-0.7,-0.7), float2(0.5,0.0), float2(-0.5,0.0), float2(0.0,0.5), float2(0.0,-0.5) };
                float4 acc = input.sample(twz_linear, q) * 2.0;
                float w = 2.0;
                for (int i = 0; i < 12; i++) {
                    float wi = i < 8 ? 1.0 : 1.5;
                    acc += input.sample(twz_linear, q + k[i] * radius * texel) * wi;
                    w += wi;
                }
                return acc / w;
            }
            float4 blur(float radius) const { return blurAt(uv, radius); }
        };

        """
        let fileName = url.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        s += "#line 1 \"\(fileName)\"\n"
        s += source
        s += "\n#line 1 \"<twizzle wrapper>\"\n"
        // Fragment wrapper
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
            Twz t;
            t.uv = in.uv;
            t.pos = in.position.xy;
            t.size = G.size.xy;
            t.inputSize = G.size.zw;
            t.texel = 1.0 / G.size.zw;
            t.aspect = G.size.x / G.size.y;
            t.time = G.timing.x;
            t.dt = G.timing.y;
            t.frame = int(G.timing.z);
            t.pass = int(G.timing.w);
            t.date = G.date;
            t.random = G.random;
            t.face = G.face;
            t.faceCount = int(G.faceInfo.x);
            t.faceRoll = G.faceInfo.y;
            t.faceYaw = G.faceInfo.z;
            t.leftEye = G.eyes.xy;
            t.rightEye = G.eyes.zw;
            t.mouth = G.mouthNose.xy;
            t.nose = G.mouthNose.zw;
            t.input = twz_tex0;
            t.mask = twz_tex1;

        """
        for (i, n) in textureNames.enumerated() { s += "    t.\(n) = twz_tex\(i + 2);\n" }
        for (i, p) in params.enumerated() {
            switch p.type {
            case .float: s += "    t.p.\(p.name) = PB.v[\(i)].x;\n"
            case .long: s += "    t.p.\(p.name) = int(round(PB.v[\(i)].x));\n"
            case .bool, .event: s += "    t.p.\(p.name) = PB.v[\(i)].x > 0.5;\n"
            case .color: s += "    t.p.\(p.name) = PB.v[\(i)];\n"
            case .point2D: s += "    t.p.\(p.name) = PB.v[\(i)].xy;\n"
            case .image, .text, .source: s += "    t.p.\(p.name)_size = PB.v[\(i)].xy;\n"
            }
        }
        if params.isEmpty { s += "    t.p._unused = 0;\n" }
        s += "    return effect(t);\n}\n"
        return s
    }

    /// Lines of generated code before the user's source (for error messages without #line support).
    func prepare(metal: MetalContext) throws {
        lock.lock(); defer { lock.unlock() }
        if fragment != nil { return }
        if let compileError { throw compileError }
        let src = generate()
        generatedSource = src
        do {
            let opts = MTLCompileOptions()
            opts.mathMode = .relaxed
            let lib = try metal.device.makeLibrary(source: src, options: opts)
            guard let f = lib.makeFunction(name: "twz_fragment") else { throw PluginError.compile("no twz_fragment generated") }
            library = lib
            fragment = f
        } catch let e as PluginError {
            compileError = e
            throw e
        } catch {
            let msg = ShaderProgram.cleanCompilerMessage("\(error)")
            let e = PluginError.compile(msg)
            compileError = e
            throw e
        }
    }

    static func cleanCompilerMessage(_ raw: String) -> String {
        // Keep only error lines and their context, drop the noisy NSError wrapper.
        var text = raw
        if let r = text.range(of: "Compilation failed: ") { text = String(text[r.upperBound...]) }
        if let r = text.range(of: "UserInfo=") { text = String(text[..<r.lowerBound]) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var keep: [Substring] = []
        var inError = false
        for l in lines {
            if l.contains(": error:") { inError = true; keep.append(l); continue }
            if l.contains(": warning:") || l.contains(": note:") { inError = l.contains(": note:") && inError; if inError { keep.append(l) }; continue }
            if inError, keep.count < 60 { keep.append(l) }
        }
        let out = keep.isEmpty ? text : keep.joined(separator: "\n")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pipeline(metal: MetalContext, format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        try prepare(metal: metal)
        lock.lock(); defer { lock.unlock() }
        if let p = pipelines[format.rawValue] { return p }
        let p = try metal.makePipeline(fragment: fragment!, format: format)
        pipelines[format.rawValue] = p
        return p
    }

    func makeRuntime(descriptor: EffectDescriptor, metal: MetalContext) throws -> EffectRuntime {
        try prepare(metal: metal)
        return ShaderRuntime(descriptor: descriptor, program: self, metal: metal)
    }
}

/// Double-buffered render target owned by a shader instance.
final class TargetBuffer {
    var read: MTLTexture
    var write: MTLTexture
    init(read: MTLTexture, write: MTLTexture) { self.read = read; self.write = write }
    func swap() { Swift.swap(&read, &write) }
}

final class ShaderRuntime: EffectRuntime {
    let descriptor: EffectDescriptor
    let program: ShaderProgram
    let metal: MetalContext
    private var targets: [String: TargetBuffer] = [:]
    private var needsClear: Set<String> = []
    private var startTime: Double?
    private var frame = 0
    private var lastEventState: [String: Bool] = [:]
    private var glyphTextures: [String: MTLTexture] = [:]
    private var bundledTextures: [String: MTLTexture] = [:]

    init(descriptor: EffectDescriptor, program: ShaderProgram, metal: MetalContext) {
        self.descriptor = descriptor
        self.program = program
        self.metal = metal
    }

    func reset() {
        targets.removeAll()
        startTime = nil
        frame = 0
    }

    private func targetSize(_ pass: ShaderProgram.Pass, input: MTLTexture, vars: [String: Double]) -> (Int, Int) {
        var w = Double(input.width) * pass.scale
        var h = Double(input.height) * pass.scale
        if let e = pass.widthExpr { w = e.evaluate(vars) }
        if let e = pass.heightExpr { h = e.evaluate(vars) }
        return (max(1, min(8192, Int(w.rounded()))), max(1, min(8192, Int(h.rounded()))))
    }

    func render(input: MTLTexture, params rawParams: [String: ParamValue], ctx: FrameContext) throws -> EffectOutput {
        let params = descriptor.resolve(rawParams)
        if startTime == nil { startTime = ctx.time }
        let localTime = ctx.time - (startTime ?? ctx.time)
        let cb = ctx.commandBuffer

        // Expression variables for pass sizes
        var vars: [String: Double] = ["WIDTH": Double(input.width), "HEIGHT": Double(input.height)]
        for p in program.params where [.float, .long, .bool].contains(p.type) { vars[p.name] = params[p.name]?.asDouble ?? 0 }

        // Param buffer (events fire for one frame on a rising edge)
        var slots = [SIMD4<Float>](repeating: .zero, count: max(1, program.params.count))
        var named: [String: MTLTexture] = [:]
        for (i, p) in program.params.enumerated() {
            let v = params[p.name] ?? p.defaultValue
            switch p.type {
            case .event:
                let now = v.asBool
                let fire = now && !(lastEventState[p.name] ?? false)
                lastEventState[p.name] = now
                slots[i] = SIMD4(fire ? 1 : 0, 0, 0, 0)
            case .text:
                let tex = ctx.resources.textTexture(TextTokens.expand(v.asString, localTime: localTime),
                                                     font: p.font ?? "Helvetica-Bold", size: p.fontSize ?? 96)
                named[p.name] = tex
                slots[i] = SIMD4(Float(tex.width), Float(tex.height), 0, 0)
            case .image:
                let path = v.asString
                let tex = path.isEmpty ? nil : ctx.resources.imageTexture(path: path, relativeTo: program.url.deletingLastPathComponent())
                named[p.name] = tex ?? metal.clearTexture
                slots[i] = SIMD4(Float(tex?.width ?? 0), Float(tex?.height ?? 0), 0, 0)
            case .source:
                let key = v.asString
                let tex = key.isEmpty ? nil : ctx.sourceResolver?(key)
                named[p.name] = tex ?? metal.clearTexture
                slots[i] = SIMD4(Float(tex?.width ?? 0), Float(tex?.height ?? 0), 0, 0)
            default:
                slots[i] = v.packed
            }
        }
        for g in program.glyphs {
            if glyphTextures[g.name] == nil {
                glyphTextures[g.name] = ctx.resources.glyphAtlas(chars: g.chars, font: g.font, size: g.size)
            }
            named[g.name] = glyphTextures[g.name]
        }
        for img in program.images {
            if bundledTextures[img.name] == nil {
                bundledTextures[img.name] = ctx.resources.imageTexture(path: img.url.path, relativeTo: nil)
            }
            named[img.name] = bundledTextures[img.name] ?? metal.clearTexture
        }

        // Allocate/resize targets
        for pass in program.passes {
            guard let name = pass.target else { continue }
            let (w, h) = targetSize(pass, input: input, vars: vars)
            let fmt: MTLPixelFormat = pass.float32 ? .rgba32Float : (pass.float ? .rgba16Float : metal.workingFormat)
            if let t = targets[name], t.read.width == w, t.read.height == h, t.read.pixelFormat == fmt { continue }
            targets[name] = TargetBuffer(read: metal.makeTexture(width: w, height: h, format: fmt, label: "\(descriptor.name).\(name)"),
                                         write: metal.makeTexture(width: w, height: h, format: fmt, label: "\(descriptor.name).\(name)'"))
            needsClear.insert(name)
        }
        for name in needsClear {
            if let t = targets[name] {
                for tex in [t.read, t.write] {
                    metal.encodeInternal("twz_copy", cb: cb, target: tex, textures: [metal.clearTexture], clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0))
                }
            }
        }
        needsClear.removeAll()

        // Globals
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: now)
        let secs = Double((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)) + Double(comps.nanosecond ?? 0) / 1e9
        let face = ctx.face
        var globals = [SIMD4<Float>](repeating: .zero, count: 8)
        globals[2] = SIMD4(Float(comps.year ?? 0), Float(comps.month ?? 0), Float(comps.day ?? 0), Float(secs))
        globals[3] = SIMD4(Float.random(in: 0..<1), Float.random(in: 0..<1), Float.random(in: 0..<1), Float.random(in: 0..<1))
        globals[4] = face.rect
        globals[5] = SIMD4(Float(face.count), face.roll, face.yaw, face.confidence)
        globals[6] = SIMD4(face.leftEye.x, face.leftEye.y, face.rightEye.x, face.rightEye.y)
        globals[7] = SIMD4(face.mouth.x, face.mouth.y, face.nose.x, face.nose.y)

        var output: EffectOutput?
        for (pi, pass) in program.passes.enumerated() {
            let isLast = pi == program.passes.count - 1
            let target: MTLTexture
            if let name = pass.target {
                target = targets[name]!.write
            } else {
                target = metal.pool.acquire(width: input.width, height: input.height, format: metal.workingFormat)
            }
            globals[0] = SIMD4(Float(target.width), Float(target.height), Float(input.width), Float(input.height))
            globals[1] = SIMD4(Float(localTime), Float(ctx.deltaTime), Float(frame), Float(pi))

            let pipeline = try program.pipeline(metal: metal, format: target.pixelFormat)
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = target
            rp.colorAttachments[0].loadAction = .dontCare
            rp.colorAttachments[0].storeAction = .store
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { continue }
            enc.label = "\(descriptor.name) pass \(pi)"
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(&globals, length: MemoryLayout<SIMD4<Float>>.stride * globals.count, index: 0)
            enc.setFragmentBytes(&slots, length: MemoryLayout<SIMD4<Float>>.stride * slots.count, index: 1)
            enc.setFragmentTexture(input, index: 0)
            enc.setFragmentTexture(ctx.mask ?? metal.whiteTexture, index: 1)
            for (ti, name) in program.textureNames.enumerated() {
                let tex = targets[name]?.read ?? named[name] ?? metal.clearTexture
                enc.setFragmentTexture(tex, index: ti + 2)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()

            if let name = pass.target { targets[name]!.swap() }
            if isLast {
                if let name = pass.target {
                    output = EffectOutput(texture: targets[name]!.read, pooled: false)
                } else {
                    output = EffectOutput(texture: target, pooled: true)
                }
            }
        }
        frame += 1
        return output ?? EffectOutput(texture: input, pooled: false)
    }
}
