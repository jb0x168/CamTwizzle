import SwiftUI
import TwizzleCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = true

    var body: some View {
        if ProcessInfo.processInfo.environment["CAMTWIZZLE_DEBUG_FLAT"] == "1" {
            flatBody
        } else {
            splitBody
        }
    }

    /// Debug layout without glass split panes (renders fully in snapshots).
    var flatBody: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            SceneSidebar().frame(width: 230).background(Color(white: 0.13))
            Divider()
            SceneEditor()
            Divider()
            InspectorView().frame(width: 320).background(Color(white: 0.15))
        }
        .sheet(isPresented: $model.showBrowser) { EffectBrowser().environment(model) }
        .sheet(isPresented: $model.showSetup) { SetupView().environment(model) }
    }

    var splitBody: some View {
        @Bindable var model = model
        return NavigationSplitView {
            SceneSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            if model.scene != nil {
                SceneEditor()
            } else {
                ContentUnavailableView("No Virtual Camera", systemImage: "camera.filters", description: Text("Create one with ⌘N."))
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .sheet(isPresented: $model.showBrowser) {
            EffectBrowser().environment(model)
        }
        .sheet(isPresented: $model.showSetup) {
            SetupView().environment(model)
        }
    }
}

struct SceneSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: UUID?

    var body: some View {
        List(selection: Binding(get: { model.selectedSceneID }, set: { model.selectScene($0) })) {
            Section("Virtual Cameras") {
                ForEach(model.document.scenes) { s in
                    SceneRow(scene: s, status: model.status[s.id], renaming: $renaming)
                        .tag(s.id)
                        .contextMenu {
                            Button("Rename") { renaming = s.id }
                            Button("Duplicate") { model.duplicateScene(s.id) }
                            Divider()
                            Button("Delete", role: .destructive) { model.removeScene(s.id) }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                SetupStatusCard()
                HStack {
                    Button { model.addScene() } label: { Image(systemName: "plus") }
                        .help("New virtual camera")
                    Button {
                        if let id = model.selectedSceneID { model.removeScene(id) }
                    } label: { Image(systemName: "minus") }
                        .disabled(model.document.scenes.count < 2)
                        .help("Remove virtual camera")
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
        }
    }
}

struct SceneRow: View {
    @Environment(AppModel.self) private var model
    let scene: SceneConfig
    let status: EngineSceneStatus?
    @Binding var renaming: UUID?
    @State private var name = ""

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                if renaming == scene.id {
                    TextField("Name", text: $name)
                        .onSubmit {
                            if let i = model.document.scenes.firstIndex(where: { $0.id == scene.id }) { model.document.scenes[i].name = name }
                            renaming = nil
                        }
                        .onAppear { name = scene.name }
                } else {
                    Text(scene.name).fontWeight(.medium)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    var dotColor: Color {
        guard scene.enabled else { return .gray }
        if status?.deviceInUse == true { return .red }
        if status?.sinkRunning == true { return .green }
        return .orange
    }

    var subtitle: String {
        if !scene.enabled { return "Off" }
        if let st = status {
            if st.deviceInUse { return "Live · \(st.sinkName ?? "")" }
            if st.sinkRunning { return "Ready · \(st.sinkName ?? "")" }
        }
        return scene.outputDeviceUID.isEmpty ? "Preview only" : "Waiting for camera driver"
    }
}

/// Small sidebar card that nags until a virtual camera driver is available.
struct SetupStatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.needsRelaunch {
            VStack(alignment: .leading, spacing: 6) {
                Label("Virtual camera found", systemImage: "arrow.clockwise.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("A camera driver was enabled after CamTwizzle started. Restart to connect to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Restart CamTwizzle") { CameraHealth.relaunch() }
                    .controlSize(.small)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else if model.obsCompeting {
            VStack(alignment: .leading, spacing: 6) {
                Label("OBS Virtual Camera is on in OBS", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("OBS's own Start Virtual Camera competes with CamTwizzle for the same camera. Click Stop Virtual Camera in OBS, or quit OBS — CamTwizzle doesn't need it running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show OBS") {
                    NSRunningApplication.runningApplications(withBundleIdentifier: CameraHealth.obsBundleID).first?.activate()
                }
                .controlSize(.small)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else if model.sinkDevices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("No virtual camera driver", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("Photo Booth and Zoom can't see CamTwizzle yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Set Up…") { model.showSetup = true }
                    .controlSize(.small)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
