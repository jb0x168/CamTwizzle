import CoreGraphics
import CoreVideo
import ImageIO
import CoreText
import Foundation
import Metal
import TwizzleCore

// twizzle — command line companion for CamTwizzle.
//   twizzle list                         list effects
//   twizzle check                        compile every effect, report errors
//   twizzle render -i in.jpg -o out.png -e Sobel [-e Ogre] [-p amount=2] [--frames 30]
//   twizzle sheet -i in.jpg -o sheet.png [--frames 20] [--size 480x270]
//   twizzle devices                      list CoreMediaIO devices and their streams
//   twizzle run [--scene file.json] [--device UID]   headless engine pushing to a virtual camera

TwzLog.echoToStderr = true
_ = registerEngineCommands
var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()

func option(_ names: String...) -> String? {
    for n in names {
        if let i = args.firstIndex(of: n), i + 1 < args.count { return args[i + 1] }
    }
    return nil
}

func options(_ name: String) -> [String] {
    var out: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == name, i + 1 < args.count { out.append(args[i + 1]); i += 2 } else { i += 1 }
    }
    return out
}

func flag(_ name: String) -> Bool { args.contains(name) }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func filtersDirectory() -> URL {
    if let d = option("--filters") { return URL(fileURLWithPath: d) }
    if let env = ProcessInfo.processInfo.environment["TWIZZLE_FILTERS"] { return URL(fileURLWithPath: env) }
    // Next to the executable inside an app bundle, or the repo's Filters folder.
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidates = [
        exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Filters"),
        exe.deletingLastPathComponent().appendingPathComponent("../../../Filters").standardized,
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Filters"),
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.last!
}

func makeRegistry() -> EffectRegistry {
    let userDirs = options("--user-filters").map { URL(fileURLWithPath: $0) }
    return EffectRegistry(builtIn: filtersDirectory(), user: userDirs + (flag("--no-user") ? [] : [EffectRegistry.defaultUserDirectory]))
}

func parseParam(_ s: String, for d: EffectDescriptor) -> (String, ParamValue)? {
    guard let eq = s.firstIndex(of: "=") else { return nil }
    let name = String(s[..<eq]), val = String(s[s.index(after: eq)...])
    guard let p = d.params.first(where: { $0.name == name }) else { return nil }
    let nums = val.split(separator: ",").compactMap { Double($0) }
    switch p.type {
    case .float: return (name, .float(nums.first ?? 0))
    case .long: return (name, .int(Int(nums.first ?? 0)))
    case .bool, .event: return (name, .bool(["1", "true", "yes"].contains(val.lowercased())))
    case .color: return (name, .color(nums))
    case .point2D: return (name, .point(nums))
    default: return (name, .string(val))
    }
}

func parseSize(_ s: String?, default d: (Int, Int)) -> (Int, Int) {
    guard let s, let x = s.firstIndex(of: "x"), let w = Int(s[..<x]), let h = Int(s[s.index(after: x)...]) else { return d }
    return (w, h)
}

/// Render `effects` over `input` for a number of frames and return the final texture.
func renderStack(_ effects: [EffectConfig], input: MTLTexture, registry: EffectRegistry, frames: Int, fps: Double = 30,
                 face: FaceInfo? = nil, mask: MTLTexture? = nil) -> (MTLTexture?, [UUID: String]) {
    let metal = MetalContext.shared
    let resources = ResourceCache(device: metal.device)
    let runner = EffectStackRunner()
    var last: MTLTexture?
    // Quartz Composer effects run asynchronously; give them real time between frames.
    let realtime = effects.contains { registry.effect(id: $0.effectID)?.kind == .quartz }
    for f in 0..<max(1, frames) {
        guard let cb = metal.queue.makeCommandBuffer() else { break }
        let ctx = FrameContext(metal: metal, commandBuffer: cb, time: Double(f) / fps, deltaTime: 1 / fps, frameIndex: f,
                               canvasSize: SIMD2(input.width, input.height), resources: resources)
        if let face { ctx.face = face }
        ctx.mask = mask
        let out = runner.run(input: input, inputPooled: false, effects: effects, registry: registry, ctx: ctx)
        cb.commit()
        if realtime { cb.waitUntilCompleted(); usleep(30_000) }
        if f == frames - 1 || frames <= 1 {
            cb.waitUntilCompleted()
            last = out.texture
        } else if out.pooled {
            metal.pool.release(out.texture)
        }
    }
    return (last, runner.errors)
}

func demoFace() -> FaceInfo {
    var f = FaceInfo()
    f.count = 1
    return f
}

/// Run Vision on the (already resized) input so face/mask effects get real data.
func analyzeInput(_ tex: MTLTexture) -> (FaceInfo, MTLTexture?) {
    let metal = MetalContext.shared
    guard let img = TextureIO.cgImage(from: tex, metal: metal) else { return (demoFace(), nil) }
    let (face, maskPB) = SourceAnalyzer.analyze(img, face: true, mask: true)
    var maskTex: MTLTexture?
    if let pb = maskPB {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        if let t = metal.device.makeTexture(descriptor: d), let base = CVPixelBufferGetBaseAddress(pb) {
            t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: CVPixelBufferGetBytesPerRow(pb))
            maskTex = t
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    }
    if face.count == 0 { TwzLog.warn("no face found in input; using a default face rect") }
    return (face.count > 0 ? face : demoFace(), maskTex)
}

switch command {
case "list":
    let reg = makeRegistry()
    for e in reg.effects {
        let flags = (e.wantsFace ? " [face]" : "") + (e.wantsMask ? " [mask]" : "")
        print("\(e.primaryCategory.padding(toLength: 12, withPad: " ", startingAt: 0)) \(e.id.padding(toLength: 22, withPad: " ", startingAt: 0)) \(e.kind.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)) \(e.params.count) params\(flags)")
    }
    for f in reg.failures { print("FAILED \(f.url.lastPathComponent): \(f.message)") }
    print("\(reg.effects.count) effects, \(reg.failures.count) failed to load")

case "check":
    let reg = makeRegistry()
    let metal = MetalContext.shared
    var bad = reg.failures.count
    for f in reg.failures { print("✗ \(f.url.lastPathComponent): \(f.message)") }
    let only = Set(options("-e"))
    for e in reg.effects where only.isEmpty || only.contains(e.id) {
        let t0 = Date()
        if let err = e.validate(metal: metal) {
            bad += 1
            print("✗ \(e.id): \(err)")
        } else {
            print("✓ \(e.id) (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)")
        }
    }
    print(bad == 0 ? "all \(reg.effects.count) effects OK" : "\(bad) problem(s)")
    exit(bad == 0 ? 0 : 1)

case "render":
    guard let inPath = option("-i", "--input"), let outPath = option("-o", "--output") else {
        fail("usage: twizzle render -i in.jpg -o out.png -e Effect [-p name=value] [--frames N] [--size WxH]")
    }
    let reg = makeRegistry()
    let metal = MetalContext.shared
    let (w, h) = parseSize(option("--size"), default: (1280, 720))
    guard let input = TextureIO.loadTexture(URL(fileURLWithPath: inPath), width: w, height: h, metal: metal) else { fail("cannot load \(inPath)") }
    var stack: [EffectConfig] = []
    for id in options("-e") {
        guard let d = reg.effect(id: id) else { fail("unknown effect \(id)") }
        stack.append(EffectConfig(effectID: d.id))
    }
    for p in options("-p") {
        // apply to the last effect that knows the param
        for i in stack.indices.reversed() {
            if let d = reg.effect(id: stack[i].effectID), let (k, v) = parseParam(p, for: d) { stack[i].params[k] = v; break }
        }
    }
    let frames = Int(option("--frames") ?? "1") ?? 1
    let (face, mask) = analyzeInput(input)
    let (tex, errors) = renderStack(stack, input: input, registry: reg, frames: frames, face: face, mask: mask)
    for (_, e) in errors { print("error: \(e)") }
    guard let tex, let img = TextureIO.cgImage(from: tex, metal: metal) else { fail("render failed") }
    try TextureIO.writePNG(img, to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")

case "sheet":
    guard let inPath = option("-i", "--input"), let outPath = option("-o", "--output") else {
        fail("usage: twizzle sheet -i in.jpg -o sheet.png [--frames N] [--size WxH] [--cols N] [-e only...]")
    }
    let reg = makeRegistry()
    let metal = MetalContext.shared
    let (w, h) = parseSize(option("--size"), default: (480, 270))
    let cols = Int(option("--cols") ?? "6") ?? 6
    guard let input = TextureIO.loadTexture(URL(fileURLWithPath: inPath), width: w, height: h, metal: metal) else { fail("cannot load \(inPath)") }
    let frames = Int(option("--frames") ?? "15") ?? 15
    let (face, mask) = analyzeInput(input)
    let only = Set(options("-e"))
    let list = reg.effects.filter { only.isEmpty || only.contains($0.id) }
    let rows = (list.count + cols - 1) / cols
    let labelH = 22
    let sheetW = cols * w, sheetH = rows * (h + labelH)
    guard let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("ctx") }
    ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 14, nil)
    for (i, e) in list.enumerated() {
        let (tex, errors) = renderStack([EffectConfig(effectID: e.id)], input: input, registry: reg, frames: frames, face: face, mask: mask)
        let col = i % cols, row = i / cols
        let x = col * w, yTop = row * (h + labelH)
        let cgY = sheetH - yTop - labelH - h
        if let tex, errors.isEmpty, let img = TextureIO.cgImage(from: tex, metal: metal) {
            ctx.draw(img, in: CGRect(x: x, y: cgY, width: w, height: h))
        } else {
            ctx.setFillColor(CGColor(red: 0.5, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: x, y: cgY, width: w, height: h))
            for (_, err) in errors { print("✗ \(e.id): \(err.prefix(300))") }
        }
        let label = NSAttributedString(string: "\(e.name)  ·  \(e.primaryCategory)", attributes: [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1)])
        let line = CTLineCreateWithAttributedString(label)
        ctx.textPosition = CGPoint(x: x + 6, y: sheetH - yTop - 16)
        CTLineDraw(line, ctx)
    }
    guard let img = ctx.makeImage() else { fail("no image") }
    try TextureIO.writePNG(img, to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(list.count) effects)")

