import CoreGraphics

enum LayoutMetrics {
    /// Shared resting height for the left sidebar account footer and the right message composer bar
    /// so their horizontal dividers align seamlessly across the split view.
    static let bottomBarHeight: CGFloat = 54

    /// Height of circular controls and single-line input pill inside the message composer bar.
    static let composerControlHeight: CGFloat = 34

    /// Vertical padding around composer controls (`34 + 10 * 2 = 54pt`, matching `bottomBarHeight`).
    static let composerVerticalPadding: CGFloat = 10
}
