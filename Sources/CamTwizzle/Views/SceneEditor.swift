import SwiftUI
import TwizzleCore

let debugHide = Set((ProcessInfo.processInfo.environment["CAMTWIZZLE_DEBUG_HIDE"] ?? "").split(separator: ",").map(String.init))

struct SceneEditor: View {
    @Environment(AppModel.self) private var model
    @AppStorage("stackHeight") private var stackHeight: Double = 300
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            if !debugHide.contains("preview") {
                PreviewPanel()
                    .frame(maxHeight: .infinity)
            }
            if !debugHide.contains("stack") {
                // Draggable divider between preview and stacks.
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .overlay(Color.clear.frame(height: 9).contentShape(Rectangle())
                        .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { g in
                            if dragStart == nil { dragStart = stackHeight }
                            stackHeight = min(max((dragStart ?? 300) - g.translation.height, 160), 700)
                        }.onEnded { _ in dragStart = nil }))
                StackPanel()
                    .frame(height: stackHeight)
            }
        }
        .navigationTitle(model.scene?.name ?? "CamTwizzle")
        .navigationSubtitle(subtitle)
        .toolbar {
            if !debugHide.contains("toolbar") {
            ToolbarItemGroup {
                OutputPicker()
                Menu {
                    Section("Resolution") {
                        ForEach([(1920, 1080), (1280, 720), (960, 540), (640, 360)], id: \.0) { w, h in
                            Button("\(w) × \(h)\(model.scene?.width == w ? " ✓" : "")") { model.mutateScene { $0.width = w; $0.height = h } }
                        }
                    }
                    Section("Frame Rate") {
                        ForEach([15, 24, 30, 60], id: \.self) { f in
                            Button("\(f) fps\(model.scene?.fps == f ? " ✓" : "")") { model.mutateScene { $0.fps = f } }
                        }
                    }
                } label: {
                    Label("\(model.scene?.width ?? 0)×\(model.scene?.height ?? 0)", systemImage: "aspectratio")
                }
                .help("Output resolution and frame rate")
            }
            }
        }
    }

    var subtitle: String {
        guard let st = model.sceneStatus else { return "" }
        return String(format: "%.0f fps · GPU %.1f ms · CPU %.1f ms", st.fps, st.gpuMS, st.renderMS)
    }
}

struct OutputPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button {
                UserDefaults.standard.set(true, forKey: "outputChosenManually")
                model.mutateScene { $0.outputDeviceUID = "" }
            } label: {
                Text("Preview Only")
            }
            if !model.sinkDevices.isEmpty { Divider() }
            ForEach(model.sinkDevices) { d in
                Button {
                    UserDefaults.standard.set(true, forKey: "outputChosenManually")
                    model.mutateScene { $0.outputDeviceUID = d.uid }
                } label: {
                    Text(d.name + (model.scene?.outputDeviceUID == d.uid ? " ✓" : ""))
                }
            }
            Divider()
            Button("Virtual Camera Setup…") { model.showSetup = true }
        } label: {
            Label(outputName, systemImage: "web.camera")
        }
        .help("Which virtual camera this scene feeds")
    }

    var outputName: String {
        guard let uid = model.scene?.outputDeviceUID, !uid.isEmpty else { return "Preview Only" }
        return model.sinkDevices.first { $0.uid == uid }?.name ?? "Camera unavailable"
    }
}

