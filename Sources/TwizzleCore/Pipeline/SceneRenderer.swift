import CoreVideo
import Foundation
import Metal

/// Per-frame status for the UI.
public struct SceneStatus {
    public var effectErrors: [UUID: String] = [:]
    public var layerStates: [UUID: SourceState] = [:]
    public var faceCount = 0
    public var renderMS = 0.0
}

/// Renders one SceneConfig: sources → per-layer effects → composite → master effects.
public final class SceneRenderer {
    public private(set) var config: SceneConfig
    let metal: MetalContext
    let registry: EffectRegistry
    let sources: SourceManager
    let resources: ResourceCache
    private var layerRunners: [UUID: EffectStackRunner] = [:]
    private let masterRunner = EffectStackRunner()
    private var held: Set<String> = []          // source keys we hold a reference to
    public private(set) var status = SceneStatus()

    public init(config: SceneConfig, metal: MetalContext, registry: EffectRegistry, sources: SourceManager, resources: ResourceCache) {
        self.config = config
        self.metal = metal
        self.registry = registry
        self.sources = sources
        self.resources = resources
    }

    public func update(_ c: SceneConfig) { config = c }

    public func resetEffect(_ id: UUID) {
        masterRunner.reset(id)
        layerRunners.values.forEach { $0.reset(id) }
    }

    /// Release all sources (scene removed / disabled).
    public func teardown() {
        for k in held { sources.release(k) }
        held.removeAll()
    }

    /// Source keys referenced by layers and by `source` parameters.
    private func referencedSourceKeys() -> Set<String> {
        var keys = Set<String>()
        func scan(_ effects: [EffectConfig]) {
            for e in effects where e.enabled {
                guard let d = registry.effect(id: e.effectID) else { continue }
                for p in d.params where p.type == .source {
                    if let v = e.params[p.name]?.asString, !v.isEmpty { keys.insert(v) }
                }
            }
        }
        for l in config.layers where l.enabled {
            keys.insert(l.source.key)
            scan(l.effects)
        }
        scan(config.effects)
        return keys
    }

    private func syncSources() {
        let want = referencedSourceKeys()
        for k in want.subtracting(held) {
            if let spec = config.layers.first(where: { $0.source.key == k })?.source ?? SourceSpec.parse(key: k) {
                _ = sources.acquire(spec)
                held.insert(k)
            }
        }
        for k in held.subtracting(want) {
            sources.release(k)
            held.remove(k)
        }
    }

    /// uv mapping canvas → source for a fit mode: srcUV = uv * scale + offset.
    static func fitTransform(srcW: Int, srcH: Int, dstW: Int, dstH: Int, fit: FitMode, crop: [Double]) -> (SIMD2<Float>, SIMD2<Float>) {
        let c = crop.count == 4 ? crop.map { min(max($0, 0), 0.45) } : [0, 0, 0, 0]
        let x0 = c[0], y0 = c[1], cw = max(0.05, 1 - c[0] - c[2]), ch = max(0.05, 1 - c[1] - c[3])
        let srcAspect = (Double(srcW) * cw) / max(1, Double(srcH) * ch)
        let dstAspect = Double(dstW) / Double(max(1, dstH))
        var sx = cw, sy = ch, ox = x0, oy = y0
        switch fit {
        case .stretch: break
        case .fill:
            if srcAspect > dstAspect {
                let f = dstAspect / srcAspect
                sx = cw * f; ox = x0 + cw * (0.5 - 0.5 * f)
            } else {
                let f = srcAspect / dstAspect
                sy = ch * f; oy = y0 + ch * (0.5 - 0.5 * f)
            }
        case .fit:
            if srcAspect > dstAspect {
                let f = srcAspect / dstAspect
                sy = ch * f; oy = y0 + ch * (0.5 - 0.5 * f)
            } else {
                let f = dstAspect / srcAspect
                sx = cw * f; ox = x0 + cw * (0.5 - 0.5 * f)
            }
        }
        return (SIMD2(Float(sx), Float(sy)), SIMD2(Float(ox), Float(oy)))
    }

