import CoreMedia
import CoreVideo
import Foundation
import Metal

/// Live status for one scene (published on the main thread).
public struct EngineSceneStatus {
    public var fps = 0.0
    public var renderMS = 0.0
    public var gpuMS = 0.0
    public var sinkName: String?
    public var sinkRunning = false
    public var sinkError: String?
    public var framesSent = 0
    public var framesDropped = 0
    /// The virtual camera isn't taking our frames (another app is feeding it).
    public var sinkStalled = false
    public var deviceInUse = false
    public var effectErrors: [UUID: String] = [:]
    public var layerStates: [UUID: SourceState] = [:]
    public var faceCount = 0
}

/// Owns the render loop: renders every enabled scene at its frame rate, then
/// fans the result out to the preview and the virtual camera sink.
public final class TwizzleEngine {
    public let metal: MetalContext
    public let registry: EffectRegistry
    public let sources = SourceManager()
    public let resources: ResourceCache

    private let renderQueue = DispatchQueue(label: "dev.camtwizzle.render", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var scenes: [SceneConfig] = []
    private var renderers: [UUID: SceneRenderer] = [:]
    private var outputs: [UUID: SceneOutputState] = [:]
    private var previewHandlers: [UUID: (CVPixelBuffer) -> Void] = [:]
    private var inFlight = 0
    private let inFlightLock = NSLock()
    private let startTime = CACurrentMediaTimeCompat()
    private var frameIndex = 0
    private var lastStatusPublish = 0.0
    /// Render even when nothing is watching (preview hidden and no client on the camera).
    public var alwaysRender = true
    public var statusHandler: (([UUID: EngineSceneStatus]) -> Void)?

    final class SceneOutputState {
        var pool: CVPixelBufferPool?
        var poolSize = (0, 0)
        var sink: CMIOSinkOutput?
        var sinkUID = ""
        var lastSinkAttempt = 0.0
        var lastSinkRestart = 0.0
        var sinkRestartDelay = 2.0
        var lastRender = 0.0
        var frameTimes: [Double] = []
        var deviceInUse = false
        var lastInUseCheck = 0.0
        var gpuMS = 0.0
        #if HAVE_SYPHON
        var syphon: SyphonOutput?
        var syphonName = ""
        #endif
    }

    public init(builtInFilters: URL?, userFilters: [URL]) {
        metal = MetalContext.shared
        resources = ResourceCache(device: metal.device)
        registry = EffectRegistry(builtIn: builtInFilters, user: userFilters)
        CMIO.enableAllDevices()
    }

    // MARK: Configuration (call from main thread)

    public func setScenes(_ s: [SceneConfig]) {
        renderQueue.async { self.applyScenes(s) }
    }

    public func setPreviewHandler(scene: UUID, _ handler: ((CVPixelBuffer) -> Void)?) {
        renderQueue.async { self.previewHandlers[scene] = handler }
    }

    public func resetEffect(scene: UUID, effect: UUID) {
        renderQueue.async { self.renderers[scene]?.resetEffect(effect) }
    }

    private func applyScenes(_ s: [SceneConfig]) {
        scenes = s
        let live = Set(s.map(\.id))
        for (id, r) in renderers where !live.contains(id) || !(s.first { $0.id == id }?.enabled ?? false) {
            r.teardown()
            renderers.removeValue(forKey: id)
            outputs[id]?.sink?.stop()
            #if HAVE_SYPHON
            outputs[id]?.syphon?.stop()
            #endif
            outputs.removeValue(forKey: id)
        }
        for c in s where c.enabled {
            if let r = renderers[c.id] { r.update(c) } else {
                renderers[c.id] = SceneRenderer(config: c, metal: metal, registry: registry, sources: sources, resources: resources)
            }
        }
    }

    // MARK: Loop

    public func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: renderQueue)
        t.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        renderQueue.sync {
            for (_, o) in outputs { o.sink?.stop() }
            for (_, r) in renderers { r.teardown() }
            renderers.removeAll()
            outputs.removeAll()
        }
    }

    private func tick() {
        let now = CACurrentMediaTimeCompat() - startTime
        for scene in scenes where scene.enabled {
            guard let r = renderers[scene.id] else { continue }
            let out = outputs[scene.id] ?? SceneOutputState()
            outputs[scene.id] = out
            let interval = 1.0 / Double(max(1, min(60, scene.fps)))
            if now - out.lastRender < interval - 0.002 { continue }
            manageSink(scene, out, now: now)
            let watching = previewHandlers[scene.id] != nil || (out.sink?.isRunning ?? false)
            if !watching && !alwaysRender { continue }
            inFlightLock.lock()
            let busy = inFlight >= 3
            if !busy { inFlight += 1 }
            inFlightLock.unlock()
            if busy { continue }
            let dt = out.lastRender == 0 ? interval : now - out.lastRender
            out.lastRender = now
            out.frameTimes.append(now)
            if out.frameTimes.count > 30 { out.frameTimes.removeFirst(out.frameTimes.count - 30) }
            renderScene(scene, renderer: r, out: out, time: now, dt: dt)
        }
        if now - lastStatusPublish > 0.25 {
            lastStatusPublish = now
            publishStatus()
        }
    }

    private func manageSink(_ scene: SceneConfig, _ out: SceneOutputState, now: Double) {
        if out.sinkUID != scene.outputDeviceUID {
            out.sink?.stop()
            out.sink = nil
            out.sinkUID = scene.outputDeviceUID
            out.lastSinkAttempt = 0
        }
        guard !scene.outputDeviceUID.isEmpty else { return }
        if out.sink == nil && now - out.lastSinkAttempt > 2 {
            out.lastSinkAttempt = now
            if let s = CMIOSinkOutput(deviceUID: scene.outputDeviceUID) {
                out.sink = s
                if !s.start() { out.sink = nil }
            }
        }
        if let s = out.sink, s.isStalled, now - out.lastSinkRestart > out.sinkRestartDelay {
            // Back off if someone else keeps the device (2 s, 4 s … 30 s).
            out.lastSinkRestart = now
            out.sinkRestartDelay = min(30, out.sinkRestartDelay * 2)
            s.restart()
        } else if let s = out.sink, !s.isStalled, now - out.lastSinkRestart > 10 {
            out.sinkRestartDelay = 2
        }
        if let s = out.sink, now - out.lastInUseCheck > 1 {
            out.lastInUseCheck = now
            out.deviceInUse = CMIO.isInUse(s.device)
        }
    }

    private func renderScene(_ scene: SceneConfig, renderer: SceneRenderer, out: SceneOutputState, time: Double, dt: Double) {
        guard let cb = metal.queue.makeCommandBuffer() else { return }
        cb.label = scene.name
        frameIndex += 1
        let ctx = FrameContext(metal: metal, commandBuffer: cb, time: time, deltaTime: dt, frameIndex: frameIndex,
                               canvasSize: SIMD2(scene.width, scene.height), resources: resources)
        let result = renderer.render(ctx: ctx)

        // Copy into an IOSurface-backed BGRA pixel buffer (opaque) for the outputs.
        var pb: CVPixelBuffer?
        // OBS's extension only advertises 1920×1080, so match it (our own extension rescales itself).
        let outSize = out.sink?.device.isOBS == true ? (1920, 1080) : (scene.width, scene.height)
        if out.pool == nil || out.poolSize != outSize {
            out.pool = SceneOutputState.makePool(width: outSize.0, height: outSize.1)
            out.poolSize = outSize
        }
        if let pool = out.pool { CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) }
        if let pb, let (tex, cvt) = metal.texture(from: pb) {
            metal.encodeInternal("twz_copy", cb: cb, target: tex, textures: [result.texture], uniforms: [SIMD4(1, 0, 0, 0)], label: "output")
            ctx.retain(cvt)
        }
        #if HAVE_SYPHON
        if scene.syphonOutput {
            let name = "\(scene.name)"
            if out.syphon == nil || out.syphonName != name {
                out.syphon?.stop()
                out.syphon = SyphonOutput(name: name, device: metal.device)
                out.syphonName = name
            }
            out.syphon?.publish(result.texture, cb: cb)
        } else if out.syphon != nil {
            out.syphon?.stop()
            out.syphon = nil
        }
        #endif
        if result.pooled { metal.pool.release(result.texture) }

        let retained = ctx
        let sink = out.sink
        let preview = previewHandlers[scene.id]
        cb.addCompletedHandler { [weak self] cb in
            _ = retained
            let gpu = (cb.gpuEndTime - cb.gpuStartTime) * 1000
            if gpu > 0 { out.gpuMS = out.gpuMS * 0.9 + gpu * 0.1 }
            if let pb {
                let host = CMClockGetTime(CMClockGetHostTimeClock())
                sink?.send(pb, hostTime: host)
                if let preview { DispatchQueue.main.async { preview(pb) } }
            }
            guard let self else { return }
            self.inFlightLock.lock(); self.inFlight -= 1; self.inFlightLock.unlock()
        }
        cb.commit()
    }

    private func publishStatus() {
        var all: [UUID: EngineSceneStatus] = [:]
        for scene in scenes {
            var st = EngineSceneStatus()
            if let r = renderers[scene.id] {
                st.renderMS = r.status.renderMS
                st.effectErrors = r.status.effectErrors
                st.layerStates = r.status.layerStates
                st.faceCount = r.status.faceCount
            }
            if let o = outputs[scene.id] {
                if o.frameTimes.count > 1, let first = o.frameTimes.first, let last = o.frameTimes.last, last > first {
                    st.fps = Double(o.frameTimes.count - 1) / (last - first)
                }
                st.sinkName = o.sink?.device.name
                st.sinkRunning = o.sink?.isRunning ?? false
                st.sinkError = o.sink?.lastError ?? (scene.outputDeviceUID.isEmpty || o.sink != nil ? nil : "Virtual camera not available")
                st.framesSent = o.sink?.framesSent ?? 0
                st.framesDropped = o.sink?.framesDropped ?? 0
                st.sinkStalled = o.sink?.isStalled ?? false
                st.deviceInUse = o.deviceInUse
                st.gpuMS = o.gpuMS
            }
            all[scene.id] = st
        }
        if let h = statusHandler { DispatchQueue.main.async { h(all) } }
    }
}

extension TwizzleEngine.SceneOutputState {
    static func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary, attrs as CFDictionary, &pool)
        return pool
    }
}