case "thumbs":
    // Pre-render a thumbnail for every effect (shipped in the app's effect browser).
    guard let inPath = option("-i", "--input"), let outDir = option("-o", "--output") else { fail("usage: twizzle thumbs -i in.jpg -o DIR [--size WxH]") }
    let reg = makeRegistry()
    let metal = MetalContext.shared
    let (w, h) = parseSize(option("--size"), default: (320, 180))
    guard let input = TextureIO.loadTexture(URL(fileURLWithPath: inPath), width: w, height: h, metal: metal) else { fail("cannot load \(inPath)") }
    let (face, mask) = analyzeInput(input)
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    var n = 0
    for e in reg.effects where e.kind != .quartz {
        let dest = URL(fileURLWithPath: outDir).appendingPathComponent(e.id + ".jpg")
        if FileManager.default.fileExists(atPath: dest.path) && !flag("--force") { continue }
        let (tex, errors) = renderStack([EffectConfig(effectID: e.id)], input: input, registry: reg, frames: 24, face: face, mask: mask)
        guard errors.isEmpty, let tex, let img = TextureIO.cgImage(from: tex, metal: metal),
              let d = CGImageDestinationCreateWithURL(dest as CFURL, "public.jpeg" as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        CGImageDestinationFinalize(d)
        n += 1
    }
    print("wrote \(n) thumbnails to \(outDir)")

default:
    if let handler = extraCommands[command] {
        handler()
    } else {
        print("""
        twizzle — CamTwizzle command line
          list | check [-e id] | render -i IN -o OUT -e ID... [-p k=v] [--frames N] [--size WxH] [--face]
          sheet -i IN -o OUT [--frames N] [--size WxH] [--cols N]
          devices | run [--scene FILE] [--device UID] [--seconds N]
        options: --filters DIR  --user-filters DIR  --no-user
        """)
    }
}