struct PreviewPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                PreviewView(host: model.preview)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        pointDrag(at: g.location, in: geo.size)
                    })
            }
            statusBadges.padding(10)
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
    }

    /// Dragging on the preview moves the selected effect's first point parameter.
    private func pointDrag(at p: CGPoint, in size: CGSize) {
        guard case let .effect(id)? = model.selection, let cfg = model.effectConfig(id), let d = model.descriptor(cfg.effectID),
              let param = d.params.first(where: { $0.type == .point2D }) else { return }
        // The layer aspect-fits the frame; find the picture rect.
        let aspect = CGFloat(model.scene?.width ?? 16) / CGFloat(model.scene?.height ?? 9)
        var w = size.width, h = size.width / aspect
        if h > size.height { h = size.height; w = h * aspect }
        let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        let x = min(max((p.x - rect.minX) / rect.width, 0), 1), y = min(max((p.y - rect.minY) / rect.height, 0), 1)
        model.mutateEffect(id) { $0.params[param.name] = .point([x, y]) }
    }

    @ViewBuilder var statusBadges: some View {
        if let st = model.sceneStatus {
            HStack(spacing: 6) {
                Badge(text: String(format: "%.0f FPS", st.fps), color: .black.opacity(0.55))
                if st.deviceInUse {
                    Badge(text: "● LIVE", color: .red.opacity(0.85))
                } else if st.sinkRunning {
                    Badge(text: "Ready", color: .green.opacity(0.7))
                }
                if st.faceCount > 0 { Badge(text: "☺︎ \(st.faceCount)", color: .blue.opacity(0.7)) }
                if let e = st.sinkError, !(model.scene?.outputDeviceUID.isEmpty ?? true) {
                    Badge(text: e, color: .orange.opacity(0.85))
                }
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

// MARK: - Stacks (sources with their effects, master effects)

struct StackPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SourcesColumn()
            Divider()
            EffectsColumn(target: .master, title: "Effects", subtitle: "Applied to the whole picture, top to bottom")
        }
    }
}

struct SourcesColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: "Sources", subtitle: "Bottom layer first") {
                AddSourceMenu { spec in model.addLayer(spec) }
            }
            List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                ForEach(model.scene?.layers ?? []) { layer in
                    LayerRow(layer: layer)
                        .tag(Selection.layer(layer.id))
                    ForEach(layer.effects) { e in
                        EffectRow(effect: e, indent: true)
                            .tag(Selection.effect(e.id))
                    }
                    .onMove { from, to in model.moveEffects(in: .layer(layer.id), from: from, to: to) }
                }
                .onMove { from, to in model.moveLayers(from: from, to: to) }
            }
            .listStyle(.inset)
            .onDeleteCommand { deleteSelection() }
        }
        .frame(minWidth: 200, maxWidth: .infinity)
    }

    func deleteSelection() {
        switch model.selection {
        case let .layer(id)?: model.removeLayer(id)
        case let .effect(id)?: model.removeEffect(id)
        default: break
        }
    }
}

