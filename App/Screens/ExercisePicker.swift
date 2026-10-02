import SwiftUI
import TrackCore

/// The exercise library: the website's catalog (exported to Resources/exercises.json by tools/export-ios.mjs).
enum Catalog {
    static let names: [String] = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url), let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return names
    }()

    /// Matches for a search, best first: exercises you've done before, then names starting with the words typed, then
    /// names containing them. Case and punctuation don't matter.
    static func search(_ query: String, used: Set<String>) -> [String] {
        let words = simplify(query).split(separator: " ")
        let all = Array(used.subtracting(names)).sorted() + names
        guard !words.isEmpty else { return all.filter { used.contains($0) } + names.filter { !used.contains($0) } }
        let matches = all.filter { name in let simple = simplify(name); return words.allSatisfy { simple.contains($0) } }
        return matches.sorted { a, b in rank(a, words, used) < rank(b, words, used) }
    }

    private static func rank(_ name: String, _ words: [Substring], _ used: Set<String>) -> Int {
        (used.contains(name) ? 0 : 2) + (simplify(name).hasPrefix(words[0]) ? 0 : 1)
    }

    static func simplify(_ text: String) -> String {
        text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }
}

/// Picks an exercise to add: search the library, or add exactly what you typed.
struct ExercisePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (String) -> Void

    var body: some View {
        let used = Set(model.training.sessions.flatMap { $0.exercises.map(\.name) } + model.training.splits.flatMap { $0.exercises.map(\.name) })
        let results = Catalog.search(query, used: used)
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            List {
                if !typed.isEmpty, !results.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
                    Button { pick(typed) } label: { Label("Add “\(typed)”", systemImage: "plus") }.glassRow()
                }
                ForEach(results.prefix(80), id: \.self) { name in
                    Button { pick(name) } label: {
                        HStack {
                            Text(name).foregroundStyle(Palette.text)
                            Spacer()
                            if used.contains(name) { Chip(text: "Done before") }
                        }
                    }
                    .glassRow()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func pick(_ name: String) {
        onPick(String(name.prefix(100)))
        dismiss()
    }
}
