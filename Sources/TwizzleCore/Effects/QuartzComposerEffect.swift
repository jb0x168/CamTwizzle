import AppKit
import CoreVideo
import Foundation
import IOSurface
import Metal
import OpenGL.GL
import OpenGL.GL3
import Quartz

/// Legacy support: runs Quartz Composer compositions (.qtz) — e.g. CamTwist's
/// original effects — through Apple's (deprecated, but still shipping)
/// QuartzComposer framework.
///
/// * "image-filter" compositions: the frame goes into `_protocolInput_Image`,
///   `_protocolOutput_Image` comes back as an IOSurface pixel buffer.
/// * any other composition is treated as an overlay: rendered into a
///   transparent IOSurface-backed framebuffer and composited over the picture.
///
/// QC runs on its own queue with its own OpenGL context; results arrive one
/// frame late, which is invisible at 30 fps.
final class QCProgram: EffectProgram {
    let url: URL
    let isFilter: Bool
    let params: [ParamDescriptor]
    let portTypes: [String: String]
    let name: String
    let summary: String

    static let protocolFilter = "com.apple.QuartzComposer.protocol.image-filter"

    init(url: URL) throws {
        self.url = url
        guard let comp = QCComposition(file: url.path) else { throw PluginError.invalidHeader("cannot open composition") }
        isFilter = (comp.protocols() ?? []).contains { ($0 as? String) == QCProgram.protocolFilter }
        let attrs = comp.attributes() as? [String: Any] ?? [:]
        name = attrs[QCCompositionAttributeNameKey] as? String ?? ParamDescriptor.prettify(url.deletingPathExtension().lastPathComponent)
        summary = attrs[QCCompositionAttributeDescriptionKey] as? String ?? ""
        var ps: [ParamDescriptor] = []
        var types: [String: String] = [:]
        for case let key as String in comp.inputKeys() ?? [] where !key.hasPrefix("_protocolInput") {
            guard let a = attrs[key] as? [String: Any], let type = a[QCPortAttributeTypeKey] as? String else { continue }
            types[key] = type
            let label = a[QCPortAttributeNameKey] as? String ?? ParamDescriptor.prettify(key)
            let dflt = a[QCPortAttributeDefaultValueKey]
            var d: ParamDescriptor
            switch type {
            case QCPortTypeNumber:
                let v = (dflt as? NSNumber)?.doubleValue ?? 0
                let mn = (a[QCPortAttributeMinimumValueKey] as? NSNumber)?.doubleValue
                let mx = (a[QCPortAttributeMaximumValueKey] as? NSNumber)?.doubleValue
                d = ParamDescriptor(name: key, label: label, type: .float, defaultValue: .float(v),
                                    min: mn ?? min(0, v), max: mx ?? max(1, abs(v) * 2))
            case QCPortTypeIndex:
                let v = (dflt as? NSNumber)?.intValue ?? 0
                d = ParamDescriptor(name: key, label: label, type: .long, defaultValue: .int(v))
                if let items = a[QCPortAttributeMenuItemsKey] as? [String] {
                    d.labels = items
                    d.values = Array(0..<items.count)
                } else {
                    let mx = (a[QCPortAttributeMaximumValueKey] as? NSNumber)?.intValue ?? max(10, v)
                    d.values = Array(0...max(0, mx))
                    d.labels = d.values.map(String.init)
                }
            case QCPortTypeBoolean:
                d = ParamDescriptor(name: key, label: label, type: .bool, defaultValue: .bool((dflt as? NSNumber)?.boolValue ?? false))
            case QCPortTypeString:
                d = ParamDescriptor(name: key, label: label, type: .text, defaultValue: .string(dflt as? String ?? ""))
            case QCPortTypeColor:
                var c: [Double] = [1, 1, 1, 1]
                if let col = (dflt as AnyObject as? NSColor)?.usingColorSpace(NSColorSpace.sRGB) {
                    c = [col.redComponent, col.greenComponent, col.blueComponent, col.alphaComponent].map(Double.init)
                } else if let o = dflt, CFGetTypeID(o as CFTypeRef) == CGColor.typeID, let comps = (o as! CGColor).components {
                    c = comps.map(Double.init) + (comps.count < 4 ? [1] : [])
                }
                d = ParamDescriptor(name: key, label: label, type: .color, defaultValue: .color(c))
            case QCPortTypeImage:
                d = ParamDescriptor(name: key, label: label, type: .image, defaultValue: .string(""))
            default:
                continue   // structures etc. aren't exposed
            }
            ps.append(d)
        }
        params = ps
        portTypes = types
    }

