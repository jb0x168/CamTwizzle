import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Metal
import TwizzleCore

private func loadScene(_ path: String?) -> SceneConfig {
    if let path, let data = FileManager.default.contents(atPath: path) {
        if let s = try? JSONDecoder().decode(SceneConfig.self, from: data) { return s }
        if let doc = try? JSONDecoder().decode(TwizzleDocument.self, from: data), let s = doc.scenes.first { return s }
        fail("cannot parse scene \(path)")
    }
    var s = SceneConfig(name: "CLI")
    let src = option("--source") ?? "pattern:bars"
    var spec = SourceSpec.parse(key: src) ?? SourceSpec.testPattern
    if spec.kind == .image || spec.kind == .movie { spec.identifier = (spec.identifier as NSString).expandingTildeInPath }
    s.layers = [LayerConfig(source: spec)]
    s.effects = options("-e").map { EffectConfig(effectID: $0) }
    if let size = option("--size"), let x = size.firstIndex(of: "x"), let w = Int(size[..<x]), let h = Int(size[size.index(after: x)...]) {
        s.width = w; s.height = h
    }
    return s
}

private func resolveDevice(_ query: String?) -> VirtualCameraDevice? {
    let sinks = CMIO.sinkDevices()
    guard let q = query?.lowercased() else { return sinks.first(where: \.isCamTwizzle) ?? sinks.first }
    return sinks.first { $0.uid.lowercased() == q || $0.name.lowercased().contains(q) }
}

