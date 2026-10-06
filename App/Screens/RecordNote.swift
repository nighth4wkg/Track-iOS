import SwiftUI
import TrackCore

/// "New best" over what it beat: for a moment it takes the exercise header's place (the website's too), so it
/// covers nothing half-way and never the numbers being typed. It never takes taps.
struct RecordNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill").font(.title3).foregroundStyle(Palette.record)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.record.opacity(0.16)))
                .overlay(Circle().strokeBorder(Palette.record.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text("New best").font(.callout.weight(.bold)).foregroundStyle(Palette.record)
                Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10).padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Solid, with a faint gold wash from the trophy's side and a soft lift (the website's).
        .background(LinearGradient(colors: [Palette.record.opacity(0.14), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5)))
        .background(Palette.dialog)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.record.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
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