    func prepare(metal: MetalContext) throws {}

    func makeRuntime(descriptor: EffectDescriptor, metal: MetalContext) throws -> EffectRuntime {
        QCRuntime(descriptor: descriptor, program: self, metal: metal)
    }
}

final class QCRuntime: EffectRuntime {
    let descriptor: EffectDescriptor
    let program: QCProgram
    let metal: MetalContext
    private let queue = DispatchQueue(label: "dev.camtwizzle.qc", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var latest: CVPixelBuffer?            // filter output (ARGB) or overlay surface (BGRA)
    private var latestIsOverlay = false
    private var startTime: Double?
    private var failed: String?

    // Owned by `queue`:
    private var renderer: QCRenderer?
    private var cgl: CGLContextObj?
    private var pixelFormat: CGLPixelFormatObj?
    private var fbo: GLuint = 0
    private var depth: GLuint = 0
    private var overlayBuffers: [CVPixelBuffer] = []
    private var overlayTextures: [GLuint] = []
    private var overlayIndex = 0
    private var fboSize = (0, 0)
    private var inputPool: CVPixelBufferPool?
    private var inputPoolSize = (0, 0)
    private var emptyFrames = 0

    init(descriptor: EffectDescriptor, program: QCProgram, metal: MetalContext) {
        self.descriptor = descriptor
        self.program = program
        self.metal = metal
    }

    deinit {
        let r = renderer, c = cgl, pf = pixelFormat
        queue.async {
            _ = r
            if let c { CGLDestroyContext(c) }
            if let pf { CGLReleasePixelFormat(pf) }
        }
    }

    func reset() {
        queue.async { self.renderer = nil }
        startTime = nil
    }

    func render(input: MTLTexture, params: [String: ParamValue], ctx: FrameContext) throws -> EffectOutput {
        if let failed { throw PluginError.compile(failed) }
        let resolved = descriptor.resolve(params)
        if startTime == nil { startTime = ctx.time }
        let localTime = ctx.time - (startTime ?? ctx.time)
        let w = input.width, h = input.height

        // 1. Kick off QC for this frame (if the previous one is done).
        lock.lock()
        let canStart = !busy
        if canStart { busy = true }
        let current = latest
        let currentIsOverlay = latestIsOverlay
        lock.unlock()

        if canStart {
            var inputPB: CVPixelBuffer?
            if program.isFilter {
                if inputPool == nil || inputPoolSize != (w, h) {
                    inputPool = TwizzleEngine.SceneOutputState.makePool(width: w, height: h)
                    inputPoolSize = (w, h)
                }
                if let pool = inputPool { CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &inputPB) }
                if let pb = inputPB, let (tex, cvt) = metal.texture(from: pb) {
                    metal.encodeInternal("twz_copy", cb: ctx.commandBuffer, target: tex, textures: [input], uniforms: [SIMD4(1, 0, 0, 0)])
                    ctx.retain(cvt)
                }
            }
            let pb = inputPB
            ctx.commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.renderQC(input: pb, width: w, height: h, params: resolved, time: localTime) }
            }
        }

        // 2. Output whatever QC produced most recently.
        guard let pb = current else { return EffectOutput(texture: input, pooled: false) }
        if !currentIsOverlay {
            // QC's output format depends on the composition: usually 32ARGB, sometimes BGRA/RGBA.
            let fmt = CVPixelBufferGetPixelFormatType(pb)
            let mtlFormat: MTLPixelFormat = fmt == kCVPixelFormatType_32RGBA ? .rgba8Unorm : .bgra8Unorm
            guard let (raw, cvt) = metal.texture(from: pb, format: mtlFormat) else { return EffectOutput(texture: input, pooled: false) }
            ctx.retain(cvt); ctx.retain(pb)
            var view = raw
            if fmt == kCVPixelFormatType_32ARGB {
                view = raw.makeTextureView(pixelFormat: .bgra8Unorm, textureType: .type2D, levels: 0..<1, slices: 0..<1,
                                           swizzle: MTLTextureSwizzleChannels(red: .green, green: .red, blue: .alpha, alpha: .blue)) ?? raw
            }
            let out = metal.pool.acquire(width: w, height: h, format: metal.workingFormat)
            metal.encodeInternal("twz_copy", cb: ctx.commandBuffer, target: out, textures: [view], uniforms: [SIMD4(1, 0, 0, 0)])
            return EffectOutput(texture: out, pooled: true)
        } else {
            guard let (ov, cvt) = metal.texture(from: pb, format: .bgra8Unorm) else { return EffectOutput(texture: input, pooled: false) }
            ctx.retain(cvt); ctx.retain(pb)
            let out = metal.pool.acquire(width: w, height: h, format: metal.workingFormat)
            metal.encodeInternal("twz_over_flipped", cb: ctx.commandBuffer, target: out, textures: [input, ov])
            return EffectOutput(texture: out, pooled: true)
        }
    }

    // MARK: QC side (on `queue`)

    private func setupContext() -> Bool {
        if cgl != nil { return true }
        let attrs: [CGLPixelFormatAttribute] = [kCGLPFAAccelerated, kCGLPFAAllowOfflineRenderers, kCGLPFAColorSize, CGLPixelFormatAttribute(24),
                                                kCGLPFAAlphaSize, CGLPixelFormatAttribute(8), kCGLPFADepthSize, CGLPixelFormatAttribute(24),
                                                CGLPixelFormatAttribute(0)]
        var pf: CGLPixelFormatObj?
        var n: GLint = 0
        guard CGLChoosePixelFormat(attrs, &pf, &n) == kCGLNoError, let pf else { return false }
        var c: CGLContextObj?
        guard CGLCreateContext(pf, nil, &c) == kCGLNoError, let c else { return false }
        pixelFormat = pf
        cgl = c
        return true
    }

    private func ensureFBO(width: Int, height: Int) {
        guard fboSize != (width, height) else { return }
        if fbo != 0 { glDeleteFramebuffersEXT(1, &fbo) }
        if depth != 0 { glDeleteRenderbuffersEXT(1, &depth) }
        if !overlayTextures.isEmpty { glDeleteTextures(GLsizei(overlayTextures.count), overlayTextures) }
        overlayTextures = []
        overlayBuffers = []
        glGenFramebuffersEXT(1, &fbo)
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), fbo)
        glGenRenderbuffersEXT(1, &depth)
        glBindRenderbufferEXT(GLenum(GL_RENDERBUFFER_EXT), depth)
        glRenderbufferStorageEXT(GLenum(GL_RENDERBUFFER_EXT), GLenum(GL_DEPTH_COMPONENT24), GLsizei(width), GLsizei(height))
        glFramebufferRenderbufferEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_DEPTH_ATTACHMENT_EXT), GLenum(GL_RENDERBUFFER_EXT), depth)
        // Triple-buffered IOSurface color targets shared with Metal.
        for _ in 0..<3 {
            var pb: CVPixelBuffer?
            let a: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any], kCVPixelBufferMetalCompatibilityKey as String: true]
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, a as CFDictionary, &pb)
            guard let pb, let surf = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { continue }
            var tex: GLuint = 0
            glGenTextures(1, &tex)
            glBindTexture(GLenum(GL_TEXTURE_RECTANGLE_ARB), tex)
            CGLTexImageIOSurface2D(cgl!, GLenum(GL_TEXTURE_RECTANGLE_ARB), GLenum(GL_RGBA), GLsizei(width), GLsizei(height),
                                   GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), surf, 0)
            overlayBuffers.append(pb)
            overlayTextures.append(tex)
        }
        fboSize = (width, height)
    }

    private func renderQC(input: CVPixelBuffer?, width: Int, height: Int, params: [String: ParamValue], time: Double) {
        defer { lock.lock(); busy = false; lock.unlock() }
        guard setupContext(), let cgl else { failed = "Couldn't create an OpenGL context for Quartz Composer"; return }
        CGLSetCurrentContext(cgl)
        defer { CGLSetCurrentContext(nil) }
        ensureFBO(width: width, height: height)
        if renderer == nil {
            guard let comp = QCComposition(file: program.url.path),
                  let r = QCRenderer(cglContext: cgl, pixelFormat: pixelFormat!, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, composition: comp) else {
                failed = "Quartz Composer couldn't load \(program.url.lastPathComponent)"
                return
            }
            renderer = r
        }
        guard let r = renderer else { return }
        // Parameters
        for p in descriptor.params {
            guard let v = params[p.name] else { continue }
            let value: Any?
            switch p.type {
            case .float: value = NSNumber(value: v.asDouble)
            case .long: value = NSNumber(value: v.asInt)
            case .bool, .event: value = NSNumber(value: v.asBool)
            case .text: value = TextTokens.expand(v.asString, localTime: time)
            case .color:
                let c = v.asColor
                value = CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
            case .image: value = v.asString.isEmpty ? nil : NSImage(contentsOfFile: (v.asString as NSString).expandingTildeInPath)
            default: value = nil
            }
            if let value { r.setValue(value, forInputKey: p.name) }
        }
        if let input { r.setValue(input, forInputKey: "_protocolInput_Image") }
        if (r.inputKeys() as? [String] ?? []).contains("_protocolInput_PreviewMode") { r.setValue(false, forInputKey: "_protocolInput_PreviewMode") }

        if program.isFilter {
            glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), fbo)
            if let tex = overlayTextures.first {
                glFramebufferTexture2DEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_COLOR_ATTACHMENT0_EXT), GLenum(GL_TEXTURE_RECTANGLE_ARB), tex, 0)
            }
            glViewport(0, 0, GLsizei(width), GLsizei(height))
            r.render(atTime: time, arguments: nil)
            let out = r.value(forOutputKey: "_protocolOutput_Image", ofType: "CVPixelBuffer")
            glFlush()
            if let o = out, CFGetTypeID(o as CFTypeRef) == CVPixelBufferGetTypeID() {
                let pb = o as! CVPixelBuffer
                lock.lock(); latest = pb; latestIsOverlay = false; lock.unlock()
                emptyFrames = 0
            } else {
                emptyFrames += 1
                if emptyFrames == 90 {
                    TwzLog.warn("\(program.url.lastPathComponent): composition produces no image (it may rely on CamTwist-only patches or old Core Image kernels)")
                }
            }
        } else {
            guard !overlayTextures.isEmpty else { return }
            overlayIndex = (overlayIndex + 1) % overlayTextures.count
            glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), fbo)
            glFramebufferTexture2DEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_COLOR_ATTACHMENT0_EXT), GLenum(GL_TEXTURE_RECTANGLE_ARB), overlayTextures[overlayIndex], 0)
            glViewport(0, 0, GLsizei(width), GLsizei(height))
            glClearColor(0, 0, 0, 0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
            r.render(atTime: time, arguments: nil)
            glFlush()
            lock.lock(); latest = overlayBuffers[overlayIndex]; latestIsOverlay = true; lock.unlock()
        }
    }
}
