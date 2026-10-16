import SwiftUI
import TwizzleCore

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch model.selection {
                case let .effect(id)?:
                    if let cfg = model.effectConfig(id) {
                        EffectInspector(config: cfg)
                    } else {
                        SceneInspector()
                    }
                case let .layer(id)?:
                    if let layer = model.scene?.layers.first(where: { $0.id == id }) {
                        LayerInspector(layer: layer)
                    } else {
                        SceneInspector()
                    }
                default:
                    SceneInspector()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: Effect

struct EffectInspector: View {
    @Environment(AppModel.self) private var model
    let config: EffectConfig

    var body: some View {
        let d = model.descriptor(config.effectID)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(d?.name ?? config.effectID).font(.title2.bold())
                Spacer()
                Toggle("", isOn: Binding(get: { config.enabled }, set: { v in model.mutateEffect(config.id) { $0.enabled = v } }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if let d {
                HStack(spacing: 6) {
                    ForEach(d.categories, id: \.self) { c in
                        Text(c).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(d.kind == .shader ? "Metal shader" : (d.kind == .graph ? "Core Image graph" : "Quartz Composer (legacy)")).font(.caption2).foregroundStyle(.secondary)
                    if d.wantsFace { Image(systemName: "face.smiling").font(.caption).help("Uses face tracking") }
                    if d.wantsMask { Image(systemName: "person.crop.rectangle").font(.caption).help("Uses person segmentation") }
                }
                if !d.summary.isEmpty {
                    Text(d.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
        if let err = model.error(for: config.id) {
            ScrollView(.horizontal) {
                Text(err).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
            }
            .padding(8)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        if let d {
            if d.params.isEmpty {
                Text("This effect has no parameters.").font(.callout).foregroundStyle(.secondary)
            } else {
                InspectorSection(title: "Parameters") {
                    ForEach(d.params) { p in
                        ParamControl(param: p, value: model.paramBinding(effect: config.id, param: p))
                    }
                }
                if d.params.contains(where: { $0.type == .point2D }) {
                    Text("Tip: drag on the preview to move \(d.params.first { $0.type == .point2D }!.label.lowercased()).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button("Reset") { model.resetEffectParams(config.id) }
                Button("Restart") { model.restartEffect(config.id) }.help("Clear feedback buffers and timers")
                Spacer()
                Button(d.isBuiltIn ? "Customize…" : "Edit…") { model.editEffectSource(d) }
                    .help(d.isBuiltIn ? "Copy into My Effects and open in your editor; changes reload live" : "Open in your editor; changes reload live")
            }
            HStack {
                Button("Duplicate") { model.duplicateEffect(config.id) }
                Spacer()
                Button("Remove", role: .destructive) { model.removeEffect(config.id) }
            }
            if let credit = d.credit {
                Text(credit).font(.caption2).foregroundStyle(.tertiary)
            }
            Text(d.url.lastPathComponent + (d.isBuiltIn ? " (built-in)" : " (my effects)"))
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
        } else {
            Text("The effect '\(config.effectID)' is not installed.").foregroundStyle(.red)
            Button("Remove", role: .destructive) { model.removeEffect(config.id) }
        }
    }
}

// MARK: Layer

struct LayerInspector: View {
    @Environment(AppModel.self) private var model
    let layer: LayerConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon(for: layer.source.kind)).font(.title2)
                Text(layer.source.name).font(.title2.bold()).lineLimit(2)
            }
            Text(kindName).font(.callout).foregroundStyle(.secondary)
            if let msg = model.sceneStatus?.layerStates[layer.id]?.message {
                Label(msg, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if layer.source.kind == .screen || layer.source.kind == .window {
                    Button("Open Screen Recording Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
                if layer.source.kind == .camera {
                    Button("Open Camera Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
            }
        }
        AddSourceMenu(label: "Replace Source") { spec in model.replaceSource(layer.id, with: spec) }
            .fixedSize()

        InspectorSection(title: "Framing") {
            Picker("Fit", selection: model.layerBinding(layer.id, \.fit, default: .fill)) {
                Text("Fill").tag(FitMode.fill)
                Text("Fit").tag(FitMode.fit)
                Text("Stretch").tag(FitMode.stretch)
            }
            .pickerStyle(.segmented)
            Toggle("Mirror", isOn: model.layerBinding(layer.id, \.mirror, default: false))
            CropControls(layerID: layer.id)
        }

        InspectorSection(title: "Placement") {
            SliderRow(label: "Size", value: model.layerBinding(layer.id, \.scale, default: 1), range: 0.05...2, format: "%.0f%%", display: { $0 * 100 })
            SliderRow(label: "X", value: model.layerBinding(layer.id, \.x, default: 0.5), range: -0.5...1.5)
            SliderRow(label: "Y", value: model.layerBinding(layer.id, \.y, default: 0.5), range: -0.5...1.5)
            SliderRow(label: "Rotate", value: model.layerBinding(layer.id, \.rotation, default: 0), range: -180...180, format: "%.0f°")
            SliderRow(label: "Opacity", value: model.layerBinding(layer.id, \.opacity, default: 1), range: 0...1, format: "%.0f%%", display: { $0 * 100 })
            Picker("Blend", selection: model.layerBinding(layer.id, \.blend, default: .normal)) {
                ForEach(BlendMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            HStack {
                Button("Full Frame") { model.mutateLayer(layer.id) { $0.x = 0.5; $0.y = 0.5; $0.scale = 1; $0.rotation = 0 } }
                Button("Corner PIP") { model.mutateLayer(layer.id) { $0.x = 0.8; $0.y = 0.78; $0.scale = 0.3; $0.rotation = 0 } }
            }
        }

        InspectorSection(title: "Effects on this source") {
            if layer.effects.isEmpty {
                Text("None. Effects added here only apply to this source (before compositing).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(layer.effects) { e in
                Button {
                    model.selection = .effect(e.id)
                } label: {
                    Label(model.descriptor(e.effectID)?.name ?? e.effectID, systemImage: "wand.and.stars")
                }
                .buttonStyle(.link)
            }
            Button("Add Effect…") {
                model.browserTarget = .layer(layer.id)
                model.showBrowser = true
            }
        }
        Divider()
        Button("Remove Source", role: .destructive) { model.removeLayer(layer.id) }
    }

    var kindName: String {
        switch layer.source.kind {
        case .camera: return "Camera"
        case .screen: return "Screen capture"
        case .window: return "Window capture"
        case .syphon: return "Syphon"
        case .image: return "Image"
        case .movie: return "Movie (looping)"
        case .pattern: return "Generator"
        }
    }
}

struct CropControls: View {
    @Environment(AppModel.self) private var model
    let layerID: UUID

    var body: some View {
        DisclosureGroup("Crop") {
            ForEach(Array(["Left", "Top", "Right", "Bottom"].enumerated()), id: \.offset) { i, name in
                SliderRow(label: name, value: Binding(
                    get: { model.scene?.layers.first { $0.id == layerID }?.crop[safe: i] ?? 0 },
                    set: { v in model.mutateLayer(layerID) { l in
                        if l.crop.count != 4 { l.crop = [0, 0, 0, 0] }
                        l.crop[i] = v
                    } }
                ), range: 0...0.45, format: "%.0f%%", display: { $0 * 100 })
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

// MARK: Scene

struct SceneInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let scene = model.scene {
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.name).font(.title2.bold())
                Text("Virtual camera").font(.callout).foregroundStyle(.secondary)
            }
            InspectorSection(title: "Camera") {
                TextField("Name", text: model.sceneBinding(\.name, default: ""))
                Toggle("Enabled", isOn: model.sceneBinding(\.enabled, default: true))
                LabeledContent("Output") { OutputPicker().fixedSize() }
                #if HAVE_SYPHON
                Toggle("Also publish via Syphon", isOn: model.sceneBinding(\.syphonOutput, default: false))
                    .help("Other apps (OBS, VDMX, Resolume…) can receive this camera as a Syphon source")
                #endif
                LabeledContent("Resolution", value: "\(scene.width) × \(scene.height) @ \(scene.fps) fps")
            }
            if let st = model.sceneStatus {
                InspectorSection(title: "Status") {
                    LabeledContent("Frame rate", value: String(format: "%.1f fps", st.fps))
                    LabeledContent("CPU encode", value: String(format: "%.2f ms", st.renderMS))
                    if !scene.outputDeviceUID.isEmpty {
                        LabeledContent("Driver", value: st.sinkName ?? "not connected")
                        LabeledContent("Frames sent", value: "\(st.framesSent)")
                        LabeledContent("In use by an app", value: st.deviceInUse ? "Yes" : "No")
                    }
                    if let e = st.sinkError { Text(e).font(.caption).foregroundStyle(.orange) }
                }
            }
            InspectorSection(title: "How it works") {
                Text("Sources are stacked bottom-to-top (each can have its own effects), then the Effects column is applied to the composite — each effect processes the output of the one above it. Select CamTwizzle's output camera in Photo Booth, Zoom, FaceTime, etc.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Generic slider row

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format = "%.2f"
    var display: (Double) -> Double = { $0 }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 64, alignment: .leading).lineLimit(1)
            Slider(value: $value, in: range)
            Text(String(format: format, display(value)))
                .font(.caption.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
