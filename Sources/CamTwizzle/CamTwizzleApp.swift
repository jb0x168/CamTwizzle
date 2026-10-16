import AppKit
import CoreImage
import ServiceManagement
import SwiftUI
import TwizzleCore
import UniformTypeIdentifiers

@main
struct CamTwizzleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("CamTwizzle", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Virtual Camera") { model.addScene() }.keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import Setup…") { importSetup() }.keyboardShortcut("o")
                Button("Export Setup…") { exportSetup() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Effects") {
                Button("Add Effect…") {
                    model.browserTarget = .master
                    model.showBrowser = true
                }.keyboardShortcut("k")
                Divider()
                Button("New Effect from Template") { model.newEffectFromTemplate() }
                Button("Open My Effects Folder") { model.openEffectsFolder() }
                Button("Import CamTwist Classics…") { model.importCamTwist() }
                Button("Reload Effects") { model.reloadEffects() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowArrangement) {
                Button("Virtual Camera Setup…") { model.showSetup = true }
            }
        }

        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image(systemName: "camera.filters")
        }

        Settings {
            SettingsView().environment(model).frame(width: 520)
        }
    }

    private func importSetup() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url {
            do { try model.importSetup(from: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    private func exportSetup() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "CamTwizzle Setup.json"
        if p.runModal() == .OK, let url = p.url {
            do { try model.exportSetup(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DebugSnapshot.scheduleIfRequested()
    }

    /// Keep feeding the virtual camera when the window is closed (lives in the menu bar).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.engine.stop() }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(model.document.scenes) { s in
            let st = model.status[s.id]
            Toggle(isOn: Binding(get: { s.enabled }, set: { v in
                if let i = model.document.scenes.firstIndex(where: { $0.id == s.id }) { model.document.scenes[i].enabled = v }
            })) {
                Text("\(s.name)\(st?.deviceInUse == true ? " — live" : "")")
            }
            // Quick effect toggles for use mid-call.
            if !s.effects.isEmpty {
                Menu("\(s.name) Effects") {
                    ForEach(s.effects) { e in
                        Toggle(e.label ?? model.descriptor(e.effectID)?.name ?? e.effectID, isOn: Binding(
                            get: { e.enabled },
                            set: { v in
                                guard let si = model.document.scenes.firstIndex(where: { $0.id == s.id }),
                                      let ei = model.document.scenes[si].effects.firstIndex(where: { $0.id == e.id }) else { return }
                                model.document.scenes[si].effects[ei].enabled = v
                            }))
                    }
                    Divider()
                    Button("All Off") {
                        if let si = model.document.scenes.firstIndex(where: { $0.id == s.id }) {
                            for i in model.document.scenes[si].effects.indices { model.document.scenes[si].effects[i].enabled = false }
                        }
                    }
                }
            }
        }
        Divider()
        Button("Open CamTwizzle") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("alwaysRender") private var alwaysRender = true

    var body: some View {
        Form {
            Section("Rendering") {
                Toggle("Keep rendering when nothing is watching", isOn: $alwaysRender)
                    .onChange(of: alwaysRender) { _, v in model.engine.alwaysRender = v }
                Text("When off, a virtual camera only renders while the preview is open or another app is using it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch CamTwizzle at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { NSAlert(error: error).runModal() }
                    }))
                Text("CamTwizzle keeps feeding the virtual camera from the menu bar when its window is closed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Effects") {
                LabeledContent("My effects") {
                    Button("Show in Finder") { model.openEffectsFolder() }
                }
                Text(EffectRegistry.defaultUserDirectory.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("\(model.effects.count) effects loaded, \(model.effectFailures.count) failed").font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Debug aid: CAMTWIZZLE_SNAPSHOT=/path.png renders the main window (plus the
/// live preview) into a PNG after CAMTWIZZLE_SNAPSHOT_DELAY seconds, optionally
/// running CAMTWIZZLE_SNAPSHOT_ACTIONS first, then quits if CAMTWIZZLE_SNAPSHOT_EXIT=1.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["CAMTWIZZLE_SNAPSHOT"] else { return }
        let delay = Double(env["CAMTWIZZLE_SNAPSHOT_DELAY"] ?? "3") ?? 3
        if let size = env["CAMTWIZZLE_SNAPSHOT_SIZE"], let x = size.firstIndex(of: "x"), let w = Double(size[..<x]), let h = Double(size[size.index(after: x)...]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    for win in NSApp.windows where win.isVisible && win.styleMask.contains(.titled) {
                        win.setFrame(NSRect(x: 40, y: 40, width: w, height: h), display: true)
                    }
                }
            }
        }
        if let actions = env["CAMTWIZZLE_SNAPSHOT_ACTIONS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 2) { MainActor.assumeIsolated { run(actions) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                if let pb = clientFrame {
                    let ci = CIImage(cvPixelBuffer: pb)
                    if let cg = CIContext().createCGImage(ci, from: ci.extent) {
                        try? TextureIO.writePNG(cg, to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-client.png")))
                    }
                    NSLog("CamTwizzle snapshot: client received \(client?.frames ?? 0) frames")
                }
                for (i, w) in NSApp.windows.enumerated() where w.isVisible && w.contentView != nil {
                    let p = i == 0 ? path : path.replacingOccurrences(of: ".png", with: "-\(i).png")
                    snapshot(w, to: URL(fileURLWithPath: p))
                }
                if env["CAMTWIZZLE_SNAPSHOT_EXIT"] == "1" { AppModel.shared.engine.stop(); exit(0) }
            }
        }
    }

    static var client: CameraClient?
    static var clientFrame: CVPixelBuffer?

    @MainActor static func run(_ actions: String) {
        let m = AppModel.shared
        for a in actions.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let parts = a.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "browser": m.browserTarget = .master; m.showBrowser = true
            case "setup": m.showSetup = true
            case "add": if parts.count > 1, let d = m.descriptor(parts[1]) { m.addEffect(d, to: .master) }
            case "select-effect":
                if let idx = Int(parts.count > 1 ? parts[1] : "0"), let s = m.scene, idx < s.effects.count { m.selection = .effect(s.effects[idx].id) }
            case "select-layer":
                if let idx = Int(parts.count > 1 ? parts[1] : "0"), let s = m.scene, idx < s.layers.count { m.selection = .layer(s.layers[idx].id) }
            case "source":
                if parts.count > 1, let spec = SourceSpec.parse(key: parts[1]), let s = m.scene, let l = s.layers.first { m.replaceSource(l.id, with: spec) }
            case "client":
                // Act like Photo Booth: open a (virtual) camera and keep its latest frame.
                if parts.count > 1, let c = CameraClient(deviceNameOrID: parts[1]) {
                    c.onFrame = { pb in DispatchQueue.main.async { DebugSnapshot.clientFrame = pb } }
                    c.start()
                    client = c
                } else {
                    NSLog("CamTwizzle snapshot: client camera not found")
                }
            case "add-source":
                if parts.count > 1, let spec = SourceSpec.parse(key: parts[1]) { m.addLayer(spec) }
            default: break
            }
        }
    }

    typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// CGWindowListCreateImage is unavailable in the macOS 15 SDK but still exported;
    /// capturing our own windows doesn't need Screen Recording permission.
    @MainActor static func windowImage(_ window: NSWindow) -> CGImage? {
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: WindowImageFn.self)
        // kCGWindowListOptionIncludingWindow = 1 << 3 ; kCGWindowImageBoundsIgnoreFraming = 1 << 0
        return fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue()
    }

    /// Render the window's whole layer tree (works without Screen Recording permission).
    @MainActor static func layerSnapshot(_ window: NSWindow, to url: URL) -> Bool {
        guard let frameView = window.contentView?.superview, let layer = frameView.layer else { return false }
        let scale = window.backingScaleFactor
        let size = frameView.bounds.size
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(NSColor.windowBackgroundColor.usingColorSpace(.sRGB)?.cgColor ?? .white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        if !frameView.isFlipped { } else { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
        layer.render(in: ctx)
        // Glass/visual-effect panels (sidebar, inspector) don't render in software:
        // paint a background and render their hosted SwiftUI content on top.
        func glassHosts(_ v: NSView, inGlass: Bool, into out: inout [NSView]) {
            let name = String(describing: type(of: v))
            let glass = inGlass || name.contains("Glass") || name.contains("VisualEffect") || name.contains("Backdrop")
            if glass && name.hasPrefix("NSHostingView") { out.append(v); return }
            for s in v.subviews where !s.isHidden { glassHosts(s, inGlass: glass && !name.hasPrefix("NSThemeFrame"), into: &out) }
        }
        var hosts: [NSView] = []
        for s in frameView.subviews where !s.isHidden { glassHosts(s, inGlass: false, into: &hosts) }
        for hv in hosts {
            guard let hl = hv.layer else { continue }
            var r = hv.convert(hv.bounds, to: frameView)
            if frameView.isFlipped { r.origin.y = size.height - r.maxY }
            if r.width < 10 || r.height < 10 || r.width >= size.width - 1 { continue }
            ctx.saveGState()
            ctx.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor)
            ctx.fill(r)
            ctx.translateBy(x: r.minX, y: r.minY)
            if !hv.isFlipped { } else { ctx.translateBy(x: 0, y: r.height); ctx.scaleBy(x: 1, y: -1) }
            hl.render(in: ctx)
            ctx.restoreGState()
        }
        // Draw the live preview frame (IOSurface layer contents don't render in software).
        if let pb = AppModel.shared.lastPreview, let pv = findPreview(in: frameView) {
            var r = pv.convert(pv.bounds, to: frameView)
            if frameView.isFlipped { r.origin.y = size.height - r.maxY }
            let ci = CIImage(cvPixelBuffer: pb)
            if let cg = CIContext().createCGImage(ci, from: ci.extent) {
                let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
                let s = min(r.width / iw, r.height / ih)
                let dw = iw * s, dh = ih * s
                let dst = CGRect(x: r.midX - dw / 2, y: r.midY - dh / 2, width: dw, height: dh)
                ctx.saveGState()
                if frameView.isFlipped { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
                ctx.draw(cg, in: dst)
                ctx.restoreGState()
            }
        }
        guard let img = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return false }
        try? data.write(to: url)
        return true
    }

    @MainActor static func dumpTree(_ v: NSView, depth: Int = 0, into out: inout String) {
        guard depth < 18 else { return }
        let f = v.convert(v.bounds, to: nil)
        let cls = String(describing: type(of: v)).prefix(60)
        out += String(repeating: "  ", count: depth) + "\(cls) [\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))]\(v.isHidden ? " hidden" : "")\(v.alphaValue < 1 ? " a=\(v.alphaValue)" : "")\n"
        for s in v.subviews { dumpTree(s, depth: depth + 1, into: &out) }
    }

    @MainActor static func snapshot(_ window: NSWindow, to url: URL) {
        if ProcessInfo.processInfo.environment["CAMTWIZZLE_SNAPSHOT_TREE"] == "1", let root = window.contentView?.superview {
            var s = "window \(window.frame)\n"
            dumpTree(root, into: &s)
            try? s.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        }
        if ProcessInfo.processInfo.environment["CAMTWIZZLE_SNAPSHOT_MODE"] != "cache", layerSnapshot(window, to: url) { return }
        guard let view = window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        // Layer-hosted preview content isn't captured by cacheDisplay; draw the last frame on top.
        if let pb = AppModel.shared.lastPreview, let previewView = findPreview(in: view) {
            let frame = previewView.convert(previewView.bounds, to: view)
            let ci = CIImage(cvPixelBuffer: pb)
            if let cg = CIContext().createCGImage(ci, from: ci.extent) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
                let s = min(frame.width / iw, frame.height / ih)
                let w = iw * s, h = ih * s
                var r = CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
                if !view.isFlipped { } else { r.origin.y = bounds.height - r.maxY }
                NSGraphicsContext.current?.cgContext.draw(cg, in: r)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    @MainActor static func findPreview(in v: NSView) -> NSView? {
        if v is PreviewNSView { return v }
        for s in v.subviews { if let f = findPreview(in: s) { return f } }
        return nil
    }
}
