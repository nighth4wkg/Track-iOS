import SwiftUI
import TrackCore

/// Home, as the PWA's: the brand and Settings, today's date over "Ready to train" (or "Keep going"), the week ring
/// with what's next (or the workout in progress), your splits (tap one for its page, swipe it left for its delete,
/// Arrange to move them), then this week's volume and the next achievement.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var open: String?
    @State private var arranging = false
    @State private var naming = false

    var body: some View {
        let training = model.training
        let now = nowMillis()
        Page(title: training.active == nil ? "Ready to train" : "Keep going",
             caption: Date.now.formatted(.gregorian.weekday(.wide).month(.abbreviated).day()), settingsOpen: $settingsOpen) {
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.loadError {
                    Label(error, systemImage: "exclamationmark.triangle").type(.t14).foregroundStyle(Palette.danger).padding(.bottom, Space.s4)
                }
                UpNextCard(training: training, now: now, create: create)
                if !training.splits.isEmpty { splits(training).padding(.top, Space.s6) }
                HomeTiles(training: training, now: now).padding(.top, Space.s3)
            }
            .navigationDestination(item: $open) { SplitPage(splitId: $0) }
            .onChange(of: open != nil) { _, up in model.setPushed(.home, up) }
        }
        .sensoryFeedback(.selection, trigger: training.splits.map(\.id))
        .onChange(of: training.splits.count) { _, count in if count < 2 { arranging = false } }
        .sheet(isPresented: $naming) {
            NewSplitSheet { split in
                model.update { $0.splits.append(split) }
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.sheetAway) { open = split.id }
            }
        }
    }

    private func splits(_ training: Training) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Your splits").type(.t20).foregroundStyle(Palette.text)
                Spacer()
                HStack(spacing: Space.s1) {
                    if training.splits.count > 1 {
                        RoundButton(icon: arranging ? "checkmark" : "arrow.up.arrow.down", label: arranging ? "Done arranging splits" : "Arrange splits") {
                            withAnimation(.smooth(duration: Motion.standard)) { arranging.toggle() }
                        }
                    }
                    if !arranging { RoundButton(icon: "plus", label: "New split", action: create) }
                }
            }
            if arranging {
                ArrangeList(items: training.splits, name: \.name, onMove: { from, to in model.update { $0.splits = $0.splits.moved(from, to: to) } }) { split in
                    SplitLine(split: split)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(training.splits) { split in
                        SplitCard(split: split, next: training.active == nil && training.nextSplit?.split.id == split.id) { open = split.id }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func create() { naming = true }
}

/// A split's tile, name and size, as a row on Home and in Arrange.
private struct SplitLine: View {
    let split: Split

    var body: some View {
        HStack(spacing: Space.s3) {
            TrackMark(size: IconSize.medium).foregroundStyle(Palette.text)
                .frame(width: Size.tile, height: Size.tile).raised(.control, .inner)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(split.name).type(.t16).foregroundStyle(Palette.text)
                Text(split.exercises.isEmpty ? "Tap to add exercises" : split.summary).type(.t14).foregroundStyle(Palette.muted)
            }
        }
    }
}

/// One split on its own card: tap it for its page; swipe it left (or hold it) and its end becomes a red trash, which
/// asks first. The one up next says so.
private struct SplitCard: View {
    @Environment(AppModel.self) private var model
    let split: Split
    let next: Bool
    let open: () -> Void
    @State private var armed = false

    var body: some View {
        HStack(spacing: 0) {
            Button { if armed { armed = false } else { open() } } label: {
                HStack(spacing: Space.s3) {
                    SplitLine(split: split)
                    Spacer(minLength: 0)
                    if next && !armed { Badge(text: "Next").transition(.opacity) }
                }
                .padding(Space.s4)
                .frame(minHeight: Size.control + Space.s4 * 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle()) // as the PWA's split row: no shrink
            if armed {
                RoundButton(icon: "trash", label: "Delete \(split.name)", tint: Palette.danger) { armed = false; model.deleteSplit(split) }
                    .padding(.trailing, Space.s4)
                    .transition(.opacity)
            }
        }
        .raised()
        .swipeToArm($armed)
    }
}

/// New split, as the PWA's: a name and Create, or one of the starter templates.
private struct NewSplitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let created: (Split) -> Void
    @State private var name = ""

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let problem = trimmed.isEmpty ? nil : model.splitNameTaken(trimmed)
        let save = { if !trimmed.isEmpty, problem == nil { create(Split(name: trimmed)) } }
        SheetFrame(title: "New split", closeLabel: "Cancel") {
            VStack(alignment: .leading, spacing: Space.s4) {
                Field(placeholder: "Name, like Push A", text: $name, label: "Split name", submit: save)
                if let problem { Text(problem).type(.t14).foregroundStyle(Palette.danger) }
                Button("Create", action: save).buttonStyle(PrimaryButtonStyle()).disabled(trimmed.isEmpty || problem != nil)
            }
            .padding(.top, Space.s3)
            Text("Or start from a template").type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s6)
            VStack(spacing: 0) {
                ForEach(SplitTemplate.all) { template in
                    Button { create(template.makeSplit()) } label: {
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(template.name).type(.t16).foregroundStyle(Palette.text)
                                Text(template.exercises.joined(separator: ", ")).type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.muted)
                        }
                        .padding(Space.s4)
                        .frame(minHeight: Size.row)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .overlay(alignment: .top) { if template.id != SplitTemplate.all.first?.id { Palette.hairline.frame(height: 1) } }
                }
            }
            .raised()
            .padding(.top, Space.s2)
        }
    }

    private func create(_ split: Split) {
        dismiss()
        created(split)
    }
}

/// "0:42" or "1:05:09" since the start.
func elapsed(_ start: Int, _ now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince1970) - start / 1000)
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        : String(format: "%d:%02d", seconds / 60, seconds % 60)
}
