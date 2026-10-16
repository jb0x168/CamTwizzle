import Foundation
import Metal

/// Runs an ordered list of effects, each consuming the previous one's output.
/// Keeps one runtime per EffectConfig.id so stateful effects (trails, feedback,
/// timers) survive parameter edits and reordering.
public final class EffectStackRunner {
    private var runtimes: [UUID: EffectRuntime] = [:]
    public private(set) var errors: [UUID: String] = [:]
    /// GPU-side timing isn't available per effect; track CPU encode time for diagnostics.
    public private(set) var encodeTimes: [UUID: Double] = [:]

    public init() {}

    public var wantsFace: Bool { runtimes.values.contains { $0.descriptor.wantsFace } }
    public var wantsMask: Bool { runtimes.values.contains { $0.descriptor.wantsMask } }

    public func needs(_ effects: [EffectConfig], registry: EffectRegistry) -> (face: Bool, mask: Bool) {
        var face = false, mask = false
        for e in effects where e.enabled {
            if let d = registry.effect(id: e.effectID) {
                face = face || d.wantsFace
                mask = mask || d.wantsMask
            }
        }
        return (face, mask)
    }

    public func reset(_ id: UUID) { runtimes[id]?.reset() }
    public func resetAll() { runtimes.values.forEach { $0.reset() } }

    /// Encode the stack. `input` ownership: if `inputPooled`, the runner releases it once consumed.
    public func run(input: MTLTexture, inputPooled: Bool, effects: [EffectConfig], registry: EffectRegistry,
                    ctx: FrameContext) -> EffectOutput {
        var current = EffectOutput(texture: input, pooled: inputPooled)
        var live = Set<UUID>()
        for e in effects {
            live.insert(e.id)
            guard e.enabled else { continue }
            guard let d = registry.effect(id: e.effectID) else {
                errors[e.id] = "Effect '\(e.effectID)' not found"
                continue
            }
            var rt = runtimes[e.id]
            if rt == nil || rt!.descriptor !== d {
                do {
                    rt = try d.makeRuntime(metal: ctx.metal)
                    runtimes[e.id] = rt
                    errors[e.id] = nil
                } catch {
                    errors[e.id] = "\(error)"
                    runtimes[e.id] = nil
                    continue
                }
            }
            let t0 = CACurrentMediaTimeCompat()
            do {
                let out = try rt!.render(input: current.texture, params: e.params, ctx: ctx)
                if current.pooled && out.texture !== current.texture { ctx.metal.pool.release(current.texture) }
                current = out
                errors[e.id] = nil
            } catch {
                errors[e.id] = "\(error)"
            }
            encodeTimes[e.id] = CACurrentMediaTimeCompat() - t0
        }
        // Drop runtimes for effects that were removed.
        for id in runtimes.keys where !live.contains(id) { runtimes.removeValue(forKey: id) }
        for id in errors.keys where !live.contains(id) { errors.removeValue(forKey: id) }
        return current
    }
}

@inline(__always) func CACurrentMediaTimeCompat() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1e9
}