let registerEngineCommands: Void = {
    extraCommands["devices"] = {
        CMIO.enableAllDevices()
        // Give the HAL a moment to discover extension devices.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let devs = CMIO.devices()
        if devs.isEmpty { print("no CoreMediaIO devices") }
        for d in devs {
            let inUse = CMIO.isRunningSomewhere(d.objectID) ? " [in use]" : ""
            print("\(d.name)  uid=\(d.uid)  model=\(d.model)  sources=\(d.sourceStreams.count) sinks=\(d.sinkStreams.count)\(inUse)")
        }
        print("\ncameras usable as sources:")
        for c in CameraDevices.list(includeVirtual: true) { print("  \(c.name)  \(c.uniqueID)\(c.isVirtual ? "  (virtual — excluded)" : "")") }
    }

    extraCommands["grab"] = {
        // Read a frame from a camera the way a client app (Photo Booth, Zoom) would.
        guard let name = option("--device"), let outPath = option("-o", "--output") else { fail("usage: twizzle grab --device NAME -o out.png [--wait SECONDS]") }
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .video) { ok in granted = ok; sem.signal() }
        sem.wait()
        guard granted else { fail("camera access denied for this terminal (System Settings › Privacy › Camera)") }
        guard let client = CameraClient(deviceNameOrID: name) else { fail("camera '\(name)' not found; try: twizzle devices") }
        var last: CVPixelBuffer?
        let lock = NSLock()
        client.onFrame = { pb in lock.lock(); last = pb; lock.unlock() }
        client.start()
        let wait = Double(option("--wait") ?? "3") ?? 3
        RunLoop.current.run(until: Date().addingTimeInterval(wait))
        client.stop()
        lock.lock(); let pb = last; lock.unlock()
        guard let pb else { fail("no frames received in \(wait)s") }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { fail("conversion failed") }
        try? TextureIO.writePNG(cg, to: URL(fileURLWithPath: outPath))
        print("wrote \(outPath) (\(CVPixelBufferGetWidth(pb))×\(CVPixelBufferGetHeight(pb)), \(client.frames) frames received)")
    }

    extraCommands["import-camtwist"] = {
        let done = DispatchSemaphore(value: 0)
        LegacyImporter.importCamTwist(progress: { print($0) }) { r in
            switch r {
            case let .success(n): print("✓ \(n) CamTwist compositions in \(LegacyImporter.destination.path)")
            case let .failure(e): print("✗ \(e)")
            }
            done.signal()
        }
        done.wait()
    }

    extraCommands["syphon-list"] = {
        #if HAVE_SYPHON
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        for s in SyphonDirectory.servers() { print("\(s.displayName)  uuid=\(s.uuid)") }
        #else
        print("built without Syphon")
        #endif
    }

    extraCommands["scene"] = {
        // Render a single frame of a scene to PNG (offline test of the full pipeline).
        guard let outPath = option("-o", "--output") else { fail("usage: twizzle scene [--scene FILE | --source KEY -e FX...] -o out.png [--frames N]") }
        let engineFilters = filtersDirectory()
        let reg = EffectRegistry(builtIn: engineFilters, user: flag("--no-user") ? [] : [EffectRegistry.defaultUserDirectory])
        let metal = MetalContext.shared
        let sources = SourceManager()
        let resources = ResourceCache(device: metal.device)
        let scene = loadScene(option("--scene"))
        let r = SceneRenderer(config: scene, metal: metal, registry: reg, sources: sources, resources: resources)
        let frames = Int(option("--frames") ?? "5") ?? 5
        var last: MTLTexture?
        for f in 0..<frames {
            // Let sources deliver (image/syphon sources connect asynchronously).
            RunLoop.current.run(until: Date().addingTimeInterval(f == 0 ? 1.5 : 1.0 / 30))
            let cb = metal.queue.makeCommandBuffer()!
            let ctx = FrameContext(metal: metal, commandBuffer: cb, time: Double(f) / 30, deltaTime: 1.0 / 30, frameIndex: f,
                                   canvasSize: SIMD2(scene.width, scene.height), resources: resources)
            let out = r.render(ctx: ctx)
            cb.commit()
            cb.waitUntilCompleted()
            if f == frames - 1 { last = out.texture } else if out.pooled { metal.pool.release(out.texture) }
        }
        for (_, e) in r.status.effectErrors { print("effect error: \(e)") }
        for (_, s) in r.status.layerStates { if let m = s.message { print("source: \(m)") } }
        guard let last, let img = TextureIO.cgImage(from: last, metal: metal) else { fail("no output") }
        try? TextureIO.writePNG(img, to: URL(fileURLWithPath: outPath))
        print("wrote \(outPath)  (faces: \(r.status.faceCount))")
        r.teardown()
    }

    extraCommands["run"] = {
        // Headless engine: render a scene and feed a virtual camera.
        TwzLog.verbose = flag("-v")
        let engine = TwizzleEngine(builtInFilters: filtersDirectory(), userFilters: flag("--no-user") ? [] : [EffectRegistry.defaultUserDirectory])
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        var scene = loadScene(option("--scene"))
        if flag("--syphon") { scene.syphonOutput = true }
        if !flag("--no-output") {
            guard let dev = resolveDevice(option("--device")) else {
                fail("no virtual camera with a sink stream found (install/activate the CamTwizzle or OBS camera extension). Try: twizzle devices")
            }
            scene.outputDeviceUID = dev.uid
            print("output → \(dev.name) (\(dev.uid))")
        }
        engine.setScenes([scene])
        engine.statusHandler = { all in
            for (_, st) in all {
                let line = String(format: "fps %.1f  cpu %.2f ms  gpu %.2f ms  sink %@ sent %d dropped %d%@%@",
                                  st.fps, st.renderMS, st.gpuMS, st.sinkRunning ? "on" : "off", st.framesSent, st.framesDropped,
                                  st.deviceInUse ? "  [client watching]" : "", st.sinkError.map { "  ! \($0)" } ?? "")
                print("\r" + line, terminator: "")
                fflush(stdout)
            }
        }
        engine.start()
        let seconds = Double(option("--seconds") ?? "0") ?? 0
        let end = seconds > 0 ? Date().addingTimeInterval(seconds) : Date.distantFuture
        signal(SIGINT) { _ in print("\nbye"); exit(0) }
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        engine.stop()
        print("")
    }
}()
