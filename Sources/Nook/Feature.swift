import AppKit

/// An optional capability. Features live in Features/, own their own state and preferences,
/// and reach the rest of the app only through AppController's public surface and the
/// notifications below.
protocol Feature: AnyObject {
    func install(in app: AppController)
}

extension Notification.Name {
    /// An agent window was added, closed, moved or re-ordered. Object: AppController.
    static let nookAgentsChanged = Notification.Name("nookAgentsChanged")
    /// A session's state, transcript, badge or pending permission changed. Object: AgentWindow.
    static let nookSessionChanged = Notification.Name("nookSessionChanged")
    /// The active (focused) agent changed. Object: AppController.
    static let nookActiveChanged = Notification.Name("nookActiveChanged")
}
