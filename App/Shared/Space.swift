import CoreGraphics

/// Track's spacing steps, shared with the rest Live Activity (the widget extension can't see the app's Theme):
/// 16 page edge, card padding, title to content; 8 label to content; 12 between cards; 24 between sections; 4 tight.
enum Space {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24
}
