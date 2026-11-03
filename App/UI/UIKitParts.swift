import SwiftUI
import UIKit

// Theme's pieces for UIKit views (the workout's cards, -ab-uikit-card): the same tokens drawn by Core Animation, so a
// card that grows in a UIKit animation is resized by iOS's render server, with no SwiftUI update per change.

extension UIColor {
    static let text = UIColor(Palette.text), muted = UIColor(Palette.muted), accent = UIColor(Palette.accent)
    static let onGreen = UIColor(Palette.onGreen), danger = UIColor(Palette.danger), well = UIColor(Palette.well)
    static let greenWash = UIColor(Palette.greenWash)
}

extension TextStyle {
    private var uiStyle: UIFont.TextStyle {
        switch self { case .t12: .caption1; case .t14: .subheadline; case .t16: .headline; case .t20: .title3; case .t28: .title1; case .t32: .largeTitle }
    }
    private var uiWeight: UIFont.Weight {
        switch self { case .t12, .t16: .semibold; case .t14: .regular; case .t20, .t28, .t32: .bold }
    }

    /// At the system text size, as Typeset's @ScaledMetric.
    func scaled(_ value: CGFloat, _ traits: UITraitCollection) -> CGFloat {
        UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: value, compatibleWith: traits)
    }

    func font(_ traits: UITraitCollection, weight: UIFont.Weight? = nil, mono: Bool = false) -> UIFont {
        let points = scaled(self.size, traits), thickness = weight ?? uiWeight
        return mono ? .monospacedDigitSystemFont(ofSize: points, weight: thickness) : .systemFont(ofSize: points, weight: thickness)
    }
}

/// Text in a style (Typeset): the PWA's line height made up around the font's own, half above, half below and between
/// lines. One line unless `lines` is 0; `shrink` lets one line shrink to fit rather than cut.
final class Words: UILabel {
    private var style = TextStyle.t16
    private var weight: UIFont.Weight?
    private var mono = false

    convenience init(_ style: TextStyle, _ color: UIColor, weight: UIFont.Weight? = nil, mono: Bool = false, lines: Int = 0,
                     shrink: CGFloat? = nil, align: NSTextAlignment = .natural) {
        self.init(frame: .zero)
        (self.style, self.weight, self.mono) = (style, weight, mono)
        textColor = color
        numberOfLines = lines
        textAlignment = align
        if let shrink { adjustsFontSizeToFitWidth = true; minimumScaleFactor = shrink }
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (words: Words, _) in words.restyle() }
    }

    private func restyle() {
        font = style.font(traitCollection, weight: weight, mono: mono)
        show(words, again: true)
    }

    /// The text shown (multi-line text keeps its line spacing).
    private(set) var words = ""
    /// Its height at a width, kept until its text or size changes (a card asks several times a move).
    private var measured: (width: CGFloat, height: CGFloat)?

    /// The same text again draws nothing (`again`: the font changed).
    func show(_ text: String, again: Bool = false) {
        guard again || text != words || self.text == nil else { return }
        words = text
        measured = nil
        guard numberOfLines != 1 else { self.text = text; return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = extra
        paragraph.alignment = textAlignment
        attributedText = NSAttributedString(string: text, attributes: [.font: font as Any, .foregroundColor: textColor as Any, .paragraphStyle: paragraph])
    }

    /// One line's height: the style's line, or the font's own when that's taller (as Typeset: the text, up to the
    /// screen's pixel as SwiftUI sizes it, and the extra round it).
    var line: CGFloat { lines(1) }
    private var extra: CGFloat { max(0, style.scaled(style.lineHeight, traitCollection) - font.lineHeight) }

    private func lines(_ count: Int) -> CGFloat {
        let n = CGFloat(count)
        return (n * font.lineHeight + (n - 1) * extra).pixelUp(scale) + extra
    }

    func height(for width: CGFloat) -> CGFloat {
        guard numberOfLines != 1 else { return line }
        if let measured, measured.width == width { return measured.height }
        let rect = (words as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin,
                                                    attributes: [.font: font as Any], context: nil)
        let height = lines(max(1, Int((rect.height / font.lineHeight).rounded())))
        measured = (width, height)
        return height
    }

    /// One line's width.
    var width: CGFloat { ceil((words as NSString).size(withAttributes: [.font: font as Any]).width) }
}

