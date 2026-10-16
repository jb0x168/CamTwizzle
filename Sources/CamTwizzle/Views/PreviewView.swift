import AppKit
import SwiftUI

/// Hosts the engine's preview CALayer.
final class PreviewNSView: NSView {
    let host: PreviewHost

    init(host: PreviewHost) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(host.layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.layer.frame = bounds
        CATransaction.commit()
    }
}

struct PreviewView: NSViewRepresentable {
    let host: PreviewHost

    func makeNSView(context: Context) -> PreviewNSView {
        // The host layer can only live in one view; detach it from any previous one.
        host.layer.removeFromSuperlayer()
        return PreviewNSView(host: host)
    }

    func updateNSView(_ v: PreviewNSView, context: Context) {
        if v.host.layer.superlayer !== v.layer {
            v.layer?.addSublayer(v.host.layer)
            v.needsLayout = true
        }
    }
}
