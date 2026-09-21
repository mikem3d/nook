import AppKit

/// The one text-size setting. Every system-font size and the spacing that goes with it, in the
/// chat panel, the HUDs and the prompts, comes from here, so the whole app grows and shrinks together.
///
/// Sizes are written in the code as they are at `medium`; the stored value is the multiplier.
enum TextSize: Double, CaseIterable {
    case small = 0.8125 // the sizes Nook first shipped with: 13 pt body text
    case medium = 1
    case large = 1.1875
    case extraLarge = 1.375

    static let key = "nook.textSize"
    /// Posted on the main thread after the setting changed, however it was changed.
    static let changed = Notification.Name("nookTextSizeChanged")

    /// What a piece of text is.
    enum Role: CaseIterable {
        case input, body, title, code, label, secondary, caption

        /// Size in points at `medium`. Titles match the body and differ by weight.
        var base: CGFloat {
            switch self {
            case .input: return 17
            case .body, .title: return 16
            case .code: return 15
            case .label: return 14
            case .secondary: return 13
            case .caption: return 12
            }
        }
    }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Pixel text inside the agent windows moves in whole steps rather than by the multiplier.
    var pixelStep: Int {
        switch self {
        case .small: return -1
        case .medium: return 0
        case .large, .extraLarge: return 1
        }
    }

    // MARK: the current setting

    private static var cached = stored()
    private static let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in sync() }

    static var current: TextSize {
        get {
            _ = observer // the settings window writes the key directly; notice that too
            return cached
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            sync()
        }
    }

    /// The nearest size to a stored multiplier, so a hand-written value still lands on the table.
    static func nearest(to multiplier: Double) -> TextSize {
        allCases.min { abs($0.rawValue - multiplier) < abs($1.rawValue - multiplier) } ?? .medium
    }

    private static func stored() -> TextSize {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? nearest(to: value) : .medium
    }

    private static func sync() {
        let now = stored()
        guard now != cached else { return }
        cached = now
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// One size up or down the table; false at either end.
    @discardableResult
    static func step(_ delta: Int) -> Bool {
        let all = allCases
        guard let index = all.firstIndex(of: current), all.indices.contains(index + delta) else { return false }
        current = all[index + delta]
        return true
    }

    // MARK: scaling

    /// A font size: whole points, never below 10.
    func points(_ base: CGFloat) -> CGFloat { max((base * CGFloat(rawValue)).rounded(), 10) }
    func points(_ role: Role) -> CGFloat { points(role.base) }

    /// A spacing, inset, chip height or panel dimension: whole points.
    func metric(_ base: CGFloat) -> CGFloat { (base * CGFloat(rawValue)).rounded() }

    static func points(_ role: Role) -> CGFloat { current.points(role) }
    static func metric(_ base: CGFloat) -> CGFloat { current.metric(base) }

    static func font(_ role: Role, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: points(role), weight: weight)
    }

    static func mono(_ role: Role, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: points(role), weight: weight)
    }

    static func digits(_ role: Role, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: points(role), weight: weight)
    }
}
