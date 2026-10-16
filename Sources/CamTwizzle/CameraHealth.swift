import AppKit
import Foundation

/// Out-of-band checks for the situations where the virtual camera silently
/// doesn't show CamTwizzle's picture.
enum CameraHealth {
    static let obsBundleID = "com.obsproject.obs-studio"

    /// Whether OBS Studio itself is running with its own "Start Virtual Camera" on.
    /// OBS's camera extension keeps feeding from whichever app started first, so
    /// this competes with CamTwizzle. Read from OBS's current log file.
    static func obsVirtualCameraActive() -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: obsBundleID).isEmpty else { return false }
        let logs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("obs-studio/logs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.filter { $0.pathExtension == "txt" }.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        guard let newest, let text = try? String(contentsOf: newest, encoding: .utf8) else { return false }
        let start = text.range(of: "Virtual Camera Start", options: .backwards)?.lowerBound
        let stop = text.range(of: "Virtual Camera Stop", options: .backwards)?.lowerBound
        guard let start else { return false }
        return stop.map { start > $0 } ?? true
    }

    /// Sink-capable cameras as a fresh process sees them. CoreMediaIO in a running
    /// process doesn't always pick up a camera extension that was approved after
    /// launch; if a fresh process sees one we don't, a relaunch fixes it.
    static func sinkCountOutOfProcess() -> Int {
        let tool = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/twizzle")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return 0 }
        let p = Process()
        p.executableURL = tool
        p.arguments = ["devices"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.split(separator: "\n").filter { $0.contains(" sinks=") && !$0.contains(" sinks=0") }.count
    }

    /// Quit and reopen this app.
    @MainActor static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
