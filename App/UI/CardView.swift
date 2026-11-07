import SwiftUI
import TrackCore
import UIKit

/// ExerciseCard drawn by UIKit (-ab-uikit-card): the same card, so opening one costs a few UIKit views instead of a
/// SwiftUI update (15-25 ms a card on the iPhone 13). Its surface follows its frame, so it grows with its row in the
/// list's animation; what it opens is uncovered by its edge, what it closes is covered by it (the PWA's resize). Its
/// line swaps at once.
final class CardView: UIView {
    private(set) var card: ExerciseCard?
    private weak var model: AppModel?
    private let surface = RaisedView(.card, radius: Radius.card, grows: true)
    private let clip = UIView()

    // Closed: its number, name and "1 of 3 sets · last 60×8", tapped to open, held to arrange.
    private let closed = PressControl()
    private let tile = RaisedView(.control, radius: Radius.inner)
    private let number = Words(.t16, .text, mono: true, lines: 1, align: .center)
    private let closedName = Words(.t16, .text)
    private let detail = Words(.t14, .muted, mono: true)
    private let chevron = UIImageView(image: Icon.down.ui(IconSize.medium))
    private let hold = UILongPressGestureRecognizer()

    // Open: its name over its muscle and rest, ⋯ (or, swiped, a red ✕ that removes it).
    private let heading = UIView()
    private let texts = UIView()
    private let name = Words(.t20, .text)
    private let muscle = Words(.t14, .muted)
    private let options = RoundControl(.more)
    private let remove = RoundControl(.close, tint: .danger)
    private var arming: Arming?

