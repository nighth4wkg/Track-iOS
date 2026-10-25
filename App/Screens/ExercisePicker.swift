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

/// Adding an exercise, as the PWA's picker: a search, the muscle filter, a name typed that isn't in the library (to
/// add as it is), your 3 most recent, then the library or the matches, 30 at a time. Adding keeps it open for the
/// next, each added one ticked. Given `replacing`, it's "Swap exercise": what's picked takes that one's place.
struct ExercisePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var group = "All"
    @State private var shown = Self.page
    @State private var added: [String] = []
    /// Each name's muscles, worked out once per opening (a reference, so filling it redraws nothing).
    @State private var groups = Groups()
    var replacing: String? = nil
    let onPick: (String) -> Void
    private static let page = Probe.has("-pickRows10") ? 10 : 30

    var body: some View {
        let usage = model.derived("usage") { sessions in
            sessions.reduce(into: [String: Int]()) { usage, session in for exercise in session.exercises { usage[exercise.name, default: 0] += 1 } }
        }
        let recent = model.derived("recent") { sessions in
            var seen = Set<String>()
            return sessions.sorted { ($0.finishedAt ?? 0) > ($1.finishedAt ?? 0) }.flatMap { $0.exercises.map(\.name) }
                .filter { seen.insert($0).inserted }.prefix(3).map { $0 }
        }
        let choices = model.training.settings.lifts ?? [:]
        let matches = Catalog.search(query, usage: usage)
        let results = group == "All" ? matches : matches.filter { groups.of($0, choices).contains(group) }
        let typed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.name))
        let custom = !typed.isEmpty && !matches.contains { $0.caseInsensitiveCompare(typed) == .orderedSame }
        SheetFrame(title: replacing == nil ? "Add exercise" : "Swap exercise",
                   subtitle: replacing ?? (added.isEmpty ? nil : "\(added.count) added"), tall: true) {
            Field(placeholder: "Search exercises", text: $query, label: "Search exercises", icon: "magnifyingglass",
                  submit: { if custom { pick(typed) } else if let first = results.first { pick(first) } })
                .padding(.top, Space.s3)
            Seg(label: "Muscle", options: (["All"] + LiftTable.groups).map { (value: $0, text: $0) }, value: $group, columns: 3)
                .padding(.top, Space.s3)
            if custom {
                RowCard { row(typed, choices) }.padding(.top, Space.s4)
            }
            if query.isEmpty, group == "All", !recent.isEmpty {
                Text("Recent").type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s6)
                RowCard { ForEach(recent, id: \.self) { row($0, choices) } }.padding(.top, Space.s2)
            }
            Text(query.isEmpty ? "All exercises" : count(results.count, "result")).type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s6)
            if !results.isEmpty {
                RowCard { ForEach(results.prefix(shown), id: \.self) { row($0, choices) } }.padding(.top, Space.s2)
            }
            if results.count > shown {
                Button("Show more") { shown += Self.page }.buttonStyle(SecondaryButtonStyle()).padding(.top, Space.s3)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { shown = Self.page }
        .onChange(of: group) { shown = Self.page }
        .perfHook("pick.group") { group = $0 }
        .perfHook("pick.query") { query = $0 }
        .perfHook("pick.add") { pick($0) }
        // Filled once the sheet is up, so neither the opening nor the first filter tap waits for it.
        .task {
            try? await Task.sleep(for: .seconds(Motion.screen))
            for name in Catalog.names { _ = groups.of(name, choices) }
        }
    }

    /// The name over its muscle ("Added" in green once added), and + (✓ once added).
    private func row(_ name: String, _ choices: [String: String]) -> some View {
        let isAdded = added.contains(name)
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                Text(isAdded ? "Added" : groups.of(name, choices).first ?? "Exercise").type(.t14)
                    .foregroundStyle(isAdded ? Palette.accent : Palette.muted)
            }
            Spacer(minLength: 0)
            Button { pick(name) } label: {
                Image(systemName: isAdded ? "checkmark" : "plus").font(.system(size: IconSize.medium, weight: .bold))
                    .foregroundStyle(isAdded ? Palette.primaryText : Palette.text)
                    .frame(width: Size.control, height: Size.control)
                    .modifier(ProbeRaised(on: !Probe.has("-pickFlat"), surface: isAdded ? .green : .control))
                    .modifier(ProbeSymbol(on: !Probe.has("-pickNoSymbol")))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(replacing == nil ? "Add" : "Use") \(name)")
            .sensoryFeedback(.impact(weight: .light), trigger: isAdded) { _, now in now }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(minHeight: Size.row)
    }

    private func pick(_ name: String) {
        let name = String(name.prefix(Limits.name))
        onPick(name)
        if replacing != nil { dismiss() } else { withAnimation(.smooth(duration: Motion.fast)) { added.append(name) } }
    }
}

/// Names' muscles, looked up once each.
private final class Groups {
    private var map: [String: [String]] = [:]

    func of(_ name: String, _ choices: [String: String]) -> [String] {
        if let known = map[name] { return known }
        let found = LiftTable.ranking(for: name, choices: choices)?.groups ?? []
        map[name] = found
        return found
    }
}

// Temporary: picker ablation switches.
private struct ProbeRaised: ViewModifier {
    let on: Bool; let surface: Surface
    func body(content: Content) -> some View {
        if on { content.raised(surface, .inner) } else { content.background(Palette.input, in: Corner.inner.shape) }
    }
}
private struct ProbeSymbol: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.contentTransition(.symbolEffect(.replace)) } else { content } }
}
