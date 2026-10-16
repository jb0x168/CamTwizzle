import AppKit
import CoreText
import Foundation
import ImageIO
import Metal

/// Shared, cached GPU resources for plugins: glyph atlases, rendered text and image files.
public final class ResourceCache {
    let device: MTLDevice
    private var glyphs: [String: MTLTexture] = [:]
    private var texts: [String: (tex: MTLTexture, used: Int)] = [:]
    private var images: [String: (tex: MTLTexture, mtime: Date?)] = [:]
    private var clock = 0
    private let lock = NSLock()

    public init(device: MTLDevice) { self.device = device }

    // MARK: Glyph atlas

    /// White glyphs on transparent, one per cell in a horizontal strip.
    public func glyphAtlas(chars: [String], font: String, size: Double) -> MTLTexture {
        let key = "\(font)|\(size)|\(chars.joined(separator: "\u{1}"))"
        lock.lock(); defer { lock.unlock() }
        if let t = glyphs[key] { return t }
        let ctFont = ResourceCache.font(named: font, size: size)
        let ascent = CTFontGetAscent(ctFont), descent = CTFontGetDescent(ctFont)
        var maxAdvance: CGFloat = 0
        let lines = chars.map { ch -> CTLine in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: ch, attributes: [
                .font: ctFont, .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            ]))
            maxAdvance = max(maxAdvance, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            return line
        }
        let cellW = Int(ceil(max(maxAdvance, size * 0.5)))
        let cellH = Int(ceil(ascent + descent))
        let w = max(1, cellW * chars.count), h = max(1, cellH)
        let tex = renderBitmap(width: w, height: h) { ctx in
            for (i, line) in lines.enumerated() {
                let adv = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                ctx.textPosition = CGPoint(x: CGFloat(i * cellW) + (CGFloat(cellW) - adv) / 2, y: descent)
                CTLineDraw(line, ctx)
            }
        }
        glyphs[key] = tex
        return tex
    }

    // MARK: Text

    /// Render (possibly multi-line, centered) white text with a little padding.
    public func textTexture(_ string: String, font: String, size: Double) -> MTLTexture {
        let key = "\(font)|\(size)|\(string)"
        lock.lock(); defer { lock.unlock() }
        clock += 1
        if let t = texts[key] {
            texts[key] = (t.tex, clock)
            return t.tex
        }
        let ctFont = ResourceCache.font(named: font, size: size)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let text = string.isEmpty ? " " : string
        let attr = NSAttributedString(string: text, attributes: [
            .font: ctFont, .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), .paragraphStyle: para,
        ])
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: 8000, height: 8000), nil)
        let pad = ceil(size * 0.15)
        let w = Int(ceil(fit.width + pad * 2)), h = Int(ceil(fit.height + pad * 2))
        let tex = renderBitmap(width: w, height: h) { ctx in
            let path = CGPath(rect: CGRect(x: pad, y: pad, width: ceil(fit.width) + 1, height: ceil(fit.height)), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
        }
        texts[key] = (tex, clock)
        if texts.count > 48 {
            // evict least recently used
            for k in texts.sorted(by: { $0.value.used < $1.value.used }).prefix(16).map(\.key) { texts.removeValue(forKey: k) }
        }
        return tex
    }

    // MARK: Images

    public func imageTexture(path: String, relativeTo base: URL?) -> MTLTexture? {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if !path.hasPrefix("/") && !path.hasPrefix("~"), let base { url = base.appendingPathComponent(path) }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        lock.lock(); defer { lock.unlock() }
        if let c = images[url.path], c.mtime == mtime { return c.tex }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary)
        else { return nil }
        let tex = texture(from: img)
        images[url.path] = (tex, mtime)
        return tex
    }

    public func texture(from img: CGImage) -> MTLTexture {
        let w = img.width, h = img.height
        return renderBitmap(width: w, height: h, flipped: false) { ctx in
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    // MARK: Helpers

    static func font(named name: String, size: Double) -> CTFont {
        let f = CTFontCreateWithName(name as CFString, CGFloat(size), nil)
        return f
    }

    /// Draw into a premultiplied RGBA bitmap (CG coordinates, y up) and upload as an rgba8 texture.
    func renderBitmap(width: Int, height: Int, flipped: Bool = false, draw: (CGContext) -> Void) -> MTLTexture {
        let w = max(1, width), h = max(1, height)
        let bpr = w * 4
        var data = [UInt8](repeating: 0, count: bpr * h)
        data.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setShouldAntialias(true)
            ctx.setShouldSmoothFonts(false)
            draw(ctx)
        }
        // CGBitmapContext memory is top row first, matching Metal's top-left origin.
        // Un-premultiply so shaders see straight alpha.
        for i in stride(from: 0, to: data.count, by: 4) {
            let a = data[i + 3]
            if a > 0 && a < 255 {
                let af = Float(a) / 255
                data[i] = UInt8(min(255, Float(data[i]) / af))
                data[i + 1] = UInt8(min(255, Float(data[i + 1]) / af))
                data[i + 2] = UInt8(min(255, Float(data[i + 2]) / af))
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        let tex = device.makeTexture(descriptor: d)!
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: bpr)
        return tex
    }
}

/// Expands live tokens in text parameters:
/// `{time}` `{time:HH:mm}` `{date}` `{date:EEEE d MMMM}` `{elapsed}` `{countdown:5:00}` `{fps}`.
public enum TextTokens {
    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static func formatter(_ pattern: String) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let f = formatters[pattern] { return f }
        let f = DateFormatter()
        f.dateFormat = pattern
        formatters[pattern] = f
        return f
    }

    static func parseDuration(_ s: String) -> Double {
        let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    static func formatDuration(_ secs: Double) -> String {
        let s = max(0, Int(secs.rounded(.down)))
        let h = s / 3600, m = (s / 60) % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    public static func expand(_ text: String, localTime: Double) -> String {
        guard text.contains("{") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "{", let close = text[i...].firstIndex(of: "}") {
                let token = String(text[text.index(after: i)..<close])
                let (name, arg): (String, String?) = {
                    if let c = token.firstIndex(of: ":") { return (String(token[..<c]), String(token[token.index(after: c)...])) }
                    return (token, nil)
                }()
                let now = Date()
                switch name.lowercased() {
                case "time": out += formatter(arg ?? "HH:mm:ss").string(from: now)
                case "date": out += formatter(arg ?? "EEE d MMM yyyy").string(from: now)
                case "elapsed": out += formatDuration(localTime)
                case "countdown": out += formatDuration(parseDuration(arg ?? "5:00") - localTime)
                case "until":
                    // {until:HH:mm} counts down to the next occurrence of a wall-clock time
                    let parts = (arg ?? "12:00").split(separator: ":").compactMap { Int($0) }
                    var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
                    comps.hour = parts.first ?? 12
                    comps.minute = parts.count > 1 ? parts[1] : 0
                    comps.second = parts.count > 2 ? parts[2] : 0
                    var target = Calendar.current.date(from: comps) ?? now
                    if target < now { target = target.addingTimeInterval(86400) }
                    out += formatDuration(target.timeIntervalSince(now))
                default: out += "{\(token)}"
                }
                i = text.index(after: close)
            } else {
                out.append(text[i])
                i = text.index(after: i)
            }
        }
        return out
    }
}