    /// What it opens, built the first time it does and kept (closed, it's under the card's edge).
    private var sets: SetsView?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Size.column, height: Size.row))
        clip.clipsToBounds = true
        for view in [surface, clip] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
        tile.addSubview(number)
        for view in [tile, closedName, detail, chevron] as [UIView] { view.isUserInteractionEnabled = false; closed.addSubview(view) }
        chevron.tintColor = .muted
        closed.onPress = { [weak self] in self?.alpha = $0 ? Press.dim : 1 }
        closed.action = { [weak self] in self?.card?.onOpen() }
        closed.isAccessibilityElement = true
        closed.accessibilityTraits = .button
        closed.accessibilityValue = "Closed"
        hold.minimumPressDuration = SwipeToArm.hold
        hold.addTarget(self, action: #selector(held))
        closed.addGestureRecognizer(hold)
        clip.addSubview(closed)

        texts.addSubview(name)
        texts.addSubview(muscle)
        texts.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(disarm)))
        for view in [texts, options, remove] as [UIView] { heading.addSubview(view) }
        options.action = { [weak self] in self?.card?.onOptions() }
        remove.action = { [weak self] in
            guard let self, let card else { return }
            arm(false)
            model?.removeExercise(card.exercise)
        }
        remove.alpha = 0
        clip.addSubview(heading)
        arming = Arming(heading) { [weak self] in self?.arm($0) }
    }

    required init?(coder: NSCoder) { nil }

    func update(_ next: ExerciseCard, model: AppModel) {
        self.model = model
        let previous = card
        card = next
        let fresh = previous?.exercise.id != next.exercise.id
        let toggled = fresh || previous?.open != next.open
        // Opened or closed in the list's move: the line it shows and the one it hides cross-fade (-ab-card-fade), and
        // the name also glides between its two places (-ab-card-morph). Swapped at once, the line read as a jump in
        // the move's first frame (build 103, a real tap filmed).
        let blend = !fresh && toggled && (AB.cardFade || AB.cardMorph) && !Motion.still
        if fresh { sets?.removeFromSuperview(); sets = nil }
        UIView.performWithoutAnimation {
            number.show("\(next.number)")
            number.textColor = next.current ? .accent : .text
            closedName.show(next.exercise.name)
            detail.show(ExerciseCard.detail(next.exercise, last: next.last, next.unit))
            closed.accessibilityLabel = "\(next.number), \(next.exercise.name), \(detail.words)"
            closed.accessibilityCustomActions = next.onArrange == nil ? [] : [UIAccessibilityCustomAction(name: "Arrange exercises") { [weak self] _ in
                self?.card?.onArrange?(); return true
            }]
            hold.isEnabled = next.onArrange != nil
            name.show(next.exercise.name)
            muscle.show(next.muscle + dot + "Rest \(clock(next.restSeconds))")
            options.accessibilityLabel = "\(next.exercise.name) options"
            remove.accessibilityLabel = "Remove \(next.exercise.name)"
            closed.isHidden = next.open && !blend
            heading.isHidden = !next.open && !blend
            closed.alpha = 1
            heading.alpha = 1
            if blend { (next.open ? heading : closed).alpha = 0 } // what it shows now fades in from clear
            closed.isAccessibilityElement = !next.open
            heading.accessibilityElementsHidden = !next.open
            closed.isUserInteractionEnabled = !next.open
            heading.isUserInteractionEnabled = next.open
            name.transform = .identity
            closedName.transform = .identity
            if !next.open { arm(false) }
            if next.open, sets == nil { makeSets() }
            sets?.isUserInteractionEnabled = next.open
            sets?.accessibilityElementsHidden = !next.open
        }
        // What it closes saves what was typed, as its rows going away did.
        if previous?.open == true, !next.open { sets?.flush() }
        if next.open, previous?.open != true { sets?.reload() }
        if next.open { sets?.update(next, model: model) }
        // Its line and what it opens are where they go at once; set rows added or removed in an open card move.
        if toggled { UIView.performWithoutAnimation { place(bounds.width, apply: true) } } else { place(bounds.width, apply: true) }
        guard blend else { return }
        let (coming, going) = next.open ? (name, closedName) : (closedName, name)
        if AB.cardMorph {
            let start = Self.onto(coming, going, in: clip), end = Self.onto(going, coming, in: clip)
            UIView.performWithoutAnimation { coming.transform = start }
            coming.transform = .identity
            going.transform = end
        }
        // In the list's move (CardList's spring), so in step with the card's own height.
        closed.alpha = next.open ? 0 : 1
        heading.alpha = next.open ? 1 : 0
    }

    /// Moves and scales `label` onto where `other` is drawn, their first lines' starts together (-ab-card-morph).
    private static func onto(_ label: Words, _ other: Words, in space: UIView) -> CGAffineTransform {
        let to = other.convert(other.bounds, to: space), from = label.convert(label.bounds, to: space)
        let scale = other.font.pointSize / label.font.pointSize
        return CGAffineTransform(translationX: to.minX - (from.midX - from.width * scale / 2), y: to.minY - (from.midY - from.height * scale / 2))
            .scaledBy(x: scale, y: scale)
    }

    /// Its height changed by itself (typing showed an error or a new best).
    var onResize: (() -> Void)?

    /// Typing saves before the card shows another exercise.
    func flush() { sets?.flush() }

    private func makeSets() {
        let built = SetsView()
        built.onResize = { [weak self] in self?.onResize?() }
        sets = built
        clip.addSubview(built)
    }

    /// Where a set's row is in it, while it's open.
    func frame(ofSet id: String) -> CGRect? {
        guard card?.open == true, let row = sets?.row(id) else { return nil }
        return row.convert(row.bounds, to: self)
    }

    /// Closed and not yet built what it opens (-ab-prebuilt-sets).
    var needsSets: Bool { card?.open == false && sets == nil }

    /// What it opens, built while it's closed (laid out when it opens), so a tap only shows it.
    func buildSets() {
        guard needsSets, let card, let model else { return }
        UIView.performWithoutAnimation {
            makeSets()
            sets?.isUserInteractionEnabled = false
            sets?.accessibilityElementsHidden = true
            sets?.update(card, model: model)
            // Laid out under its edge, out of sight, so its words are drawn now rather than as it opens.
            guard let sets else { return }
            let inner = bounds.width - Space.s4 * 2
            let height = sets.place(inner, apply: true)
            sets.frame = CGRect(x: Space.s4, y: bounds.height, width: inner, height: height)
        }
    }

    func height(for width: CGFloat) -> CGFloat { place(width, apply: false) }

    /// Its height once it shows `next`, worked out before it does (CardList times its move by how far it goes); its
    /// set rows not made yet are counted as tall as one it has.
    func height(for width: CGFloat, as next: ExerciseCard) -> CGFloat {
        let now = card
        card = next
        defer { card = now }
        let height = place(width, apply: false)
        guard next.open, let sets else { return height }
        return height + sets.change(to: AB.noRows ? 0 : next.exercise.sets.count, width - Space.s4 * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        place(bounds.width, apply: true)
    }

    /// Its parts' frames at this width (when `apply`), and its height (.pad() all round).
    @discardableResult private func place(_ width: CGFloat, apply: Bool) -> CGFloat {
        guard let card else { return 0 }
        let pad = Space.s4, inner = width - pad * 2
        let top: CGFloat
        if card.open {
            let textWidth = inner - Space.s3 - Size.control
            let nameHeight = name.height(for: textWidth), textHeight = nameHeight + muscle.height(for: textWidth)
            top = max(Size.control, textHeight)
            if apply {
                heading.frame = CGRect(x: pad, y: pad, width: inner, height: top)
                texts.frame = CGRect(x: 0, y: (top - textHeight) / 2, width: textWidth, height: textHeight)
                name.frame = CGRect(x: 0, y: 0, width: textWidth, height: nameHeight)
                muscle.frame = CGRect(x: 0, y: nameHeight, width: textWidth, height: textHeight - nameHeight)
                for button in [options, remove] { button.frame = CGRect(x: inner - Size.control, y: (top - Size.control) / 2, width: Size.control, height: Size.control) }
            }
        } else {
            chevron.sizeToFit()
            let icon = chevron.bounds.size
            let textWidth = inner - Size.tile - Space.s3 * 2 - icon.width
            let nameHeight = closedName.height(for: textWidth), textHeight = nameHeight + detail.height(for: textWidth)
            top = max(Size.tile, textHeight, icon.height)
            if apply {
                closed.frame = CGRect(x: pad, y: pad, width: inner, height: top)
                tile.frame = CGRect(x: 0, y: (top - Size.tile) / 2, width: Size.tile, height: Size.tile)
                number.frame = tile.bounds
                let x = Size.tile + Space.s3
                closedName.frame = CGRect(x: x, y: (top - textHeight) / 2, width: textWidth, height: nameHeight)
                detail.frame = CGRect(x: x, y: closedName.frame.maxY, width: textWidth, height: textHeight - nameHeight)
                chevron.frame = CGRect(x: inner - icon.width, y: (top - icon.height) / 2, width: icon.width, height: icon.height)
            }
        }
        var height = pad + top + pad
        if card.open, let sets {
            let setsHeight = sets.place(inner, apply: apply)
            if apply { sets.frame = CGRect(x: pad, y: pad + top, width: inner, height: setsHeight) }
            height += setsHeight
        }
        return height
    }

    @objc private func held(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began, let onArrange = card?.onArrange else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onArrange()
    }

    @objc private func disarm() { if arming?.armed == true { arm(false) } }

    /// ⋯ and the red ✕ cross-fade in place.
    private func arm(_ on: Bool) {
        arming?.armed = on
        Moves.swap { [self] in
            options.alpha = on ? 0 : 1
            remove.alpha = on ? 1 : 0
        }
        options.isUserInteractionEnabled = !on
        remove.isUserInteractionEnabled = on
        options.accessibilityElementsHidden = on
        remove.accessibilityElementsHidden = !on
    }
}

