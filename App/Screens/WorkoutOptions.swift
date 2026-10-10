import SwiftUI
import TrackCore

/// The workout's options, as the website's: rename, switch kg ⇄ lb, start a rest, discard the workout.
struct WorkoutOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let active = model.training.active
        let split = model.training.splits.first { $0.id == active?.splitId }
        let unit = model.training.settings.unit
        // Scrolls at large text sizes, where the four options outgrow the sheet.
        ScrollView { VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Workout options").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                Spacer()
                GlassCircleButton(icon: "xmark", label: "Close") { dismiss() }.padding(.top, -6).padding(.trailing, -6)
            }
            Text(active?.name ?? "").font(.subheadline).foregroundStyle(Palette.muted).padding(.bottom, 6)
            option(split != nil ? "Rename split" : "Rename workout", "pencil") {
                dismiss()
                model.naming = Naming(title: split != nil ? "Rename split" : "Rename workout", name: active?.name ?? "",
                                      label: split != nil ? "Split name" : "Workout name", action: "Save name") { name in
                    // The split's name changes now too, not only when the workout is finished.
                    model.update { training in training.active?.name = name; if let id = split?.id { training.edit(id) { $0.name = name } } }
                }
            }
            option(unit == .kg ? "Use pounds (lb)" : "Use kilograms (kg)", "arrow.left.arrow.right") {
                model.update { $0.settings.unit = unit == .kg ? .lb : .kg }
            }
            option("Start rest timer", "timer") { model.startRest(); dismiss() }
            option("Discard workout", "trash", danger: true) { dismiss(); model.discard() }
        }
        .padding(24) }
        .scrollBounceBehavior(.basedOnSize)
        .background(Backdrop()) // the app's own backdrop, as Settings and every other sheet (not a plain grey material)
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
    }

    private func option(_ title: String, _ icon: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(danger ? Palette.dangerText : Palette.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .glass(radius: 24, fill: danger ? .clear : Palette.control, lifted: false)
        }
        .buttonStyle(PressStyle())
    }
}
