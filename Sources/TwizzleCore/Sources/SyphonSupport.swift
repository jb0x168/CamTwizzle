#if HAVE_SYPHON
import Foundation
import Metal
import Syphon

public struct SyphonServerInfo: Identifiable, Hashable {
    public var id: String { uuid }
    public let uuid: String
    public let name: String
    public let appName: String
    public var displayName: String { name.isEmpty ? appName : "\(appName) — \(name)" }
}

public enum SyphonDirectory {
    public static func servers() -> [SyphonServerInfo] {
        let all = SyphonServerDirectory.shared().servers as? [[String: Any]] ?? []
        return all.compactMap { d in
            guard let uuid = d[SyphonServerDescriptionUUIDKey] as? String else { return nil }
            return SyphonServerInfo(uuid: uuid, name: d[SyphonServerDescriptionNameKey] as? String ?? "",
                                    appName: d[SyphonServerDescriptionAppNameKey] as? String ?? "")
        }.filter { $0.appName != "CamTwizzle" && $0.appName != "twizzle" }
    }

    static func description(uuid: String) -> [String: Any]? {
        (SyphonServerDirectory.shared().servers as? [[String: Any]])?.first { ($0[SyphonServerDescriptionUUIDKey] as? String) == uuid }
    }
}

/// Receives frames from a Syphon server (VDMX, Resolume, MadMapper, TouchDesigner…).
public final class SyphonSource: BufferedSource {
    private var client: SyphonMetalClient?
    private var retry: DispatchSourceTimer?

    public override func start() {
        setState(.starting)
        connect()
        // Servers come and go; keep trying to (re)connect.
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if self.client == nil || !(self.client!.isValid) { self.connect() }
        }
        t.resume()
        retry = t
    }

    private func connect() {
        // Match by UUID first, then by app/server name (UUIDs change when the server app restarts).
        var desc = SyphonDirectory.description(uuid: spec.identifier)
        if desc == nil {
            let all = SyphonServerDirectory.shared().servers as? [[String: Any]] ?? []
            desc = all.first { d in
                let n = "\(d[SyphonServerDescriptionAppNameKey] as? String ?? "") — \(d[SyphonServerDescriptionNameKey] as? String ?? "")"
                return n == spec.name || (d[SyphonServerDescriptionAppNameKey] as? String) == spec.name
                    || (d[SyphonServerDescriptionNameKey] as? String) == spec.name
            }
        }
        guard let desc else {
            setState(.failed("Syphon server '\(spec.name)' not running"))
            client = nil
            return
        }
        client = SyphonMetalClient(serverDescription: desc, device: MetalContext.shared.device, options: nil) { [weak self] c in
            guard let self, let tex = c.newFrameImage() else { return }
            self.publish(SourceFrame(texture: tex, timestamp: CACurrentMediaTimeCompat()))
        }
    }

    public override func stop() {
        retry?.cancel()
        retry = nil
        client?.stop()
        client = nil
        clearFrame()
        setState(.idle)
    }
}

/// Publishes a scene's output as a Syphon server.
public final class SyphonOutput {
    private let server: SyphonMetalServer

    public init(name: String, device: MTLDevice) {
        server = SyphonMetalServer(name: name, device: device, options: nil)
    }

    public func publish(_ texture: MTLTexture, cb: MTLCommandBuffer) {
        server.publishFrameTexture(texture, on: cb, imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height), flipped: false)
    }

    public var hasClients: Bool { server.hasClients }

    public func stop() { server.stop() }
}
#endif