/// What an open card shows under its line: the Set · Last · kg · Reps · RIR · Done columns, a row per set, Add set.
private final class SetsView: UIView {
    private let columns: [Words]
    private var rows: [String: SetRowView] = [:]
    private var order: [String] = []
    private let add = PressControl()
    private let addFill = RaisedView(.control, radius: nil)
    private let addIcon = UIImageView(image: Icon.plus.ui(IconSize.medium))
    private let addWords = Words(.t16, .text, lines: 1)

    init() {
        columns = (0..<6).map { _ in Words(.t12, .muted, lines: 1, align: .center) }
        super.init(frame: .zero)
        for column in columns { column.isAccessibilityElement = false; addSubview(column) }
        addIcon.tintColor = .text
        addWords.show("Add set")
        for view in [addFill, addIcon, addWords] as [UIView] { view.isUserInteractionEnabled = false; add.addSubview(view) }
        add.isAccessibilityElement = true
        add.accessibilityLabel = "Add set"
        add.accessibilityTraits = .button
        addSubview(add)
    }

    required init?(coder: NSCoder) { nil }

    private var card: ExerciseCard?
    private weak var model: AppModel?
    var onResize: (() -> Void)?

    func update(_ card: ExerciseCard, model: AppModel) {
        self.card = card
        self.model = model
        let exercise = card.exercise
        for (column, title) in zip(columns, ["Set", "Last", card.unit.rawValue, "Reps", "RIR", "Done"]) { column.show(title) }
        let labels = exercise.setLabels
        let next = exercise.sets.firstIndex { !$0.done }
        let ids = AB.noRows ? [] : exercise.sets.map(\.id)
        for id in order where !ids.contains(id) { if let row = rows[id] { gone(row) }; rows[id] = nil }
        for (index, set) in exercise.sets.enumerated() where ids.contains(set.id) {
            let row = rows[set.id] ?? {
                let row = SetRowView(set: set, unit: card.unit)
                row.onResize = { [weak self] in self?.onResize?() }
                rows[set.id] = row
                addSubview(row)
                return row
            }()
            row.update(SetRowView.Input(
                exercise: exercise, set: set, label: labels[index], next: index == next, unit: card.unit, autoLog: card.autoLog, bests: card.bests,
                last: card.last.flatMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil },
                focus: card.focus,
                focused: card.focusHere.flatMap { $0.hasPrefix("\(set.id).") ? String($0.dropFirst(set.id.count + 1)) : nil }), model: model)
        }
        order = ids
        add.isEnabled = exercise.sets.count < Limits.sets
        add.action = { [weak self] in
            guard let id = self?.card?.exercise.id else { return }
            self?.model?.update { $0.updateActive(exercise: id) { $0 = $0.addingSet() } }
        }
    }

    /// A removed set's row fades as what's under it comes up (`.row`).
    private func gone(_ row: SetRowView) {
        row.flush()
        guard UIView.inheritedAnimationDuration > 0 else { row.removeFromSuperview(); return }
        Moves.spring({ row.alpha = 0 }, completion: { _ in row.removeFromSuperview() })
    }

    func flush() { rows.values.forEach { $0.flush() } }
    func row(_ id: String) -> UIView? { rows[id] }
    /// How much taller (or shorter) `count` rows make it than the rows it has, each as tall as its first.
    func change(to count: Int, _ width: CGFloat) -> CGFloat {
        let each = (order.first.flatMap { rows[$0] }?.height(for: width) ?? Size.row) + Space.s2
        return CGFloat(count - order.count) * each
    }
    /// Opened again: its rows show the sets' numbers, as rows built anew did.
    func reload() { rows.values.forEach { $0.reload() } }

    @discardableResult func place(_ width: CGFloat, apply: Bool) -> CGFloat {
        var y = Space.s4
        let header = columns[0].line
        if apply { for (column, frame) in zip(columns, SetRowView.columns(width, y: y, height: header)) { column.frame = frame } }
        y += header + Space.s2
        for (index, id) in order.enumerated() {
            guard let row = rows[id] else { continue }
            let height = row.height(for: width)
            if apply {
                let frame = CGRect(x: 0, y: y, width: width, height: height)
                if row.frame == .zero {
                    // A new row is laid out where it goes and uncovered there, fading in (`.row`).
                    UIView.performWithoutAnimation { row.frame = frame; row.layoutIfNeeded(); row.alpha = 0 }
                    row.alpha = 1
                } else {
                    row.frame = frame
                }
            }
            y += height + (index < order.count - 1 ? Space.s2 : 0)
        }
        y += Space.s4
        let height = max(Size.control, addWords.line)
        if apply {
            add.frame = CGRect(x: 0, y: y, width: width, height: height)
            addFill.frame = add.bounds
            addIcon.sizeToFit()
            let icon = addIcon.bounds.size, words = addWords.width
            // Label's icon and title, side by side in the middle.
            let x = (width - icon.width - Gap.label - words) / 2
            addIcon.frame = CGRect(x: x, y: (height - icon.height) / 2, width: icon.width, height: icon.height)
            addWords.frame = CGRect(x: x + icon.width + Gap.label, y: (height - addWords.line) / 2, width: words, height: addWords.line)
        }
        return y + height
    }
}

