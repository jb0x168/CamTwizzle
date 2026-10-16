import SwiftUI
import TwizzleCore

/// Searchable catalogue of effects, grouped by category.
struct EffectBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category: String? = nil
    @State private var selected: EffectDescriptor?

    static let libraryCategories = ["ISF", "Quartz Composer", "My Effects"]

    /// Native categories first (CamTwist on top), then the plugin libraries.
    var categories: [String] {
        var c: [String] = []
        for e in model.effects where e.kind != .quartz && e.url.pathExtension.lowercased() != "fs" {
            for cat in e.categories where !c.contains(cat) { c.append(cat) }
        }
        c.sort { a, b in a == "CamTwist" ? true : (b == "CamTwist" ? false : a < b) }
        for lib in EffectBrowser.libraryCategories where model.effects.contains(where: { inCategory($0, lib) }) { c.append(lib) }
        return c
    }

    func inCategory(_ e: EffectDescriptor, _ c: String) -> Bool {
        switch c {
        case "My Effects": return !e.isBuiltIn
        case "ISF": return e.url.pathExtension.lowercased() == "fs"
        case "Quartz Composer": return e.kind == .quartz
        default:
            // Library effects only appear under their library entry.
            return e.categories.contains(c) && e.kind != .quartz && e.url.pathExtension.lowercased() != "fs"
        }
    }

    var filtered: [EffectDescriptor] {
        model.effects.filter { e in
            (category == nil || inCategory(e, category!)) &&
            (search.isEmpty || e.name.localizedCaseInsensitiveContains(search) || e.summary.localizedCaseInsensitiveContains(search)
             || e.categories.contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(targetTitle).font(.title3.bold())
                Spacer()
                TextField("Search effects", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(14)
            Divider()
            HSplitView {
                List(selection: $category) {
                    Text("All Effects (\(model.effects.count))").tag(String?.none)
                    ForEach(categories, id: \.self) { c in
                        Text("\(c) (\(model.effects.filter { inCategory($0, c) }.count))").tag(String?.some(c))
                    }
                }
                .frame(minWidth: 170, maxWidth: 220)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        ForEach(filtered) { e in
                            EffectCard(effect: e, selected: selected === e)
                                .onTapGesture { selected = e }
                                .onTapGesture(count: 2) { add(e) }
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 420)
            }
            Divider()
            HStack {
                if let s = selected {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.headline)
                        Text(s.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Button("New Effect…") { model.newEffectFromTemplate() }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { if let s = selected { add(s) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
            .padding(14)
        }
        .frame(width: 860, height: 600)
        .onAppear { if selected == nil { selected = filtered.first } }
    }

    var targetTitle: String {
        if case let .layer(id) = model.browserTarget, let l = model.scene?.layers.first(where: { $0.id == id }) {
            return "Add Effect to “\(l.source.name)”"
        }
        return "Add Effect"
    }

    func add(_ e: EffectDescriptor) {
        model.addEffect(e, to: model.browserTarget)
        dismiss()
    }
}

struct EffectCard: View {
    let effect: EffectDescriptor
    let selected: Bool

    static var thumbCache: [String: NSImage] = [:]

    var thumbnail: NSImage? {
        if let t = EffectCard.thumbCache[effect.id] { return t }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Thumbnails/\(effect.id).jpg"),
              let img = NSImage(contentsOf: url) else { return nil }
        EffectCard.thumbCache[effect.id] = img
        return img
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(Image(systemName: effect.kind == .quartz ? "q.circle" : "wand.and.stars").font(.title).foregroundStyle(.secondary))
            }
            HStack {
                Image(systemName: effect.kind == .graph ? "point.3.filled.connected.trianglepath.dotted" : (effect.kind == .quartz ? "q.circle" : "wand.and.stars"))
                    .foregroundStyle(.purple)
                Text(effect.name).font(.headline).lineLimit(1)
                Spacer()
                if effect.wantsFace { Image(systemName: "face.smiling").foregroundStyle(.secondary) }
                if effect.wantsMask { Image(systemName: "person.crop.rectangle").foregroundStyle(.secondary) }
                if !effect.isBuiltIn { Image(systemName: "person.fill").foregroundStyle(.orange).help("My effect") }
            }
            Text(effect.summary.isEmpty ? effect.primaryCategory : effect.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Text(effect.categories.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2)))
        .contentShape(Rectangle())
    }
}
