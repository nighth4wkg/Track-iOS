import SwiftUI
import TrackCore

/// "New best" over what it beat: for a moment it takes the exercise header's place (the website's too), so it
/// covers nothing half-way and never the numbers being typed. It never takes taps.
struct RecordNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill").font(.subheadline.weight(.bold)).foregroundStyle(Palette.record)
                .frame(width: 32, height: 32).background(Circle().fill(Palette.record.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text("New best").font(.subheadline.weight(.bold)).foregroundStyle(Palette.record)
                Text(text).font(.footnote.weight(.medium)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.dialog))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.record.opacity(0.45), lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true) // announced once instead (SetRow)
    }

    /// The website's wording for what a best beat.
    static func describe(_ record: LiveRecord, _ set: TrainingSet, unit: TrackCore.Settings.Unit) -> String {
        let w = { (kg: Double) in "\(TrainingSet.display(kg: kg, unit: unit)) \(unit.rawValue)" }
        switch record {
        case .heaviest(let kg): return "Heaviest ever · up from \(w(kg))"
        case .weightForReps(let kg): return "Heaviest for \(set.reps ?? 0) reps · up from \(w(kg))"
        case .repsForWeight(let reps): return "Most reps at \(w(set.kg ?? 0)) · up from \(reps)"
        case .repsAtOrAbove(let reps): return "More reps than any heavier set · was \(reps)"
        }
    }
}