/// SetRow drawn by UIKit: its number (green on the next to do), last time's numbers, kg · reps · RIR, and ✓. Typing,
/// saving and swiping work as SetRow's (its comments say why).
final class SetRowView: UIView {
    struct Input {
        let exercise: Exercise
        let set: TrainingSet
        let label: String
        let next: Bool
        let unit: TrackCore.Settings.Unit
        let autoLog: Bool
        let bests: RecordBests
        let last: TrainingSet?
        let focus: Binding<String?>
        let focused: String?
    }

    private var state: Input?
    private weak var model: AppModel?
    private var weight = "", reps = "", rir = ""
    private var rirTyped = false
    private var pending: Task<Void, Never>?
    private var replacing: String?
    private var done = false, best = false
    private var arming: Arming?

    private let tile = RaisedView(.control, radius: Radius.inner)
    private let label = Words(.t16, .text, weight: .semibold, mono: true, lines: 1, align: .center)
    private let lastWords = Words(.t12, .muted, mono: true, lines: 1, shrink: Shrink.figure, align: .center)
    private let fields: [(id: String, well: SunkView, words: Words)] = ["kg", "reps", "rir"].map {
        (id: $0, well: SunkView(), words: Words(.t16, .text, weight: .semibold, mono: true, lines: 1, shrink: Shrink.value, align: .center))
    }
    private let check = PressControl()
    private let checkFill = RaisedView(.control, radius: Radius.inner)
    private let checkIcon = UIImageView()
    private let error = Words(.t12, .danger)
    private let badge = UIView()
    private let badgeWords = Words(.t12, .accent, weight: .bold, mono: true, lines: 1)
    private let bestWords = Words(.t14, .muted)