extension UIView {
    /// The screen's pixels a point (a view not yet on screen has none of its own).
    var scale: CGFloat { max(traitCollection.displayScale, UITraitCollection.current.displayScale, 1) }

    /// A point in this view's space moved to where the view is shown now (mid-move its frame is where it's going).
    func onScreen(_ point: CGPoint) -> CGPoint {
        guard let shown = layer.presentation(), let root = window?.layer else { return point }
        return shown.convert(layer.convert(point, to: root), from: nil)
    }
}

extension CGFloat {
    /// Up to the next whole pixel, as SwiftUI sizes text and views (a hair under one counts as on it).
    func pixelUp(_ scale: CGFloat) -> CGFloat { ((self * scale) - 0.001).rounded(.up) / scale }
}

/// A gradient-backed view: its gradient resizes with it in a UIKit animation.
final class Shade: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}

/// RAISED (Raised): the shade, a light line along the top edge, a small soft shadow. Its parts follow its frame, so it
/// grows with a card in a UIKit animation. `radius` nil: a pill.
final class RaisedView: UIView {
    private let shade = Shade(), fade = Shade(), inner = Shade()
    private let radius: CGFloat?
    /// A fixed-size part's shadow is drawn from its shape; a card's, which grows in an animation, from its shade.
    private let grows: Bool
    var surface: Surface { didSet { if surface != oldValue { paint() } } }

    init(_ surface: Surface, radius: CGFloat?, grows: Bool = false) {
        (self.surface, self.radius, self.grows) = (surface, radius, grows)
        // Laid out once at a size, so their autoresizing keeps them right at any later one.
        super.init(frame: CGRect(x: 0, y: 0, width: Size.cell, height: Size.cell))
        isUserInteractionEnabled = false
        for (view, inset) in [(shade, CGFloat(0)), (fade, 0), (inner, Size.hairline)] {
            view.frame = bounds.insetBy(dx: inset, dy: inset)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.layer.cornerCurve = radius == nil ? .circular : .continuous
            addSubview(view)
        }
        shade.layer.shadowColor = UIColor.black.cgColor
        shade.layer.shadowOpacity = AB.noShadow ? 0 : 0.45
        shade.layer.shadowRadius = 4
        shade.layer.shadowOffset = CGSize(width: 0, height: 3)
        fade.gradient.locations = [0, 0.12]
        round()
        paint()
    }

    required init?(coder: NSCoder) { nil }

    private func paint() {
        UIView.performWithoutAnimation {
            let colors = surface.shade.map { UIColor($0).cgColor }
            shade.gradient.colors = colors
            inner.gradient.colors = colors
            fade.gradient.colors = [UIColor.white.withAlphaComponent(surface.edge).cgColor, UIColor.white.withAlphaComponent(0.04).cgColor]
        }
    }

    private func round() {
        let r = radius ?? bounds.height / 2
        shade.layer.cornerRadius = r
        fade.layer.cornerRadius = r
        inner.layer.cornerRadius = max(0, r - Size.hairline)
        shade.layer.shadowPath = grows ? nil
            : UIBezierPath(roundedRect: bounds, cornerRadius: r).cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !grows || radius == nil { round() }
    }
}

/// SUNK (Sunk): the dark well with a soft inner shadow at its top; a ring (green focused, red wrong) when given.
final class SunkView: UIView {
    private let caster = CALayer()
    var ring: UIColor? { didSet { if ring != oldValue { edge() } } }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.backgroundColor = UIColor.well.cgColor
        layer.cornerRadius = Radius.inner
        layer.cornerCurve = .continuous
        layer.masksToBounds = true // the inner shadow stays in the well
        if !AB.noInner {
            caster.shadowColor = UIColor.black.cgColor
            caster.shadowOpacity = 0.65
            caster.shadowRadius = 1.5
            caster.shadowOffset = CGSize(width: 0, height: 1)
            layer.addSublayer(caster)
        }
        edge()
    }

    required init?(coder: NSCoder) { nil }

    private func edge() {
        layer.borderWidth = ring == nil ? Size.hairline : 2
        layer.borderColor = (ring ?? UIColor.white.withAlphaComponent(0.03)).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        caster.frame = bounds
        // A frame round the well: its shadow falls inside.
        let frame = UIBezierPath(rect: bounds.insetBy(dx: -Space.s4, dy: -Space.s4))
        frame.append(UIBezierPath(roundedRect: bounds, cornerRadius: Radius.inner).reversing())
        caster.shadowPath = frame.cgPath
    }
}

