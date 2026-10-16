import AVFoundation
import SwiftUI
import TwizzleCore

/// Guides the user through getting a virtual camera driver and permissions in place.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var installer = ExtensionInstaller.shared
    @State private var cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var screenOK = ScreenDevices.hasPermission

    var obsInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/OBS.app") }
    var obsDevice: VirtualCameraDevice? { model.sinkDevices.first { $0.isOBS } }
    var ownDevice: VirtualCameraDevice? { model.sinkDevices.first { $0.isCamTwizzle } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "web.camera").font(.largeTitle).foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("Virtual Camera Setup").font(.title2.bold())
                    Text("CamTwizzle renders your sources and effects, then feeds them into a virtual camera that Photo Booth, Zoom, FaceTime, Meet, OBS etc. can select.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    relaunchNotice
                    driverOwn
                    driverOBS
                    permissions
                    if !model.sinkDevices.isEmpty {
                        ClientTestBox()
                        GroupBox("Detected virtual cameras") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.sinkDevices) { d in
                                    Label("\(d.name)  ·  \(CMIO.isInUse(d) ? "in use" : "idle")", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button("Refresh") { refresh() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 640, height: 640)
        .onAppear { refresh() }
    }

    func refresh() {
        model.refreshSinks()
        model.checkHealth()
        model.refreshDevices()
        cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        screenOK = ScreenDevices.hasPermission
        if installer.extensionURL != nil { installer.refresh() }
    }

    @ViewBuilder var relaunchNotice: some View {
        if model.needsRelaunch {
            GroupBox {
                HStack {
                    Label("A virtual camera was enabled after CamTwizzle started. Restart CamTwizzle to connect to it.", systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.blue).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Restart") { CameraHealth.relaunch() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder var driverOwn: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("① CamTwizzle Camera").font(.headline)
                    Spacer()
                    if ownDevice != nil { StatusPill(text: "Active", color: .green) }
                    else if installer.state == .awaitingApproval { StatusPill(text: "Needs approval", color: .orange) }
                    else { StatusPill(text: "Not installed", color: .gray) }
                }
                Text("CamTwizzle's own Camera Extension shows up as “CamTwizzle” in every app. macOS only loads camera extensions signed by an Apple Developer Program team, so this build must be signed with your team (see README › Signing).")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let team = ExtensionInstaller.teamIdentifier {
                    Text("Signed by team \(team)").font(.caption.monospaced())
                } else {
                    Label("This copy is not signed with a Developer team, so the extension can't be installed.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !installer.isInApplications {
                    Label("Move CamTwizzle.app to /Applications before installing.", systemImage: "folder").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Install Camera Extension") { installer.activate() }
                        .disabled(!installer.canInstall)
                    Button("Uninstall") { installer.deactivate() }
                        .disabled(!installer.canInstall)
                    Button("Open Extension Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                }
                if !installer.log.isEmpty {
                    Text(installer.log.suffix(3).joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder var driverOBS: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("② OBS Virtual Camera (no developer account needed)").font(.headline)
                    Spacer()
                    if obsDevice != nil { StatusPill(text: "Active", color: .green) }
                    else if obsInstalled { StatusPill(text: "Not activated", color: .orange) }
                    else { StatusPill(text: "Not installed", color: .gray) }
                }
                Text("OBS Studio ships a signed camera extension that accepts frames from other apps. CamTwizzle can drive it directly — OBS itself doesn't need to be running. In other apps the camera is called “OBS Virtual Camera”.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if obsDevice == nil {
                    if obsInstalled {
                        Text("One-time activation: open OBS, click **Start Virtual Camera** (bottom right) and approve “OBS” in System Settings › General › Login Items & Extensions › Camera Extensions. Then click **Stop Virtual Camera** and quit OBS — while OBS's own virtual camera is on, it competes with CamTwizzle.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open OBS") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/OBS.app")) }
                            Button("Open Extension Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                            }
                        }
                    } else {
                        Text("Install OBS Studio (free): `brew install --cask obs` or download from obsproject.com, then come back here.")
                            .font(.callout).textSelection(.enabled)
                        Button("Download OBS…") { NSWorkspace.shared.open(URL(string: "https://obsproject.com/download")!) }
                    }
                } else if let d = obsDevice {
                    if model.obsCompeting {
                        Label("OBS's own Virtual Camera is on. Click Stop Virtual Camera in OBS (or quit OBS) so other apps see CamTwizzle.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Use for “\(model.scene?.name ?? "")”") {
                        model.mutateScene { $0.outputDeviceUID = d.uid }
                    }
                    .disabled(model.scene?.outputDeviceUID == d.uid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder var permissions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions").font(.headline)
                HStack {
                    Label("Camera", systemImage: "camera")
                    Spacer()
                    switch cameraAuth {
                    case .authorized: StatusPill(text: "Allowed", color: .green)
                    case .notDetermined:
                        Button("Allow…") { CameraDevices.requestAccess { _ in refresh() } }
                    default:
                        Button("Open Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!) }
                    }
                }
                Text("Needed for webcam sources and to talk to virtual camera drivers.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label("Screen Recording", systemImage: "display")
                    Spacer()
                    if screenOK { StatusPill(text: "Allowed", color: .green) } else {
                        Button("Allow…") {
                            ScreenDevices.requestPermission()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                }
                Text("Needed only for screen and window sources.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption.bold()).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}


/// Opens the virtual camera like Photo Booth would and shows what arrives.
struct ClientTestBox: View {
    @Environment(AppModel.self) private var model
    @State private var client: CameraClient?
    @State private var host = PreviewHost()
    @State private var frames = 0
    @State private var device = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Test what other apps see").font(.headline)
                    Spacer()
                    Picker("", selection: $device) {
                        ForEach(model.sinkDevices) { d in Text(d.name).tag(d.name) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Button(client == nil ? "Start" : "Stop") { toggle() }
                }
                if client != nil {
                    PreviewView(host: host)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                    Text("\(frames) frames received").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if device.isEmpty { device = model.sinkDevices.first?.name ?? "" } }
        .onDisappear { client?.stop(); client = nil }
    }

    func toggle() {
        if let c = client { c.stop(); client = nil; return }
        guard let c = CameraClient(deviceNameOrID: device) else { return }
        let h = host
        c.onFrame = { pb in
            DispatchQueue.main.async {
                h.display(pb)
                frames += 1
            }
        }
        c.start()
        client = c
    }
}