    init(set: TrainingSet, unit: TrackCore.Settings.Unit) {
        super.init(frame: .zero)
        show(set, unit)
        tile.addSubview(label)
        addSubview(tile)
        lastWords.isAccessibilityElement = true
        addSubview(lastWords)
        for field in fields {
            field.well.addSubview(field.words)
            field.well.isUserInteractionEnabled = true
            field.well.isAccessibilityElement = true
            field.words.isAccessibilityElement = false
            field.well.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
            addSubview(field.well)
        }
        checkFill.isUserInteractionEnabled = false
        checkIcon.contentMode = .center
        checkIcon.isUserInteractionEnabled = false
        check.addSubview(checkFill)
        check.addSubview(checkIcon)
        check.action = { [weak self] in
            guard let self else { return }
            if arming?.armed == true { delete() } else { tapCheck() }
        }
        addSubview(check)
        addSubview(error)
        badge.backgroundColor = .greenWash
        badge.addSubview(badgeWords)
        badgeWords.show("New best")
        addSubview(badge)
        addSubview(bestWords)
        arming = Arming(self) { [weak self] _ in self?.render() }
        NotificationCenter.default.addObserver(self, selector: #selector(typedKey), name: KeyInput.typed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(leaving), name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    func update(_ next: Input, model: AppModel) {
        self.model = model
        let was = state
        state = next
        if let was, was.set != next.set || was.unit != next.unit { load() }
        if let was, was.focused != next.focused {
            if was.focused != nil, next.focused == nil { flush() }
            if let now = next.focused { replacing = now }
        }
        render(first: was == nil)
    }

    /// Opened again: the set's own numbers, as a row built anew (typing that wasn't saved is gone).
    func reload() {
        guard let state else { return }
        pending?.cancel(); pending = nil
        rirTyped = false
        show(state.set, state.unit)
        render()
    }

    private func show(_ set: TrainingSet, _ unit: TrackCore.Settings.Unit) {
        weight = TrainingSet.display(kg: set.kg, unit: unit)
        reps = set.reps.map(String.init) ?? ""
        rir = set.rir.map(String.init) ?? ""
    }

    private func render(first: Bool = false) {
        guard let state else { return }
        let shown = typed
        let problem = TrainingSet.inputError(weight: weight, reps: reps, rir: rir, unit: state.unit)
        let heaviest: Double? = if case .heaviest(let before)? = state.bests.record(for: state.exercise.name, shown) { before } else { nil }
        let nowBest = heaviest != nil && shown.done
        let name = state.set.side.map { "Set \(state.label), \($0.rawValue) side" } ?? "Set \(state.label)"
        let armed = arming?.armed == true
        UIView.performWithoutAnimation {
            label.show(state.label)
            label.textColor = state.next ? .accent : .text
            label.accessibilityLabel = name
            let last = ExerciseCard.lastText(state.last, state.unit)
            lastWords.show(last)
            lastWords.accessibilityLabel = "Last time \(last)"
            let labels = ["kg": "\(state.unit.rawValue), \(name)", "reps": "Reps, \(name)", "rir": "Reps in reserve, \(name)"]
            for field in fields {
                let text = field.id == "kg" ? weight : field.id == "reps" ? reps : rir
                field.words.show(text)
                field.well.ring = problem?.fields.contains(field.id) == true ? .danger : state.focused == field.id ? .accent : nil
                field.well.accessibilityLabel = labels[field.id]
                field.well.accessibilityValue = text
                field.well.accessibilityTraits = state.focused == field.id ? [.button, .selected] : .button
            }
            checkFill.surface = shown.done && !armed ? .green : .control
            check.accessibilityLabel = armed ? "Delete \(name)" : shown.done ? "\(name) done" : "Mark \(name) done"
            check.accessibilityTraits = shown.done ? [.button, .selected] : .button
            check.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Delete set") { [weak self] _ in self?.delete(); return true }]
            error.show(problem?.message ?? "")
            error.isHidden = problem == nil
            if let heaviest {
                bestWords.show("\(TrainingSet.display(kg: shown.kg ?? 0, unit: state.unit)) \(state.unit.rawValue) beats \(TrainingSet.display(kg: heaviest, unit: state.unit)) \(state.unit.rawValue)")
            }
            badge.isHidden = !nowBest
            bestWords.isHidden = !nowBest
        }
        // ✓ and ✕ cross-fade as the row arms and disarms; otherwise its icon changes at once.
        let icon = { [self] in
            checkIcon.image = (armed ? Icon.close : Icon.check).ui(IconSize.medium, bold: true)
            checkIcon.tintColor = armed ? .danger : shown.done ? .onGreen : .muted
        }
        if armed != wasArmed, !Motion.still {
            UIView.transition(with: checkIcon, duration: Motion.normal, options: [.transitionCrossDissolve, .allowUserInteraction], animations: icon)
        } else {
            UIView.performWithoutAnimation(icon)
        }
        if !first, shown.done, !done { Moves.pop(check.layer) }
        if !first, nowBest, !best {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Moves.pop(badge.layer)
        }
        let resized = best != nowBest || errorShown != (problem != nil)
        (done, best, wasArmed, errorShown) = (shown.done, nowBest, armed, problem != nil)
        // Typing that shows or clears an error (or a new best) changes the card's height outside the list's updates.
        if resized, !first { setNeedsLayout(); onResize?() }
    }

    /// The row's height changed by itself.
    var onResize: (() -> Void)?
    private var wasArmed = false, errorShown = false

    /// SetColumns: six columns, each as wide as a cell at most, in the middle of an equal share of the row.
    static func columns(_ width: CGFloat, y: CGFloat, height: CGFloat) -> [CGRect] {
        let share = (width - Space.s1 * 5) / 6, cell = min(Size.cell, share)
        return (0..<6).map { CGRect(x: CGFloat($0) * (share + Space.s1) + (share - cell) / 2, y: y, width: cell, height: height) }
    }

    func height(for width: CGFloat) -> CGFloat { place(width, apply: false) }

    override func layoutSubviews() {
        super.layoutSubviews()
        place(bounds.width, apply: true)
    }

    @discardableResult private func place(_ width: CGFloat, apply: Bool) -> CGFloat {
        let line = max(Size.control, label.line)
        var y = line
        if apply {
            let frames = Self.columns(width, y: 0, height: line)
            tile.frame = frames[0]
            label.frame = tile.bounds
            lastWords.frame = frames[1]
            for (field, frame) in zip(fields, frames[2...4]) {
                field.well.frame = frame
                field.words.frame = frame.insetBy(dx: Space.s1, dy: 0).offsetBy(dx: -frame.minX, dy: -frame.minY)
            }
            check.frame = frames[5]
            checkFill.frame = check.bounds
            checkIcon.frame = check.bounds
        }
        if !error.isHidden {
            let height = error.height(for: width)
            if apply { error.frame = CGRect(x: 0, y: y + Space.s2, width: width, height: height) }
            y += Space.s2 + height
        }
        if best {
            let badgeHeight = badgeWords.line + Pad.badge * 2, badgeWidth = badgeWords.width + Space.s2 * 2
            let textWidth = width - badgeWidth - Space.s2, textHeight = bestWords.height(for: textWidth)
            let height = max(badgeHeight, textHeight)
            if apply {
                badge.frame = CGRect(x: 0, y: y + Space.s2 + (height - badgeHeight) / 2, width: badgeWidth, height: badgeHeight)
                badge.layer.cornerRadius = badgeHeight / 2
                badgeWords.frame = CGRect(x: Space.s2, y: Pad.badge, width: badgeWords.width, height: badgeWords.line)
                bestWords.frame = CGRect(x: badgeWidth + Space.s2, y: y + Space.s2 + (height - textHeight) / 2, width: textWidth, height: textHeight)
            }
            y += Space.s2 + height
        }
        return y
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard let state, let field = fields.first(where: { $0.well === tap.view }) else { return }
        state.focus.wrappedValue = "\(state.set.id).\(field.id)"
    }

    @objc private func typedKey(_ note: Notification) { if let focused = state?.focused { key(focused, note.object as? String) } }

    @objc private func leaving() { if pending != nil { flush() } }

    // MARK: SetRow's typing and saving, unchanged

    private func typedInto(_ id: String) {
        guard let state else { return }
        if id == "rir" { rirTyped = true }
        pending?.cancel()
        if id == "rir", state.autoLog, let n = Int(rir), n == 0 || n * 10 > Limits.rir { flush(); return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: SetRow.typingPause)
            if !Task.isCancelled { self?.flush() }
        }
    }

