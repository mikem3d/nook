import AppKit

/// The chat panel's dimensions. They are kept at the `medium` text size and multiplied by the
/// setting, so the panel holds about the same amount of text at every size. Pure, so it is tested headless.
enum ChatMetrics {
    static let baseDefault = NSSize(width: 820, height: 560)
    static let baseMinimum = NSSize(width: 420, height: 280)

    static func minimumSize(textSize: TextSize) -> NSSize {
        NSSize(width: textSize.metric(baseMinimum.width), height: textSize.metric(baseMinimum.height))
    }

    /// The size to show. `saved` is a stored base size; one that is missing or too small falls back to the default.
    static func panelSize(saved: NSSize?, textSize: TextSize) -> NSSize {
        let usable = saved.flatMap { $0.width >= baseMinimum.width && $0.height >= baseMinimum.height ? $0 : nil }
        let base = usable ?? baseDefault
        return NSSize(width: textSize.metric(base.width), height: textSize.metric(base.height))
    }

    /// The inverse of `panelSize`: what to store for a size the user dragged out.
    static func baseSize(of shown: NSSize, textSize: TextSize) -> NSSize {
        NSSize(width: (shown.width / textSize.rawValue).rounded(), height: (shown.height / textSize.rawValue).rounded())
    }
}
