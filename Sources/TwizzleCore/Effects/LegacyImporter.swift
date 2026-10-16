import Foundation

/// Fetches CamTwist's original Quartz Composer effects (from the official
/// CamTwist download) into the user's effects folder, so they can run through
/// the legacy Quartz Composer runtime next to the native ports.
public enum LegacyImporter {
    public static let camTwistDMG = URL(string: "https://camtwiststudio.com/beta/CamTwist_3.4.3.dmg")!

    public static var destination: URL {
        EffectRegistry.defaultUserDirectory.appendingPathComponent("CamTwist Classics", isDirectory: true)
    }

    /// Download, mount read-only, copy `Effects/*.qtz`, unmount. Calls back with the number of files copied.
    public static func importCamTwist(progress: ((String) -> Void)? = nil, completion: @escaping (Result<Int, Error>) -> Void) {
        progress?("Downloading CamTwist…")
        let task = URLSession.shared.downloadTask(with: camTwistDMG) { tmp, _, error in
            if let error { completion(.failure(error)); return }
            guard let tmp else { completion(.failure(PluginError.missingResource("download failed"))); return }
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("camtwizzle-import-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }
                let dmg = work.appendingPathComponent("CamTwist.dmg")
                try FileManager.default.moveItem(at: tmp, to: dmg)
                let mount = work.appendingPathComponent("mnt")
                progress?("Mounting disk image…")
                try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path])
                defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
                let effects = mount.appendingPathComponent("Manual Install/CamTwist/Effects")
                let files = try FileManager.default.contentsOfDirectory(at: effects, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "qtz" && !$0.lastPathComponent.hasSuffix("~.qtz") }
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                var n = 0
                for f in files {
                    let d = destination.appendingPathComponent(f.lastPathComponent)
                    try? FileManager.default.removeItem(at: d)
                    try FileManager.default.copyItem(at: f, to: d)
                    n += 1
                }
                progress?("Imported \(n) compositions")
                completion(.success(n))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { throw PluginError.unsupported("\(tool) failed: \(out)") }
        return out
    }
}
