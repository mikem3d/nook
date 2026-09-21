import AppKit
import UserNotifications

/// The only file that talks to UNUserNotificationCenter.
///
/// `UNUserNotificationCenter.current()` raises an exception in a process without a bundle
/// identifier, so nothing here touches it unless Nook runs from Nook.app (scripts/bundle.sh);
/// from `swift run` every call is a harmless no-op.
///
/// Time-sensitive delivery is not used: it needs the restricted entitlement
/// com.apple.developer.usernotifications.time-sensitive, which only a provisioning profile from a
/// paid developer account can grant (an ad-hoc signed app that claims it will not launch).
/// Approvals use the normal active level instead.
final class NotifyCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifyCenter()
    /// Posted on the main thread when `status` changes. The settings window listens.
    static let statusChanged = Notification.Name("nookNotifyStatusChanged")

    enum Status { case unavailable, undetermined, allowed, denied }

    enum Action: Equatable {
        case open, allow, deny
        case reply(String)
    }

    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private(set) var status = Status.unavailable
    /// Called on the main thread with the agent id and request id the notification carried.
    var onAction: ((Action, _ agentID: String, _ requestID: String?) -> Void)?

    private var center: UNUserNotificationCenter? { Self.isAvailable ? .current() : nil }

    /// Identifiers from an earlier run name agents that no longer exist, so those notifications go.
    func start() {
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories(Self.categories)
        center.removeAllDeliveredNotifications()
        refresh()
    }

    func refresh(then done: (() -> Void)? = nil) {
        guard let center else { done?(); return }
        center.getNotificationSettings { [weak self] settings in
            let status: Status
            switch settings.authorizationStatus {
            case .notDetermined: status = .undetermined
            case .denied: status = .denied
            default: status = .allowed
            }
            DispatchQueue.main.async { self?.set(status); done?() }
        }
    }

    /// Shows the system's own permission prompt. It appears once ever; afterwards this only reports the answer.
    func requestAuthorisation(then done: @escaping (Bool) -> Void) {
        guard let center else { return done(false) }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.set(granted ? .allowed : .denied); done(granted) }
        }
    }

    func post(_ plan: NotifyPlan) {
        guard let center, status == .allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.subtitle = plan.subtitle
        content.body = plan.body
        content.threadIdentifier = plan.thread
        content.categoryIdentifier = plan.category.rawValue
        content.sound = plan.sound ? .default : nil
        content.interruptionLevel = plan.passive ? .passive : .active
        content.userInfo = ["agent": plan.agentID, "request": plan.requestID ?? ""]
        center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: nil))
    }

    func remove(_ identifiers: [String]) {
        guard let center, !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// The Notifications pane for Nook; the general pane if the bundle identifier is missing.
    static func openSystemSettings() {
        let base = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let target = Bundle.main.bundleIdentifier.map { "\(base)?id=\($0)" } ?? base
        if let url = URL(string: target) { NSWorkspace.shared.open(url) }
    }

    private func set(_ new: Status) {
        guard new != status else { return }
        status = new
        NotificationCenter.default.post(name: Self.statusChanged, object: self)
    }

    private static var categories: Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: "open", title: "Open", options: [.foreground])
        let allow = UNNotificationAction(identifier: "allow", title: "Allow", options: [])
        let deny = UNNotificationAction(identifier: "deny", title: "Deny", options: [])
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let actions: [NotifyPlan.Category: [UNNotificationAction]] = [
            .approve: [allow, deny], .review: [deny, open], .finished: [reply, open], .open: [open],
        ]
        return Set(NotifyPlan.Category.allCases.map {
            UNNotificationCategory(identifier: $0.rawValue, actions: actions[$0] ?? [], intentIdentifiers: [])
        })
    }

    // MARK: UNUserNotificationCenterDelegate (called off the main thread)

    /// Suppression already happened before posting, so a notification shows even while Nook is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let passive = notification.request.content.interruptionLevel == .passive
        completionHandler(passive ? [.list] : [.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let agent = info["agent"] as? String ?? ""
        let request = (info["request"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let action: Action?
        switch response.actionIdentifier {
        case "allow": action = .allow
        case "deny": action = .deny
        case "reply": action = (response as? UNTextInputNotificationResponse).map { .reply($0.userText) }
        case UNNotificationDismissActionIdentifier: action = nil
        default: action = .open // a click on the notification itself, or Open
        }
        DispatchQueue.main.async { [weak self] in
            if let action { self?.onAction?(action, agent, request) }
            completionHandler()
        }
    }
}
