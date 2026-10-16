import AppKit
import SwiftUI
import TwizzleCore
import UniformTypeIdentifiers

/// Auto-generated control for an effect parameter.
struct ParamControl: View {
    @Environment(AppModel.self) private var model
    let param: ParamDescriptor
    @Binding var value: ParamValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            if let help = param.help {
                Text(help).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder var control: some View {
        switch param.type {
        case .float:
            FloatParam(label: param.label, value: Binding(get: { value.asDouble }, set: { value = .float($0) }),
                       range: (param.min ?? 0)...max((param.max ?? 1), (param.min ?? 0) + 1e-6))
        case .long:
            if !param.values.isEmpty {
                let picker = Picker(param.label, selection: Binding(get: { value.asInt }, set: { value = .int($0) })) {
                    ForEach(Array(zip(param.values, param.labels)), id: \.0) { v, l in Text(l).tag(v) }
                }
                if param.values.count <= 3 && param.labels.allSatisfy({ $0.count < 12 }) {
                    picker.pickerStyle(.segmented)
                } else {
                    picker.pickerStyle(.menu)
                }
            } else {
                Stepper("\(param.label): \(value.asInt)", value: Binding(get: { value.asInt }, set: { value = .int($0) }),
                        in: Int(param.min ?? 0)...Int(param.max ?? 100))
            }
        case .bool:
            Toggle(param.label, isOn: Binding(get: { value.asBool }, set: { value = .bool($0) }))
        case .event:
            Button(param.label) {
                value = .bool(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { value = .bool(false) }
            }
        case .color:
            ColorPicker(param.label, selection: Binding(
                get: {
                    let c = value.asColor
                    return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3])
                },
                set: { newColor in
                    let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .white
                    value = .color([Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent)])
                }
            ), supportsOpacity: true)
        case .point2D:
            VStack(alignment: .leading, spacing: 2) {
                Text(param.label)
                SliderRow(label: "X", value: Binding(get: { value.asPoint[0] }, set: { value = .point([$0, value.asPoint[1]]) }), range: 0...1)
                SliderRow(label: "Y", value: Binding(get: { value.asPoint[1] }, set: { value = .point([value.asPoint[0], $0]) }), range: 0...1)
            }
        case .text:
            VStack(alignment: .leading, spacing: 2) {
                Text(param.label)
                TextField(param.label, text: Binding(get: { value.asString }, set: { value = .string($0) }), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Text("Live tokens: {time} {time:HH:mm} {date} {elapsed} {countdown:5:00} {until:17:30}")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        case .image:
            HStack {
                Text(param.label)
                Spacer()
                Text(value.asString.isEmpty ? "None" : URL(fileURLWithPath: value.asString).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button("Choose…") {
                    let p = NSOpenPanel()
                    p.allowedContentTypes = [.image]
                    if p.runModal() == .OK, let url = p.url { value = .string(url.path) }
                }
                if !value.asString.isEmpty { Button { value = .string("") } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless) }
            }
        case .source:
            Picker(param.label, selection: Binding(get: { value.asString }, set: { value = .string($0) })) {
                Text("None").tag("")
                ForEach(model.availableSources, id: \.key) { s in
                    Label(s.name, systemImage: icon(for: s.kind)).tag(s.key)
                }
            }
        }
    }
}

struct FloatParam: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                TextField("", text: $text)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if let v = Double(text) { value = v } }
                    .onAppear { text = format(value) }
                    .onChange(of: value) { _, v in text = format(v) }
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = $0 }), in: range)
        }
    }

    func format(_ v: Double) -> String {
        let span = range.upperBound - range.lowerBound
        if span >= 100 { return String(format: "%.0f", v) }
        if span >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.3f", v)
    }
}
