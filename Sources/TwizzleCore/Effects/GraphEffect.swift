import CoreImage
import Foundation
import Metal

/// "Twizzle graph" plugins: a JSON patch that wires Core Image filters (and
/// other plugins) together, in the spirit of a Quartz Composer composition.
///
///     { "NAME": "Ogre", "INPUTS": [ ... ],
///       "GRAPH": [ { "ID": "edges", "FILTER": "CIEdgeWork", "INPUTS": { "inputImage": "$input", "inputRadius": 11 } },
///                  { "ID": "out", "FILTER": "CIDisplacementDistortion",
///                    "INPUTS": { "inputImage": "$input", "inputDisplacementImage": "@edges", "inputScale": "=amount*40" } } ],
///       "OUTPUT": "@out" }
///
/// Value syntax: numbers/bools, "$input" "$mask" "$prev", "@node", "=expression",
/// "%param" (typed param value; points become CI pixel vectors), arrays -> CIVector,
/// {"COLOR": [r,g,b,a]}, {"VECTOR": [...]}, {"TRANSFORM": {...}}.
final class GraphProgram: EffectProgram {
    struct Node {
        var id: String
        var filter: String?
        var shader: String?
        var inputs: [(String, JSONValue)]
        var clamp = false
        var crop = false
    }

    let url: URL
    let header: JSONValue
    let params: [ParamDescriptor]
    let nodes: [Node]
    let output: String
    weak var registry: EffectRegistry?

    init(url: URL, json: JSONValue, registry: EffectRegistry?) throws {
        self.url = url
        header = json
        self.registry = registry
        params = try (json["INPUTS"]?.array ?? []).map { try ParamDescriptor.parse($0) }
        var nodes: [Node] = []
        var ids = Set<String>()
        for (i, j) in (json["GRAPH"]?.array ?? []).enumerated() {
            let id = j["ID"]?.string ?? "node\(i)"
            guard !ids.contains(id) else { throw PluginError.invalidHeader("duplicate node ID '\(id)'") }
            ids.insert(id)
            var n = Node(id: id, filter: j["FILTER"]?.string, shader: j["SHADER"]?.string, inputs: [])
            if n.filter == nil && n.shader == nil { throw PluginError.invalidHeader("node '\(id)' needs FILTER or SHADER") }
            if let f = n.filter, CIFilter(name: f) == nil { throw PluginError.invalidHeader("unknown Core Image filter '\(f)'") }
            n.inputs = (j["INPUTS"] ?? j["PARAMS"])?.objectPairs ?? []
            if let input = j["INPUT"] { n.inputs.append(("inputImage", input)) }
            n.clamp = j["CLAMP"]?.bool ?? false
            n.crop = j["CROP"]?.bool ?? false
            nodes.append(n)
        }
        guard !nodes.isEmpty else { throw PluginError.invalidHeader("GRAPH is empty") }
        self.nodes = nodes
        output = json["OUTPUT"]?.string ?? "@\(nodes.last!.id)"
    }

    func prepare(metal: MetalContext) throws {
        for n in nodes {
            if let s = n.shader {
                guard let d = registry?.effect(id: s), d.kind == .shader else { throw PluginError.invalidHeader("node '\(n.id)': unknown shader '\(s)'") }
                try d.program.prepare(metal: metal)
            }
        }
    }

    func makeRuntime(descriptor: EffectDescriptor, metal: MetalContext) throws -> EffectRuntime {
        try prepare(metal: metal)
        return GraphRuntime(descriptor: descriptor, program: self, metal: metal)
    }
}

final class GraphRuntime: EffectRuntime {
    let descriptor: EffectDescriptor
    let program: GraphProgram
    let metal: MetalContext
    private var filters: [String: CIFilter] = [:]
    private var subRuntimes: [String: EffectRuntime] = [:]
    private var prev: MTLTexture?
    private var startTime: Double?
    private var frame = 0

    init(descriptor: EffectDescriptor, program: GraphProgram, metal: MetalContext) {
        self.descriptor = descriptor
        self.program = program
        self.metal = metal
        for n in program.nodes {
            if let f = n.filter, let filter = CIFilter(name: f) {
                filter.setDefaults()
                filters[n.id] = filter
            }
        }
    }

    func reset() {
        prev = nil
        startTime = nil
        frame = 0
        subRuntimes.values.forEach { $0.reset() }
    }

