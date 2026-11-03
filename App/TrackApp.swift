import SwiftUI
import TrackCore

@main
struct TrackApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        RestIntent.change = { seconds in
            await MainActor.run { if seconds == 0 { model.skipRest() } else { model.shiftRest(by: seconds) } }
            await RestLive.pending?.value
        }
    }

    /// A hidden field takes the keyboard and gives it back at once, so iOS loads its keyboard before a field is tapped;
    /// skipped when a sheet or the workout is already up (a field there may be in use).
    @MainActor private static func warmKeyboard(_ model: AppModel) {
        guard let window = keyWindow, !model.workoutOpen, model.sheets.isEmpty else { return }
        let field = UITextField(frame: .zero)
        window.addSubview(field)
        UIView.performWithoutAnimation { _ = field.becomeFirstResponder(); _ = field.resignFirstResponder() }
        field.removeFromSuperview()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.mode == nil { WelcomeScreen() } else { Shell() }
            }
            .environment(model)
            .tint(Palette.accent)
            .preferredColorScheme(.dark)
            .onAppear {
                TestSeed.apply(model)
                FrameLog.install()
                TouchLog.install()
                Sampler.install()
                // The library's and your own exercises' muscles worked out off the main thread, ahead of the picker,
                // the workout's cards and the ranks.
                let names = Catalog.names + model.training.sessions.flatMap { $0.exercises.map(\.name) }
                Task.detached(priority: .utility) { LiftTable.warm(names) }
                if MotionCheck.onLaunch { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MotionCheck.run(model) } }
                if AB.warmKeyboard { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Self.warmKeyboard(model) } }
            }
            // The rest Live Activity: back to the workout in progress.
            .onOpenURL { url in if url.host == "workout", model.training.active != nil { model.workoutOpen = true } }
        }
    }
}