/// A button that dims while pressed (CardStyle) and fades when disabled. `onPress` dims something else instead (a
/// whole card whose edge is outside the button).
class PressControl: UIControl {
    var action: () -> Void = {}
    var onPress: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(fire), for: .touchUpInside)
        addTarget(self, action: #selector(lifted), for: .touchUpOutside)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() { action() }

    /// Lifted outside its frame but inside where it's shown: it moved under the finger mid-move.
    @objc private func lifted(_ control: UIControl, _ event: UIEvent) {
        guard let touch = event.allTouches?.first, bounds.contains(onScreen(touch.location(in: self))) else { return }
        action()
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            if let onPress { onPress(isHighlighted) } else { look() }
        }
    }

    override var isEnabled: Bool { didSet { look() } }

    private func look() { alpha = (isEnabled ? 1 : Press.faded) * (isHighlighted ? Press.dim : 1) }
}

/// A round button holding one icon (RoundButton).
final class RoundControl: PressControl {
    private let fill = RaisedView(.control, radius: nil)
    private let icon = UIImageView()

    init(_ icon: Icon, tint: UIColor = .text) {
        super.init(frame: CGRect(x: 0, y: 0, width: Size.control, height: Size.control))
        fill.frame = bounds
        fill.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(fill)
        self.icon.image = icon.ui(IconSize.round)
        self.icon.tintColor = tint
        self.icon.contentMode = .center
        self.icon.frame = bounds
        self.icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(self.icon)
    }

    required init?(coder: NSCoder) { nil }
}

extension Icon {
    /// The symbol at the PWA's size, as Icon.image draws it.
    func ui(_ size: CGFloat = IconSize.regular, bold: Bool = false) -> UIImage? {
        UIImage(systemName: rawValue, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: bold ? .bold : .semibold))
    }
}

/// The PWA's swipe to arm (SwipeToArm) on a UIKit view: a swipe (or flick) left or a long press arms it, a swipe
/// right disarms it.
final class Arming: NSObject, UIGestureRecognizerDelegate {
    var armed = false
    private let changed: (Bool) -> Void

    init(_ view: UIView, changed: @escaping (Bool) -> Void) {
        self.changed = changed
        super.init()
        guard !AB.noSwipe else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = SwipeToArm.hold
        view.addGestureRecognizer(hold)
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y) && (armed || velocity.x < 0)
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled else { return }
        let x = pan.translation(in: pan.view).x, velocity = pan.velocity(in: pan.view).x
        set(abs(velocity) > SidewaysPan.flick ? velocity < 0 : x < 0)
    }

    @objc private func held(_ hold: UILongPressGestureRecognizer) { if hold.state == .began { set(true) } }

    private func set(_ now: Bool) {
        guard now != armed else { return }
        armed = now
        if now { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        changed(now)
    }
}

enum Moves {
    /// A part's change as SwipeToArm's motion: cross-faded on iOS's curve (at once with Reduce Motion).
    @MainActor static func swap(_ change: @escaping () -> Void) {
        if Motion.still { change() } else { spring(change) }
    }

    /// The app's move (Motion.move) in UIKit. What's moving still takes touches, as in SwiftUI (UIKit's default
    /// ignores them until it settles, so a quick next tap was lost).
    @MainActor static func spring(_ change: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(springDuration: Motion.normal, bounce: 0, options: .allowUserInteraction, animations: change, completion: completion)
    }

    /// The pop (Pop): swells from Pop.from past full size and settles, fading in over its first part.
    @MainActor static func pop(_ layer: CALayer) {
        guard !Motion.still else { return }
        let steps = 30
        let done = (0...steps).map { Motion.ease.value(at: Double($0) / Double(steps)) }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = done.map(Pop.scale)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = done.map { min(1, $0 / Pop.peak) }
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Motion.normal
        layer.add(group, forKey: "pop")
    }
}