    private func key(_ field: String, _ text: String?) {
        let allowed = field == "kg" ? "0123456789.," : "0123456789"
        if let text, text.isEmpty || !text.allSatisfy({ allowed.contains($0) }) { return }
        var value = replacing == field ? "" : field == "kg" ? weight : field == "reps" ? reps : rir
        replacing = nil
        if let text { value += text } else { value = String(value.dropLast()) }
        if field == "kg" { weight = value } else if field == "reps" { reps = value } else { rir = value }
        if let n = Int(rir), n > Limits.rir { rir = String(Limits.rir) }
        typedInto(field)
        render()
    }

    private func delete() {
        guard let state else { return }
        arming?.armed = false
        model?.removeSet(state.set.id, in: state.exercise.id)
    }

    private func load() {
        guard let state else { return }
        let unit = state.unit, set = state.set
        let shown = (TrainingSet.display(kg: set.kg, unit: unit), set.reps.map(String.init) ?? "", set.rir.map(String.init) ?? "")
        if TrainingSet.display(kg: TrainingSet.kilograms(from: weight, unit: unit), unit: unit) != shown.0 { weight = shown.0 }
        if TrainingSet.wholeNumber(reps) != set.reps { reps = shown.1 }
        if TrainingSet.wholeNumber(rir) != set.rir { rir = shown.2 }
    }