    /// Fit a source frame into a canvas-sized texture. Returns a pooled texture.
    private func fitFrame(_ frame: SourceFrame, spec: SourceSpec, fit: FitMode, crop: [Double], mirror: Bool,
                          ctx: FrameContext, time: Double) -> (MTLTexture, SIMD2<Float>, SIMD2<Float>)? {
        let W = config.width, H = config.height
        let out = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
        var srcTex: MTLTexture?
        if let pb = frame.pixelBuffer, let (t, cvt) = metal.texture(from: pb) {
            srcTex = t
            ctx.retain(cvt)
            ctx.retain(pb)
        } else if let t = frame.texture {
            srcTex = t
        }
        guard let srcTex else { metal.pool.release(out); return nil }
        let (scale, offset) = SceneRenderer.fitTransform(srcW: srcTex.width, srcH: srcTex.height, dstW: W, dstH: H, fit: fit, crop: crop)
        metal.encodeInternal("twz_fit", cb: ctx.commandBuffer, target: out, textures: [srcTex], uniforms: [
            SIMD4(scale.x, scale.y, offset.x, offset.y),
            SIMD4(mirror ? 1 : 0, 1, 0, 0),
            SIMD4(0, 0, 0, 1),
        ])
        return (out, scale, offset)
    }

    private func fitMask(_ pb: CVPixelBuffer, scale: SIMD2<Float>, offset: SIMD2<Float>, mirror: Bool, ctx: FrameContext) -> MTLTexture? {
        var tex: MTLTexture?
        if let (t, cvt) = metal.texture(from: pb, format: .r8Unorm) {
            tex = t
            ctx.retain(cvt)
            ctx.retain(pb)
        } else {
            // Not IOSurface-backed: upload.
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
            d.usage = .shaderRead
            if let t = metal.device.makeTexture(descriptor: d), let base = CVPixelBufferGetBaseAddress(pb) {
                t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: CVPixelBufferGetBytesPerRow(pb))
                tex = t
            }
        }
        guard let tex else { return nil }
        let out = metal.pool.acquire(width: config.width, height: config.height, format: metal.workingFormat)
        metal.encodeInternal("twz_fit_mask", cb: ctx.commandBuffer, target: out, textures: [tex], uniforms: [
            SIMD4(scale.x, scale.y, offset.x, offset.y), SIMD4(mirror ? 1 : 0, 0, 0, 0),
        ])
        return out
    }

    private func placementUniforms(_ l: LayerConfig) -> [SIMD4<Float>] {
        return [
            SIMD4(Float(l.x), Float(l.y), Float(l.scale), Float(l.rotation * .pi / 180)),
            SIMD4(Float(config.width), Float(config.height), Float(l.opacity), Float(l.blend.index)),
            SIMD4(0, 0, 0, 0),  // layer-space crop (crop is applied when fitting the source)
        ]
    }

    /// Render a frame. The returned texture is pooled if `pooled` (caller releases).
    public func render(ctx: FrameContext) -> EffectOutput {
        let t0 = CACurrentMediaTimeCompat()
        syncSources()
        let W = config.width, H = config.height
        var canvas: MTLTexture?
        var canvasFace: FaceInfo?
        var canvasMask: MTLTexture?
        var newStatus = SceneStatus()
        let masterNeeds = masterRunner.needs(config.effects, registry: registry)

        // Per-frame cache for `source` parameters.
        var resolved: [String: MTLTexture] = [:]
        ctx.sourceResolver = { [weak self] key in
            guard let self else { return nil }
            if let t = resolved[key] { return t }
            guard let src = self.sources.existing(key) else { return nil }
            var tex: MTLTexture?
            if let gen = src as? GeneratedSource {
                let t = self.metal.pool.acquire(width: W, height: H, format: self.metal.workingFormat)
                gen.encode(into: t, time: ctx.time, metal: self.metal, cb: ctx.commandBuffer)
                tex = t
            } else if let f = src.currentFrame() {
                tex = self.fitFrame(f, spec: src.spec, fit: .fill, crop: [0, 0, 0, 0], mirror: false, ctx: ctx, time: ctx.time)?.0
            }
            if let tex { resolved[key] = tex }
            return tex
        }

        for layer in config.layers where layer.enabled {
            let runner = layerRunners[layer.id] ?? EffectStackRunner()
            layerRunners[layer.id] = runner
            guard let src = sources.existing(layer.source.key) else { continue }
            newStatus.layerStates[layer.id] = src.state

            var content: MTLTexture?
            var scale = SIMD2<Float>(1, 1), offset = SIMD2<Float>(0, 0)
            if let gen = src as? GeneratedSource {
                let t = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
                gen.encode(into: t, time: ctx.time, metal: metal, cb: ctx.commandBuffer)
                content = t
            } else if let f = src.currentFrame(), let r = fitFrame(f, spec: layer.source, fit: layer.fit, crop: layer.crop, mirror: layer.mirror, ctx: ctx, time: ctx.time) {
                content = r.0; scale = r.1; offset = r.2
            }
            guard let content else { continue }

            // Face / mask analysis in this layer's space.
            let needs = runner.needs(layer.effects, registry: registry)
            let isBase = canvas == nil
            let wantFace = needs.face || (isBase && masterNeeds.face)
            let wantMask = needs.mask || (isBase && masterNeeds.mask)
            var layerFace = FaceInfo()
            var layerMask: MTLTexture?
            if wantFace || wantMask, let analyzer = sources.analyzer(for: layer.source.key) {
                analyzer.update(wantFace: wantFace, wantMask: wantMask, now: ctx.time)
                if wantFace {
                    // source uv → canvas uv: inverse of srcUV = uv*scale + offset
                    layerFace = analyzer.face.mapped(scale: 1 / scale, offset: -offset / scale, mirror: layer.mirror)
                    newStatus.faceCount = max(newStatus.faceCount, layerFace.count)
                }
                if wantMask, let m = analyzer.mask {
                    layerMask = fitMask(m, scale: scale, offset: offset, mirror: layer.mirror, ctx: ctx)
                }
            }
            ctx.face = layerFace
            ctx.mask = layerMask
            let out = runner.run(input: content, inputPooled: true, effects: layer.effects, registry: registry, ctx: ctx)
            for (k, v) in runner.errors { newStatus.effectErrors[k] = v }

            let simple = layer.isFullFrame && layer.opacity >= 0.999 && layer.blend == .normal
            if canvas == nil && simple {
                // The base layer covers the canvas: use it directly.
                if out.pooled {
                    canvas = out.texture
                } else {
                    let c = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
                    metal.encodeInternal("twz_copy", cb: ctx.commandBuffer, target: c, textures: [out.texture])
                    canvas = c
                }
                canvasFace = layerFace
                canvasMask = layerMask
                layerMask = nil
            } else {
                let base = canvas ?? {
                    let c = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
                    metal.encodeInternal("twz_pattern", cb: ctx.commandBuffer, target: c, textures: [], uniforms: [SIMD4(0, 0, 0, 0), SIMD4(0, 0, 0, 1)])
                    return c
                }()
                let next = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
                metal.encodeInternal("twz_composite", cb: ctx.commandBuffer, target: next, textures: [base, out.texture], uniforms: placementUniforms(layer))
                metal.pool.release(base)
                if out.pooled { metal.pool.release(out.texture) }
                canvas = next
                if canvasFace == nil || (canvasFace!.count == 0 && layerFace.count > 0) {
                    // Map the face through the layer placement (ignoring rotation).
                    let s = Float(layer.scale)
                    canvasFace = layerFace.mapped(scale: SIMD2(s, s), offset: SIMD2(Float(layer.x) - s / 2, Float(layer.y) - s / 2))
                }
                if canvasMask == nil, let lm = layerMask {
                    let black = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
                    metal.encodeInternal("twz_pattern", cb: ctx.commandBuffer, target: black, textures: [], uniforms: [SIMD4(0, 0, 0, 0), SIMD4(0, 0, 0, 1)])
                    let placed = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
                    var u = placementUniforms(layer)
                    u[1].z = 1; u[1].w = 0
                    metal.encodeInternal("twz_composite", cb: ctx.commandBuffer, target: placed, textures: [black, lm], uniforms: u)
                    metal.pool.release(black)
                    canvasMask = placed
                }
            }
            if let lm = layerMask { metal.pool.release(lm) }
        }

        let base: MTLTexture = canvas ?? {
            let c = metal.pool.acquire(width: W, height: H, format: metal.workingFormat)
            metal.encodeInternal("twz_pattern", cb: ctx.commandBuffer, target: c, textures: [], uniforms: [SIMD4(0, 0, 0, 0), SIMD4(0, 0, 0, 1)])
            return c
        }()
        ctx.face = canvasFace ?? FaceInfo()
        ctx.mask = canvasMask
        let out = masterRunner.run(input: base, inputPooled: true, effects: config.effects, registry: registry, ctx: ctx)
        for (k, v) in masterRunner.errors { newStatus.effectErrors[k] = v }
        if let m = canvasMask { metal.pool.release(m) }
        for (_, t) in resolved { metal.pool.release(t) }
        ctx.sourceResolver = nil

        // Forget runners for deleted layers.
        let live = Set(config.layers.map(\.id))
        for id in layerRunners.keys where !live.contains(id) { layerRunners.removeValue(forKey: id) }
        newStatus.renderMS = (CACurrentMediaTimeCompat() - t0) * 1000
        status = newStatus
        return out
    }
}
