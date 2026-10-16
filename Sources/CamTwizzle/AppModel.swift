import AppKit
import AVFoundation
import Combine
import CoreVideo
import Observation
import SwiftUI
import TwizzleCore

/// What the inspector is showing.
enum Selection: Hashable {
    case scene(UUID)
    case layer(UUID)
    case effect(UUID)
}

/// Which stack an "add effect" goes into.
enum StackTarget: Hashable {
    case master
    case layer(UUID)
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let engine: TwizzleEngine
    var document = TwizzleDocument() {
        didSet { documentChanged() }
    }
    var selectedSceneID: UUID?
    var selection: Selection?
    var status: [UUID: EngineSceneStatus] = [:]
    var effects: [EffectDescriptor] = []
    var effectFailures: [(url: URL, message: String)] = []
    var cameras: [CameraDeviceInfo] = []
    var displays: [ScreenInfo] = []
    var windows: [ScreenInfo] = []
    var sinkDevices: [VirtualCameraDevice] = []
    var showBrowser = false
    var browserTarget: StackTarget = .master
    var showSetup = false
    /// A virtual camera exists (a fresh process sees it) but this process can't: relaunch.
    var needsRelaunch = false
    /// OBS's own "Start Virtual Camera" is on and competes for the OBS camera.
    var obsCompeting = false
    var lastPreview: CVPixelBuffer?
    var effectsVersion = 0

    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var healthCheckRunning = false
    @ObservationIgnored let preview = PreviewHost()

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CamTwizzle", isDirectory: true)
    }

    static var setupURL: URL {
        if let p = ProcessInfo.processInfo.environment["CAMTWIZZLE_SETUP"] { return URL(fileURLWithPath: p) }
        return supportDirectory.appendingPathComponent("Setup.json")
    }

    static var builtInFilters: URL? {
        if let env = ProcessInfo.processInfo.environment["TWIZZLE_FILTERS"] { return URL(fileURLWithPath: env) }
        return Bundle.main.resourceURL?.appendingPathComponent("Filters")
    }

    private init() {
        try? FileManager.default.createDirectory(at: EffectRegistry.defaultUserDirectory, withIntermediateDirectories: true)
        engine = TwizzleEngine(builtInFilters: AppModel.builtInFilters, userFilters: [EffectRegistry.defaultUserDirectory] + EffectRegistry.legacyDirectories)
        effects = engine.registry.effects
        effectFailures = engine.registry.failures
        engine.registry.onChange = { [weak self] in
            Task { @MainActor in self?.effectsReloaded() }
        }
        engine.registry.startWatching()
        engine.alwaysRender = UserDefaults.standard.object(forKey: "alwaysRender") as? Bool ?? true
        engine.statusHandler = { [weak self] st in
            Task { @MainActor in self?.status = st }
        }
        load()
        // Camera permission is needed both for webcams and to talk to virtual camera drivers.
        if CameraDevices.authorization == .notDetermined {
            CameraDevices.requestAccess { [weak self] _ in self?.refreshDevices() }
        }
        refreshDevices()
        engine.setScenes(document.scenes)
        engine.start()
        // Cameras can appear while we run (extension approved in System Settings, USB webcam plugged in).
        CMIO.observeDevices { [weak self] in
            MainActor.assumeIsolated { self?.refreshSinks() }
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDevices() }
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSinks()
                self?.checkHealth()
            }
        }
        checkHealth()
        installPreview()
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: AppModel.setupURL), let doc = try? JSONDecoder().decode(TwizzleDocument.self, from: data), !doc.scenes.isEmpty {
            document = doc
        } else {
            document = TwizzleDocument(scenes: [AppModel.defaultScene()])
        }
        selectedSceneID = document.scenes.first?.id
    }

    static func defaultScene(name: String = "CamTwizzle") -> SceneConfig {
        var s = SceneConfig(name: name)
        if let cam = CameraDevices.list().first {
            s.layers = [LayerConfig(source: SourceSpec(kind: .camera, identifier: cam.uniqueID, name: cam.name))]
        } else {
            s.layers = [LayerConfig(source: SourceSpec.testPattern)]
        }
        if let sink = CMIO.sinkDevices().sorted(by: { $0.isCamTwizzle && !$1.isCamTwizzle }).first {
            s.outputDeviceUID = sink.uid
        }
        return s
    }

    private func documentChanged() {
        engine.setScenes(document.scenes)
        saveWork?.cancel()
        let doc = document
        let w = DispatchWorkItem {
            do {
                try FileManager.default.createDirectory(at: AppModel.supportDirectory, withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(doc).write(to: AppModel.setupURL, options: .atomic)
            } catch {
                NSLog("save failed: \(error)")
            }
        }
        saveWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func exportSetup(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(document).write(to: url)
    }

    func importSetup(from url: URL) throws {
        let doc = try JSONDecoder().decode(TwizzleDocument.self, from: Data(contentsOf: url))
        document = doc
        selectedSceneID = doc.scenes.first?.id
        selection = nil
    }

    // MARK: Devices

    func refreshDevices() {
        cameras = CameraDevices.list()
        refreshSinks()
        Task {
            let d = await ScreenDevices.displays()
            let w = ScreenDevices.hasPermission ? await ScreenDevices.windows() : []
            await MainActor.run {
                self.displays = d
                self.windows = w
            }
        }
    }

    func refreshSinks() {
        let s = CMIO.sinkDevices()
        if s.map(\.uid) != sinkDevices.map(\.uid) { sinkDevices = s }
        // Newly appeared virtual camera and a scene without output? Hook it up.
        if let first = s.sorted(by: { $0.isCamTwizzle && !$1.isCamTwizzle }).first {
            for i in document.scenes.indices where document.scenes[i].outputDeviceUID.isEmpty && i == 0 && !UserDefaults.standard.bool(forKey: "outputChosenManually") {
                document.scenes[i].outputDeviceUID = first.uid
            }
        }
    }

    /// Background checks: is OBS fighting over its camera, and does a fresh process see
    /// a virtual camera that this one missed?
    func checkHealth() {
        guard !healthCheckRunning else { return }
        healthCheckRunning = true
        let usesOBS = document.scenes.contains { sc in sinkDevices.contains { $0.uid == sc.outputDeviceUID && $0.isOBS } }
        let missing = sinkDevices.isEmpty
        DispatchQueue.global(qos: .utility).async {
            let obs = usesOBS && CameraHealth.obsVirtualCameraActive()
            let outside = missing ? CameraHealth.sinkCountOutOfProcess() : 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.healthCheckRunning = false
                if self.obsCompeting != obs { self.obsCompeting = obs }
                if missing && outside > 0 { self.refreshSinks() }
                let relaunch = outside > 0 && self.sinkDevices.isEmpty
                if self.needsRelaunch != relaunch { self.needsRelaunch = relaunch }
            }
        }
    }

    private func effectsReloaded() {
        effects = engine.registry.effects
        effectFailures = engine.registry.failures
        effectsVersion += 1
    }

    func reloadEffects() {
        engine.registry.reload()
        effectsReloaded()
    }

    // MARK: Preview

    private func installPreview() {
        guard let id = selectedSceneID else { return }
        let host = preview
        engine.setPreviewHandler(scene: id) { [weak self] pb in
            host.display(pb)
            MainActor.assumeIsolated { self?.lastPreview = pb }
        }
    }

    func selectScene(_ id: UUID?) {
        if let old = selectedSceneID { engine.setPreviewHandler(scene: old, nil) }
        selectedSceneID = id
        selection = id.map { .scene($0) }
        installPreview()
    }

    // MARK: Lookup helpers

    var scene: SceneConfig? {
        guard let id = selectedSceneID else { return nil }
        return document.scenes.first { $0.id == id }
    }

    var sceneIndex: Int? {
        guard let id = selectedSceneID else { return nil }
        return document.scenes.firstIndex { $0.id == id }
    }

    func descriptor(_ id: String) -> EffectDescriptor? { engine.registry.effect(id: id) }

    /// Locate an effect within the selected scene: (layer index or nil for master, effect index).
    func locateEffect(_ id: UUID) -> (layer: Int?, index: Int)? {
        guard let s = scene else { return nil }
        if let i = s.effects.firstIndex(where: { $0.id == id }) { return (nil, i) }
        for (li, l) in s.layers.enumerated() {
            if let i = l.effects.firstIndex(where: { $0.id == id }) { return (li, i) }
        }
        return nil
    }

    func effectConfig(_ id: UUID) -> EffectConfig? {
        guard let s = scene, let loc = locateEffect(id) else { return nil }
        return loc.layer.map { s.layers[$0].effects[loc.index] } ?? s.effects[loc.index]
    }

    func mutateEffect(_ id: UUID, _ f: (inout EffectConfig) -> Void) {
        guard let si = sceneIndex, let loc = locateEffect(id) else { return }
        if let li = loc.layer { f(&document.scenes[si].layers[li].effects[loc.index]) } else { f(&document.scenes[si].effects[loc.index]) }
    }

    func mutateLayer(_ id: UUID, _ f: (inout LayerConfig) -> Void) {
        guard let si = sceneIndex, let li = document.scenes[si].layers.firstIndex(where: { $0.id == id }) else { return }
        f(&document.scenes[si].layers[li])
    }

    func mutateScene(_ f: (inout SceneConfig) -> Void) {
        guard let si = sceneIndex else { return }
        f(&document.scenes[si])
    }

    func paramBinding(effect: UUID, param: ParamDescriptor) -> Binding<ParamValue> {
        Binding(
            get: { [weak self] in self?.effectConfig(effect)?.params[param.name] ?? param.defaultValue },
            set: { [weak self] v in self?.mutateEffect(effect) { $0.params[param.name] = v } }
        )
    }

    func layerBinding<T>(_ id: UUID, _ kp: WritableKeyPath<LayerConfig, T>, default d: T) -> Binding<T> {
        Binding(
            get: { [weak self] in self?.scene?.layers.first { $0.id == id }?[keyPath: kp] ?? d },
            set: { [weak self] v in self?.mutateLayer(id) { $0[keyPath: kp] = v } }
        )
    }

    func sceneBinding<T>(_ kp: WritableKeyPath<SceneConfig, T>, default d: T) -> Binding<T> {
        Binding(
            get: { [weak self] in self?.scene?[keyPath: kp] ?? d },
            set: { [weak self] v in self?.mutateScene { $0[keyPath: kp] = v } }
        )
    }

    // MARK: Scene operations

    func addScene() {
        var s = AppModel.defaultScene(name: "Camera \(document.scenes.count + 1)")
        s.outputDeviceUID = ""
        document.scenes.append(s)
        selectScene(s.id)
    }

    func duplicateScene(_ id: UUID) {
        guard var s = document.scenes.first(where: { $0.id == id }) else { return }
        s.id = UUID()
        s.name += " copy"
        s.outputDeviceUID = ""
        s.layers = s.layers.map { var l = $0; l.id = UUID(); l.effects = l.effects.map { var e = $0; e.id = UUID(); return e }; return l }
        s.effects = s.effects.map { var e = $0; e.id = UUID(); return e }
        document.scenes.append(s)
        selectScene(s.id)
    }

    func removeScene(_ id: UUID) {
        document.scenes.removeAll { $0.id == id }
        if document.scenes.isEmpty { document.scenes = [AppModel.defaultScene()] }
        if selectedSceneID == id { selectScene(document.scenes.first?.id) }
    }

    // MARK: Layer operations

    func addLayer(_ spec: SourceSpec) {
        var l = LayerConfig(source: spec)
        if let s = scene, !s.layers.isEmpty {
            // Additional sources start as a picture-in-picture in the lower right.
            l.scale = 0.3; l.x = 0.8; l.y = 0.78
        }
        mutateScene { $0.layers.append(l) }
        selection = .layer(l.id)
        if spec.kind == .screen || spec.kind == .window, !ScreenDevices.hasPermission { ScreenDevices.requestPermission() }
    }

    func replaceSource(_ layer: UUID, with spec: SourceSpec) {
        mutateLayer(layer) { $0.source = spec }
    }

    func removeLayer(_ id: UUID) {
        mutateScene { $0.layers.removeAll { $0.id == id } }
        if selection == .layer(id) { selection = selectedSceneID.map { .scene($0) } }
    }

    func moveLayers(from: IndexSet, to: Int) {
        mutateScene { $0.layers.move(fromOffsets: from, toOffset: to) }
    }

    // MARK: Effect operations

    func addEffect(_ d: EffectDescriptor, to target: StackTarget) {
        let e = EffectConfig(effectID: d.id, params: d.defaultParams())
        switch target {
        case .master: mutateScene { $0.effects.append(e) }
        case let .layer(id): mutateLayer(id) { $0.effects.append(e) }
        }
        selection = .effect(e.id)
    }

    func removeEffect(_ id: UUID) {
        guard let loc = locateEffect(id) else { return }
        if let li = loc.layer {
            mutateScene { $0.layers[li].effects.remove(at: loc.index) }
        } else {
            mutateScene { $0.effects.remove(at: loc.index) }
        }
        if selection == .effect(id) { selection = selectedSceneID.map { .scene($0) } }
    }

    func duplicateEffect(_ id: UUID) {
        guard let loc = locateEffect(id), var e = effectConfig(id) else { return }
        e.id = UUID()
        if let li = loc.layer { mutateScene { $0.layers[li].effects.insert(e, at: loc.index + 1) } } else {
            mutateScene { $0.effects.insert(e, at: loc.index + 1) }
        }
        selection = .effect(e.id)
    }

    func moveEffects(in target: StackTarget, from: IndexSet, to: Int) {
        switch target {
        case .master: mutateScene { $0.effects.move(fromOffsets: from, toOffset: to) }
        case let .layer(id): mutateLayer(id) { $0.effects.move(fromOffsets: from, toOffset: to) }
        }
    }

    func resetEffectParams(_ id: UUID) {
        guard let cfg = effectConfig(id), let d = descriptor(cfg.effectID) else { return }
        mutateEffect(id) { $0.params = d.defaultParams() }
        if let s = selectedSceneID { engine.resetEffect(scene: s, effect: id) }
    }

    func restartEffect(_ id: UUID) {
        if let s = selectedSceneID { engine.resetEffect(scene: s, effect: id) }
    }

    /// Copy a built-in effect into the user folder (overriding it) and open it for editing.
    func editEffectSource(_ d: EffectDescriptor) {
        var url = d.url
        if d.isBuiltIn {
            let dest = EffectRegistry.defaultUserDirectory.appendingPathComponent(d.url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: d.url, to: dest)
            }
            url = dest
            reloadEffects()
        }
        NSWorkspace.shared.open(url)
    }

    func newEffectFromTemplate() {
        let dir = EffectRegistry.defaultUserDirectory
        var n = 1
        var url = dir.appendingPathComponent("MyEffect.metal")
        while FileManager.default.fileExists(atPath: url.path) { n += 1; url = dir.appendingPathComponent("MyEffect\(n).metal") }
        let name = url.deletingPathExtension().lastPathComponent
        let template = """
        /*{
          "NAME": "\(name)",
          "CATEGORIES": ["My Effects"],
          "DESCRIPTION": "A new CamTwizzle effect. Edit me — changes reload live.",
          "INPUTS": [
            { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
            { "NAME": "tint", "LABEL": "Tint", "TYPE": "color", "DEFAULT": [1, 0.4, 0.8, 1] }
          ]
        }*/

        float4 effect(Twz t) {
            float4 c = t.sample(t.uv);
            // wobble the image a little over time
            float2 uv = t.uv + 0.01 * t.p.amount * float2(sin(t.uv.y * 30.0 + t.time * 3.0), 0.0);
            c = t.sample(uv);
            return float4(mix(c.rgb, c.rgb * t.p.tint.rgb, t.p.amount), 1.0);
        }
        """
        try? template.write(to: url, atomically: true, encoding: .utf8)
        reloadEffects()
        NSWorkspace.shared.open(url)
    }

    var importStatus: String?

    /// Download CamTwist and copy its original Quartz Composer effects into My Effects.
    func importCamTwist() {
        let alert = NSAlert()
        alert.messageText = "Import CamTwist's original effects?"
        alert.informativeText = "CamTwizzle will download CamTwist 3.4.3 from camtwiststudio.com and copy its Quartz Composer effects into “My Effects/CamTwist Classics”. They run through the legacy Quartz Composer engine (some may not work on modern macOS); native ports of all of them are already built in."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        importStatus = "Downloading CamTwist…"
        LegacyImporter.importCamTwist(progress: { msg in
            Task { @MainActor in self.importStatus = msg }
        }) { result in
            Task { @MainActor in
                switch result {
                case let .success(n):
                    self.importStatus = nil
                    self.reloadEffects()
                    let done = NSAlert()
                    done.messageText = "Imported \(n) CamTwist effects"
                    done.informativeText = "Find them in the effect browser under “Quartz Composer”."
                    done.runModal()
                case let .failure(e):
                    self.importStatus = nil
                    NSAlert(error: e).runModal()
                }
            }
        }
    }

    func openEffectsFolder() {
        NSWorkspace.shared.open(EffectRegistry.defaultUserDirectory)
    }

    // MARK: Status helpers

    var sceneStatus: EngineSceneStatus? {
        guard let id = selectedSceneID else { return nil }
        return status[id]
    }

    func error(for effect: UUID) -> String? {
        sceneStatus?.effectErrors[effect]
    }

    /// All currently configured sources (for `source` parameters).
    var availableSources: [SourceSpec] {
        var out: [SourceSpec] = cameras.map { SourceSpec(kind: .camera, identifier: $0.uniqueID, name: $0.name) }
        out += displays.map { SourceSpec(kind: .screen, identifier: $0.id, name: $0.name) }
        out += PatternSource.patterns.map { SourceSpec(kind: .pattern, identifier: $0.id, name: $0.name) }
        for s in document.scenes { for l in s.layers where !out.contains(where: { $0.key == l.source.key }) { out.append(l.source) } }
        return out
    }
}

/// Displays engine frames in a CALayer (IOSurface contents; no copies).
final class PreviewHost {
    let layer: CALayer = {
        let l = CALayer()
        l.contentsGravity = .resizeAspect
        l.backgroundColor = NSColor.black.cgColor
        l.actions = ["contents": NSNull()]
        return l
    }()
    private var recent: [CVPixelBuffer] = []

    func display(_ pb: CVPixelBuffer) {
        recent.append(pb)
        if recent.count > 3 { recent.removeFirst() }
        if let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = surface
            CATransaction.commit()
        }
    }
}
