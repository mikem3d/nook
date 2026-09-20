import CoreGraphics

/// Where a click on an agent window lands. Pure geometry in view points (origin bottom left), so
/// it can be unit tested; the scene draws the glyphs these areas sit over.
enum WindowChrome {
    enum Hit: Equatable { case close, minimise, restore, body, outside }

    static func hit(_ point: CGPoint, in size: CGSize, minimised: Bool) -> Hit {
        if minimised { return inOrb(point, size: size) ? .restore : .outside }
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return .outside }
        let s = size.width / RoomScene.W
        guard point.y > size.height - RoomScene.bar * s else { return .body }
        let fromRight = (size.width - point.x) / s
        if fromRight < RoomScene.closeHit { return .close }
        if fromRight < RoomScene.minimiseHit { return .minimise }
        return .body
    }

    /// A minimised window is a square showing a disc; its corners belong to whatever is behind it.
    static func inOrb(_ point: CGPoint, size: CGSize) -> Bool {
        let radius = min(size.width, size.height) / 2
        return hypot(point.x - size.width / 2, point.y - size.height / 2) <= radius
    }

    /// An orb has no room for text, so hovering tells you who it is and what it is doing.
    static func tooltip(label: String, state: AgentState, waitingForPermission: Bool, summary: String) -> String {
        let status = waitingForPermission ? "waiting for permission" : state.rawValue
        let first = "\(label): \(status)"
        return summary.isEmpty ? first : first + "\n" + summary
    }
}

/// Which scene of the theme a new agent gets. The settings window writes these keys.
enum ScenePrefs {
    /// The theme's id. One theme ships today.
    static let themeKey = "nook.theme"
    static let defaultTheme = "dwarf"
    /// `rotate`, or the id of the scene every new agent gets.
    static let newAgentKey = "nook.newAgentScene"
    static let rotate = "rotate"

    /// `index` is how many agents are already open. nil when the theme offers no scenes.
    static func scene(forNew index: Int, choices: [String], preference: String?) -> String? {
        guard !choices.isEmpty else { return nil }
        if let preference, choices.contains(preference) { return preference }
        return choices[index % choices.count]
    }
}