    func render(input: MTLTexture, params rawParams: [String: ParamValue], ctx: FrameContext) throws -> EffectOutput {
        let params = descriptor.resolve(rawParams)
        if startTime == nil { startTime = ctx.time }
        let t = ctx.time - (startTime ?? ctx.time)
        let W = Double(input.width), H = Double(input.height)
        let extent = CGRect(x: 0, y: 0, width: W, height: H)

        var vars: [String: Double] = ["WIDTH": W, "HEIGHT": H, "TIME": t, "FRAME": Double(frame), "DT": ctx.deltaTime]
        for p in program.params {
            let v = params[p.name] ?? p.defaultValue
            switch p.type {
            case .point2D:
                let pt = v.asPoint
                vars["\(p.name).x"] = pt[0]; vars["\(p.name).y"] = pt[1]
            case .color:
                let c = v.asColor
                vars["\(p.name).r"] = c[0]; vars["\(p.name).g"] = c[1]; vars["\(p.name).b"] = c[2]; vars["\(p.name).a"] = c[3]
            default:
                vars[p.name] = v.asDouble
            }
        }
        let face = ctx.face
        vars["FACECOUNT"] = Double(face.count)
        vars["FACE.x"] = Double(face.rect.x); vars["FACE.y"] = Double(face.rect.y)
        vars["FACE.w"] = Double(face.rect.z); vars["FACE.h"] = Double(face.rect.w)
        vars["FACECX"] = Double(face.center.x); vars["FACECY"] = Double(face.center.y)
        vars["FACERADIUS"] = max(Double(face.rect.z) * W, Double(face.rect.w) * H) / 2

        let inputImage = metal.ciImage(from: input)
        var images: [String: CIImage] = [:]
        var pooledForFrame: [MTLTexture] = []

        func expr(_ s: String) -> Double {
            (try? TwzExpression(s))?.evaluate(vars) ?? 0
        }

        func resolve(_ j: JSONValue) -> Any? {
            switch j {
            case .null: return nil
            case let .bool(b): return NSNumber(value: b)
            case let .number(n): return NSNumber(value: n)
            case let .string(s):
                if s == "$input" { return inputImage }
                if s == "$mask" { return ctx.mask.map { metal.ciImage(from: $0) } ?? CIImage(color: .white).cropped(to: extent) }
                if s == "$prev" { return prev.map { metal.ciImage(from: $0) } ?? inputImage }
                if s.hasPrefix("@") { return images[String(s.dropFirst())] }
                if s.hasPrefix("=") { return NSNumber(value: expr(String(s.dropFirst()))) }
                if s.hasPrefix("%") { return typedParam(String(s.dropFirst())) }
                return s
            case let .array(a):
                let vals = a.map { v -> CGFloat in
                    if case let .string(s) = v, s.hasPrefix("=") { return CGFloat(expr(String(s.dropFirst()))) }
                    return CGFloat(v.double ?? 0)
                }
                return CIVector(values: vals, count: vals.count)
            case .object:
                if let c = j["COLOR"]?.array {
                    let v = c.map { e -> CGFloat in
                        if case let .string(s) = e, s.hasPrefix("=") { return CGFloat(expr(String(s.dropFirst()))) }
                        return CGFloat(e.double ?? 0)
                    } + [1, 1, 1, 1]
                    return CIColor(red: v[0], green: v[1], blue: v[2], alpha: c.count > 3 ? v[3] : 1, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
                if let v = j["VECTOR"] { return resolve(v) }
                if let tr = j["TRANSFORM"] {
                    func num(_ k: String, _ d: Double) -> Double {
                        guard let v = tr[k] else { return d }
                        if case let .string(s) = v, s.hasPrefix("=") { return expr(String(s.dropFirst())) }
                        return v.double ?? d
                    }
                    var m = CGAffineTransform.identity
                    let cx = num("cx", W / 2), cy = num("cy", H / 2)
                    m = m.translatedBy(x: cx + num("tx", 0), y: cy + num("ty", 0))
                    m = m.rotated(by: num("rotate", 0) * .pi / 180)
                    m = m.scaledBy(x: num("sx", num("scale", 1)), y: num("sy", num("scale", 1)))
                    m = m.translatedBy(x: -cx, y: -cy)
                    return NSValue(bytes: [m], objCType: "{CGAffineTransform=dddddd}")
                }
                return nil
            }
        }

        func typedParam(_ name: String) -> Any? {
            switch name.lowercased() {
            case "center": return CIVector(x: W / 2, y: H / 2)
            case "extent": return CIVector(cgRect: extent)
            case "face": return CIVector(x: CGFloat(face.center.x) * W, y: (1 - CGFloat(face.center.y)) * H)
            default: break
            }
            guard let p = program.params.first(where: { $0.name == name }) else { return nil }
            let v = params[name] ?? p.defaultValue
            switch p.type {
            case .color:
                let c = v.asColor
                return CIColor(red: c[0], green: c[1], blue: c[2], alpha: c[3], colorSpace: CGColorSpaceCreateDeviceRGB())
            case .point2D:
                let pt = v.asPoint
                return CIVector(x: pt[0] * W, y: (1 - pt[1]) * H)
            case .image:
                if let tex = ctx.resources.imageTexture(path: v.asString, relativeTo: program.url.deletingLastPathComponent()) {
                    return CIImage(mtlTexture: tex, options: [.colorSpace: NSNull()])?
                        .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(tex.height)))
                }
                return nil
            case .text:
                let tex = ctx.resources.textTexture(TextTokens.expand(v.asString, localTime: t), font: p.font ?? "Helvetica-Bold", size: p.fontSize ?? 96)
                return metal.ciImage(from: tex)
            case .source:
                return ctx.sourceResolver?(v.asString).map { metal.ciImage(from: $0) }
            default:
                return NSNumber(value: v.asDouble)
            }
        }

        for n in program.nodes {
            var out: CIImage?
            if let f = filters[n.id] {
                for (key, spec) in n.inputs {
                    guard let value = resolve(spec) else { continue }
                    if f.inputKeys.contains(key) || key == "inputImage" {
                        f.setValue(value, forKey: key)
                    }
                }
                if f.inputKeys.contains(kCIInputImageKey), f.value(forKey: kCIInputImageKey) == nil {
                    f.setValue(images.values.first ?? inputImage, forKey: kCIInputImageKey)
                }
                out = f.outputImage
            } else if let shaderID = n.shader, let d = program.registry?.effect(id: shaderID) {
                // Render the node's input to a texture, run the shader plugin, wrap the result.
                var subParams: [String: ParamValue] = [:]
                var srcImage = inputImage
                for (key, spec) in n.inputs {
                    if key == "inputImage" { if let img = resolve(spec) as? CIImage { srcImage = img }; continue }
                    if let p = d.params.first(where: { $0.name == key }) {
                        switch (p.type, resolve(spec)) {
                        case let (.color, c as CIColor): subParams[key] = .color([c.red, c.green, c.blue, c.alpha])
                        case let (.point2D, v as CIVector): subParams[key] = .point([v.x / W, 1 - v.y / H])
                        case let (_, num as NSNumber): subParams[key] = p.type == .long ? .int(num.intValue) : (p.type == .bool ? .bool(num.boolValue) : .float(num.doubleValue))
                        case let (_, s as String): subParams[key] = .string(s)
                        default: break
                        }
                    }
                }
                let srcTex = metal.pool.acquire(width: input.width, height: input.height, format: metal.workingFormat)
                metal.render(srcImage.cropped(to: extent), to: srcTex, cb: ctx.commandBuffer)
                pooledForFrame.append(srcTex)
                if subRuntimes[n.id] == nil { subRuntimes[n.id] = try d.makeRuntime(metal: metal) }
                let r = try subRuntimes[n.id]!.render(input: srcTex, params: subParams, ctx: ctx)
                if r.pooled { pooledForFrame.append(r.texture) }
                out = metal.ciImage(from: r.texture)
            }
            if var img = out {
                if n.clamp { img = img.clampedToExtent() }
                if n.crop { img = img.cropped(to: extent) }
                images[n.id] = img
            }
        }

        let result: CIImage = (resolve(.string(program.output)) as? CIImage) ?? inputImage
        let target = metal.pool.acquire(width: input.width, height: input.height, format: metal.workingFormat)
        metal.render(result.cropped(to: extent), to: target, cb: ctx.commandBuffer)
        // Sub-shader textures were consumed by the CI render encoded above.
        pooledForFrame.forEach { metal.pool.release($0) }

        // Keep a copy of the output for "$prev" feedback if the graph uses it.
        if program.usesPrev {
            if prev == nil || prev!.width != input.width || prev!.height != input.height {
                prev = metal.makeTexture(width: input.width, height: input.height, label: "\(descriptor.name).prev")
            }
            metal.encodeInternal("twz_copy", cb: ctx.commandBuffer, target: prev!, textures: [target])
        }
        frame += 1
        return EffectOutput(texture: target, pooled: true)
    }
}

extension GraphProgram {
    var usesPrev: Bool {
        func scan(_ j: JSONValue) -> Bool {
            switch j {
            case let .string(s): return s == "$prev"
            case let .array(a): return a.contains(where: scan)
            case let .object(o): return o.contains(where: { scan($0.1) })
            default: return false
            }
        }
        return nodes.contains { $0.inputs.contains { scan($0.1) } }
    }
}