struct EffectsColumn: View {
    @Environment(AppModel.self) private var model
    let target: StackTarget
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(title: title, subtitle: subtitle) {
                Button {
                    model.browserTarget = target
                    model.showBrowser = true
                } label: {
                    Label("Add Effect", systemImage: "plus")
                }
                .help("Add an effect (⌘K)")
            }
            List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                ForEach(model.scene?.effects ?? []) { e in
                    EffectRow(effect: e, indent: false)
                        .tag(Selection.effect(e.id))
                }
                .onMove { from, to in model.moveEffects(in: .master, from: from, to: to) }
                if (model.scene?.effects ?? []).isEmpty {
                    Text("No effects yet — click + to add Ogre, Sobel, Matrix, ASCII and more.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .listStyle(.inset)
            .onDeleteCommand {
                if case let .effect(id)? = model.selection { model.removeEffect(id) }
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity)
    }
}

struct ColumnHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer()
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct LayerRow: View {
    @Environment(AppModel.self) private var model
    let layer: LayerConfig

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: layer.source.kind))
                .frame(width: 18)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.source.name).lineLimit(1)
                if let msg = model.sceneStatus?.layerStates[layer.id]?.message {
                    Text(msg).font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if !layer.isFullFrame {
                    Text("Picture-in-picture").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Add Effect to This Source…") {
                    model.browserTarget = .layer(layer.id)
                    model.showBrowser = true
                }
                Button(layer.enabled ? "Hide" : "Show") { model.mutateLayer(layer.id) { $0.enabled.toggle() } }
                Divider()
                Button("Remove Source", role: .destructive) { model.removeLayer(layer.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Toggle("", isOn: model.layerBinding(layer.id, \.enabled, default: true))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .opacity(layer.enabled ? 1 : 0.5)
    }
}

func icon(for kind: SourceSpec.Kind) -> String {
    switch kind {
    case .camera: return "web.camera"
    case .screen: return "display"
    case .window: return "macwindow"
    case .syphon: return "point.3.connected.trianglepath.dotted"
    case .image: return "photo"
    case .movie: return "film"
    case .pattern: return "square.grid.3x3.fill"
    }
}

struct EffectRow: View {
    @Environment(AppModel.self) private var model
    let effect: EffectConfig
    let indent: Bool

    var body: some View {
        let d = model.descriptor(effect.effectID)
        HStack(spacing: 8) {
            if indent { Color.clear.frame(width: 14) }
            Image(systemName: d?.kind == .graph ? "point.3.filled.connected.trianglepath.dotted" : (d?.kind == .quartz ? "q.circle" : "wand.and.stars"))
                .frame(width: 18)
                .foregroundStyle(effect.enabled ? Color.purple : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(effect.label ?? d?.name ?? effect.effectID).lineLimit(1)
                if let err = model.error(for: effect.id) {
                    Text(err.split(separator: "\n").first.map(String.init) ?? err)
                        .font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if d == nil {
                    Text("Missing effect").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { effect.enabled }, set: { v in model.mutateEffect(effect.id) { $0.enabled = v } }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .opacity(effect.enabled ? 1 : 0.55)
        .contextMenu {
            Button("Duplicate") { model.duplicateEffect(effect.id) }
            Button("Reset Parameters") { model.resetEffectParams(effect.id) }
            if let d { Button("Edit Source…") { model.editEffectSource(d) } }
            Divider()
            Button("Remove", role: .destructive) { model.removeEffect(effect.id) }
        }
    }
}

/// Menu for picking any available source.
struct AddSourceMenu: View {
    @Environment(AppModel.self) private var model
    var label = "Add Source"
    let onPick: (SourceSpec) -> Void

    var body: some View {
        Menu {
            Section("Cameras") {
                if model.cameras.isEmpty { Text("No cameras found") }
                ForEach(model.cameras) { c in
                    Button(c.name) { onPick(SourceSpec(kind: .camera, identifier: c.uniqueID, name: c.name)) }
                }
            }
            Section("Screens") {
                ForEach(model.displays) { d in
                    Button(d.name) { onPick(SourceSpec(kind: .screen, identifier: d.id, name: d.name)) }
                }
            }
            if !model.windows.isEmpty {
                Menu("Window") {
                    ForEach(model.windows) { w in
                        Button(w.name) { onPick(SourceSpec(kind: .window, identifier: w.id, name: w.appName ?? w.name)) }
                    }
                }
            }
            #if HAVE_SYPHON
            Menu("Syphon") {
                let servers = SyphonDirectory.servers()
                if servers.isEmpty { Text("No Syphon servers running") }
                ForEach(servers) { s in
                    Button(s.displayName) { onPick(SourceSpec(kind: .syphon, identifier: s.uuid, name: s.displayName)) }
                }
            }
            #endif
            Section("Media") {
                Button("Image File…") { pickFile(kind: .image) }
                Button("Movie File (loops)…") { pickFile(kind: .movie) }
            }
            Section("Generators") {
                ForEach(PatternSource.patterns, id: \.id) { p in
                    Button(p.name) { onPick(SourceSpec(kind: .pattern, identifier: p.id, name: p.name)) }
                }
            }
            Divider()
            Button("Refresh Devices") { model.refreshDevices() }
        } label: {
            Label(label, systemImage: "plus")
        }
        .onAppear { model.refreshDevices() }
    }

    private func pickFile(kind: SourceSpec.Kind) {
        let p = NSOpenPanel()
        p.allowedContentTypes = kind == .image ? [.image] : [.movie, .video, .audiovisualContent]
        if p.runModal() == .OK, let url = p.url {
            onPick(SourceSpec(kind: kind, identifier: url.path, name: url.lastPathComponent))
        }
    }
}
