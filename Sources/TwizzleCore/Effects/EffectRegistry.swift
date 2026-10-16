import Foundation

/// Discovers effect plugins in the built-in and user folders.
///   *.metal         → shader plugin (JSON header + MSL)
///   *.twzgraph, *.json → Core Image graph plugin
/// A user plugin with the same file name as a built-in one overrides it.
public final class EffectRegistry {
    public private(set) var effects: [EffectDescriptor] = []
    public private(set) var failures: [(url: URL, message: String)] = []
    public let directories: [URL]
    public let builtInDirectory: URL?
    private var byID: [String: EffectDescriptor] = [:]
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadWorkItem: DispatchWorkItem?
    public var onChange: (() -> Void)?

    public init(builtIn: URL?, user: [URL]) {
        builtInDirectory = builtIn
        directories = (builtIn.map { [$0] } ?? []) + user
        reload()
    }

    public func effect(id: String) -> EffectDescriptor? {
        byID[id] ?? byID[id.lowercased()] ?? effects.first { $0.name.lowercased() == id.lowercased() }
    }

    public var categories: [String] {
        var seen: [String] = []
        for e in effects where !seen.contains(e.primaryCategory) { seen.append(e.primaryCategory) }
        return seen.sorted()
    }

    /// Folders where Quartz Composer compositions traditionally live (scanned if present).
    public static var legacyDirectories: [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return ["/Applications/CamTwist/Effects", home.appendingPathComponent("Library/Compositions").path, "/Library/Compositions"]
            .map { URL(fileURLWithPath: $0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    public static var defaultUserDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CamTwizzle/Effects", isDirectory: true)
    }

    public func reload() {
        var found: [String: (URL, Bool)] = [:]   // id -> (url, builtIn)
        for (di, dir) in directories.enumerated() {
            let builtIn = di == 0 && builtInDirectory != nil
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                let ext = url.pathExtension.lowercased()
                guard ["metal", "twzgraph", "json", "qtz", "fs"].contains(ext) else { continue }
                if url.lastPathComponent.hasPrefix("_") { continue }   // includes / disabled
                var id = url.deletingPathExtension().lastPathComponent
                if ext == "qtz" { id = "qc." + id }   // legacy compositions get their own namespace
                if ext == "fs" { id = "isf." + id }
                found[id] = (url, builtIn)
            }
        }
        var list: [EffectDescriptor] = []
        var fails: [(URL, String)] = []
        // Shaders first so graphs can reference them.
        let ordered = found.sorted { a, b in
            let ae = ["metal", "fs"].contains(a.value.0.pathExtension) ? 0 : 1
            let be = ["metal", "fs"].contains(b.value.0.pathExtension) ? 0 : 1
            return ae != be ? ae < be : a.key < b.key
        }
        byID = [:]
        for (id, (url, builtIn)) in ordered {
            do {
                let d = try load(url: url, id: id, builtIn: builtIn)
                list.append(d)
                byID[id] = d
                byID[id.lowercased()] = d
            } catch {
                fails.append((url, "\(error)"))
            }
        }
        effects = list.sorted { ($0.primaryCategory, $0.name) < ($1.primaryCategory, $1.name) }
        // Same display name from different plugin kinds? Tag the ISF / QC variants.
        let nativeNames = Set(effects.filter { $0.kind != .quartz && !$0.url.pathExtension.lowercased().hasSuffix("fs") }.map { $0.name.lowercased() })
        for e in effects where e.url.pathExtension.lowercased() == "fs" && nativeNames.contains(e.name.lowercased()) {
            e.displaySuffix = " (ISF)"
        }
        failures = fails
        TwzLog.info("loaded \(effects.count) effects, \(failures.count) failures")
    }

    func load(url: URL, id: String, builtIn: Bool) throws -> EffectDescriptor {
        if url.pathExtension.lowercased() == "qtz" {
            let q = try QCProgram(url: url)
            var cats = ["Quartz Composer"]
            if url.path.lowercased().contains("camtwist") { cats.append("CamTwist") }
            return EffectDescriptor(id: id, name: q.name + " (QC)", categories: cats,
                                    summary: q.summary.isEmpty ? (q.isFilter ? "Legacy Quartz Composer image filter." : "Legacy Quartz Composer overlay.") : q.summary,
                                    credit: "Quartz Composer composition (\(url.lastPathComponent))",
                                    kind: .quartz, url: url, params: q.params, wantsFace: false, wantsMask: false,
                                    isBuiltIn: builtIn, program: q)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let header: JSONValue
        let program: EffectProgram
        let kind: EffectDescriptor.Kind
        let params: [ParamDescriptor]
        let ext = url.pathExtension.lowercased()
        if ext == "metal" || ext == "fs" {
            let p = try ShaderProgram(url: url, text: text, dialect: ext == "fs" ? .isf : .twizzle)
            header = p.header
            program = p
            kind = .shader
            params = p.params
        } else {
            let json = try JSONValue.parse(text)
            let g = try GraphProgram(url: url, json: json, registry: self)
            header = json
            program = g
            kind = .graph
            params = g.params
        }
        let name = header["NAME"]?.string ?? (ext == "fs" ? url.deletingPathExtension().lastPathComponent : ParamDescriptor.prettify(id))
        var cats = header["CATEGORIES"]?.strings ?? header["CATEGORY"]?.strings ?? []
        if ext == "fs" { cats = ["ISF"] + cats.map { $0.replacingOccurrences(of: " Effect", with: "") } }
        return EffectDescriptor(
            id: id, name: name, categories: cats,
            summary: header["DESCRIPTION"]?.string ?? "",
            credit: header["CREDIT"]?.string,
            kind: kind, url: url, params: params,
            wantsFace: header["FACE"]?.bool ?? false,
            wantsMask: header["MASK"]?.bool ?? header["SEGMENTATION"]?.bool ?? false,
            isBuiltIn: builtIn, program: program)
    }

    /// Watch user directories and reload (debounced) when files change.
    public func startWatching() {
        stopWatching()
        for dir in directories {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
            src.setEventHandler { [weak self] in self?.scheduleReload() }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
        // Editors often save via rename; also poll modification dates cheaply.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.pollForChanges() }
    }

    private var pollTimer: Timer?
    private var lastStamp: [String: Date] = [:]

    private func pollForChanges() {
        var stamp: [String: Date] = [:]
        for dir in directories.dropFirst(builtInDirectory == nil ? 0 : 1) {
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in e {
                stamp[url.path] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
        }
        if !lastStamp.isEmpty && stamp != lastStamp { scheduleReload() }
        lastStamp = stamp
    }

    public func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.reload()
            self?.onChange?()
        }
        reloadWorkItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }
}
