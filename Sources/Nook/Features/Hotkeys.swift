import AppKit

/// Global hotkeys: approve or deny the oldest waiting request, jump to the agent that needs you.
final class Hotkeys: Feature {
    func install(in app: AppController) {}
}