    private var typed: TrainingSet {
        guard let state else { return TrainingSet() }
        let unit = state.unit, set = state.set, autoLog = state.autoLog
        if !(autoLog && rirTyped), TrainingSet.display(kg: TrainingSet.kilograms(from: weight, unit: unit), unit: unit) == TrainingSet.display(kg: set.kg, unit: unit),
           TrainingSet.wholeNumber(reps) == set.reps, TrainingSet.wholeNumber(rir) == set.rir { return set }
        return set.edited(weight: weight, reps: reps, rir: rir, unit: unit, autoLog: autoLog && rirTyped)
    }

    func flush() { pending?.cancel(); pending = nil; if !invalid { save(typed) } }
    private var invalid: Bool { state.map { TrainingSet.inputError(weight: weight, reps: reps, rir: rir, unit: $0.unit) != nil } ?? true }

    private func tapCheck() {
        guard let state, !invalid else { return }
        flush()
        rirTyped = false
        model?.toggle(set: state.set.id, in: state.exercise.id)
    }

    private func save(_ next: TrainingSet) {
        guard let state, next != state.set else { return }
        let started = next.done && !state.set.done
        let exerciseId = state.exercise.id, setId = state.set.id
        model?.update(moving: started) { training in
            training.updateActive(exercise: exerciseId) { exercise in
                if let index = exercise.sets.firstIndex(where: { $0.id == setId }) { exercise.sets[index] = next }
            }
            if started { training.startRest() }
        }
    }
}
