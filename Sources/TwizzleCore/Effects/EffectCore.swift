import Foundation
import Metal

/// Face tracking results in normalized, top-left-origin coordinates of the
/// image an effect is processing.
public struct FaceInfo: Equatable {
    public var count: Int = 0
    public var rect = SIMD4<Float>(0.35, 0.25, 0.3, 0.4) // x, y, w, h
    public var leftEye = SIMD2<Float>(0.43, 0.38)
    public var rightEye = SIMD2<Float>(0.57, 0.38)
    public var mouth = SIMD2<Float>(0.5, 0.56)
    public var nose = SIMD2<Float>(0.5, 0.47)
    public var roll: Float = 0
    public var yaw: Float = 0
    public var confidence: Float = 0

    public init() {}

    public var center: SIMD2<Float> { SIMD2(rect.x + rect.z / 2, rect.y + rect.w / 2) }

    /// Map through an affine transform of normalized coordinates: p' = p * scale + offset.
    public func mapped(scale: SIMD2<Float>, offset: SIMD2<Float>, mirror: Bool = false) -> FaceInfo {
        var f = self
        func m(_ p: SIMD2<Float>) -> SIMD2<Float> {
            var q = p * scale + offset
            if mirror { q.x = 1 - q.x }
            return q
        }
        let o = m(SIMD2(rect.x, rect.y))
        let o2 = m(SIMD2(rect.x + rect.z, rect.y + rect.w))
        f.rect = SIMD4(min(o.x, o2.x), min(o.y, o2.y), abs(o2.x - o.x), abs(o2.y - o.y))
        f.leftEye = m(leftEye)
        f.rightEye = m(rightEye)
        f.mouth = m(mouth)
        f.nose = m(nose)
        if mirror {
            swap(&f.leftEye, &f.rightEye)
            f.roll = -roll
            f.yaw = -yaw
        }
        return f
    }
}

/// Everything an effect needs to render one frame.
public final class FrameContext {
    public let metal: MetalContext
    public let commandBuffer: MTLCommandBuffer
    public let time: Double
    public let deltaTime: Double
    public let frameIndex: Int
    public let canvasSize: SIMD2<Int>
    public var face = FaceInfo()
    /// Person-segmentation mask in the same space as the effect's input (r channel), if available.
    public var mask: MTLTexture?
    public let resources: ResourceCache
    /// Resolves a source key (for `source` params) to its latest frame, fitted to the canvas.
    public var sourceResolver: ((String) -> MTLTexture?)?
    /// Objects kept alive until the command buffer completes.
    private(set) var retained: [Any] = []

    public init(metal: MetalContext, commandBuffer: MTLCommandBuffer, time: Double, deltaTime: Double,
                frameIndex: Int, canvasSize: SIMD2<Int>, resources: ResourceCache) {
        self.metal = metal
        self.commandBuffer = commandBuffer
        self.time = time
        self.deltaTime = deltaTime
        self.frameIndex = frameIndex
        self.canvasSize = canvasSize
        self.resources = resources
    }

    public func retain(_ obj: Any) { retained.append(obj) }
}

/// Result of an effect: a texture plus whether it came from the shared pool
/// (and should be released by whoever consumes it) or is owned by the effect.
public struct EffectOutput {
    public let texture: MTLTexture
    public let pooled: Bool
    public init(texture: MTLTexture, pooled: Bool) {
        self.texture = texture
        self.pooled = pooled
    }
}

/// A live instance of an effect with its own state (feedback buffers, timers...).
public protocol EffectRuntime: AnyObject {
    var descriptor: EffectDescriptor { get }
    func render(input: MTLTexture, params: [String: ParamValue], ctx: FrameContext) throws -> EffectOutput
    func reset()
}

/// Static description of an effect plugin.
public final class EffectDescriptor: Identifiable, Hashable {
    public enum Kind: String { case shader, graph, quartz }

    public let id: String
    private let baseName: String
    /// Added to the name when another effect has the same name (e.g. " (ISF)").
    public internal(set) var displaySuffix = ""
    public var name: String { baseName + displaySuffix }
    public let categories: [String]
    public let summary: String
    public let credit: String?
    public let kind: Kind
    public let url: URL
    public let params: [ParamDescriptor]
    public let wantsFace: Bool
    public let wantsMask: Bool
    public internal(set) var isBuiltIn: Bool
    /// Program shared by all instances (compiled shader / parsed graph).
    let program: EffectProgram

    init(id: String, name: String, categories: [String], summary: String, credit: String?, kind: Kind, url: URL,
         params: [ParamDescriptor], wantsFace: Bool, wantsMask: Bool, isBuiltIn: Bool, program: EffectProgram) {
        self.id = id
        self.baseName = name
        self.categories = categories.isEmpty ? ["Other"] : categories
        self.summary = summary
        self.credit = credit
        self.kind = kind
        self.url = url
        self.params = params
        self.wantsFace = wantsFace
        self.wantsMask = wantsMask
        self.isBuiltIn = isBuiltIn
        self.program = program
    }

    public static func == (a: EffectDescriptor, b: EffectDescriptor) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    public var primaryCategory: String { categories.first ?? "Other" }

    public func defaultParams() -> [String: ParamValue] {
        Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0.defaultValue) })
    }

    /// Fill in defaults and sanitize user values.
    public func resolve(_ values: [String: ParamValue]) -> [String: ParamValue] {
        var out: [String: ParamValue] = [:]
        for p in params { out[p.name] = p.sanitize(values[p.name]) }
        return out
    }

    public func makeRuntime(metal: MetalContext) throws -> EffectRuntime {
        try program.makeRuntime(descriptor: self, metal: metal)
    }

    /// Compile (if needed) and report problems without instantiating.
    public func validate(metal: MetalContext) -> String? {
        do { try program.prepare(metal: metal); return nil } catch { return "\(error)" }
    }
}

protocol EffectProgram: AnyObject {
    func prepare(metal: MetalContext) throws
    func makeRuntime(descriptor: EffectDescriptor, metal: MetalContext) throws -> EffectRuntime
}
