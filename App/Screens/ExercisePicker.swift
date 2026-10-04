import SwiftUI
import TrackCore

/// The exercise library: the website's catalog (exported to Resources/exercises.json by tools/export-ios.mjs).
enum Catalog {
    static let names: [String] = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url), let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return names
    }()
    /// Worked out once, so a keystroke in the search only compares.
    private static let simple = names.map(simplify)
    private static let known = Set(names.map { $0.lowercased() })

    /// Matches for a search, best first: what you use most, then names starting with the words typed, then names
    /// containing them. Case and punctuation don't matter. With no search, your exercises first, then the library.
    static func search(_ query: String, usage: [String: Int]) -> [String] {
        let words = simplify(query).split(separator: " ")
        let own = usage.keys.filter { !known.contains($0.lowercased()) }.sorted()
        let all = Array(zip(own, own.map(simplify))) + Array(zip(names, simple))
        let matches = all.enumerated().compactMap { offset, entry -> (uses: Int, starts: Bool, offset: Int, name: String)? in
            guard words.allSatisfy({ entry.1.contains($0) }) else { return nil }
            return (usage[entry.0] ?? 0, words.first.map { entry.1.hasPrefix($0) } ?? false, offset, entry.0)
        }
        return matches.sorted { a, b in a.uses != b.uses ? a.uses > b.uses : a.starts != b.starts ? a.starts : a.offset < b.offset }.map(\.name)
    }

    static func simplify(_ text: String) -> String {
        text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}

/// Adding an exercise, as the website's picker: "Add an exercise", a search, the library or the matches (with how
/// many), a + on each, more on request, and your own name when it isn't in the library.
struct ExercisePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var shown = 50
    let onPick: (String) -> Void

    var body: some View {
        let usage = model.derived("usage") { sessions in
            sessions.reduce(into: [String: Int]()) { usage, session in for exercise in session.exercises { usage[exercise.name, default: 0] += 1 } }
        }
        let results = Catalog.search(query, usage: usage)
        let typed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let custom = !typed.isEmpty && !results.contains { $0.caseInsensitiveCompare(typed) == .orderedSame }
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Find a movement or add your own.").font(.subheadline).foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField("Search exercises…", text: $query).submitLabel(.done)
                            .onSubmit { if let first = results.first { pick(first) } else if custom { pick(typed) } }
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                                .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .glass(radius: 14, fill: Palette.input, lifted: false)
                    HStack {
                        Text(query.isEmpty ? "Exercise library" : "Matches")
                        Spacer()
                        Text(results.isEmpty ? "No exercises" : "Showing \(min(shown, results.count)) of \(results.count)")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                    if results.isEmpty {
                        Text("No matching exercises.").font(.subheadline).foregroundStyle(Palette.muted).padding(.vertical, 8)
                    } else {
                        GlassList {
                            ForEach(results.prefix(shown), id: \.self) { name in
                                Button { pick(name) } label: {
                                    HStack {
                                        Text(name).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                                        Spacer()
                                        if let times = usage[name] { Text(count(times, "time")).font(.caption).foregroundStyle(Palette.muted) }
                                        Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(Palette.accent)
                                    }
                                    .frame(minHeight: 32).contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel("Add \(name)")
                            }
                        }
                        if results.count > shown {
                            Button("Show more") { shown += 50 }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    if custom {
                        Button { pick(typed) } label: { Label("Add “\(typed.prefix(50))” as your own", systemImage: "plus") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Backdrop())
            .navigationTitle("Add an exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.text) }.accessibilityLabel("Close")
                }
            }
            .onChange(of: query) { shown = 50 }
        }
    }

    private func pick(_ name: String) {
        onPick(String(name.prefix(100)))
        dismiss()
    }
}
