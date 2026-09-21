import AppKit

/// Every window level Nook uses, in one place, bottom to top:
///
///     normal app windows                    0
///     focusOverlay   (.floating - 1)        2   the full-screen dim; above other apps, below all of Nook
///     agent, chat, prompt (.floating)       3   agent windows, the chat panel, line prompts
///     Dock                                 20   (system)
///     menu bar                             24   (system)
///     hud            (.statusBar)          25   HUD, voice HUD, close question and undo offer
///     ghost          (.popUpMenu)         101   the handoff drag chip, above everything
///
/// The overlay must stay under `.floating` or it would dim the active agent and the chat panel.
/// That also puts it under the system's menu bar and Dock, which therefore stay bright.
enum NookLevel {
    static let focusOverlay = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    /// AgentWindow sets `.floating` itself; this names the same level.
    static let agent = NSWindow.Level.floating
    static let chat = NSWindow.Level.floating
    static let prompt = NSWindow.Level.floating
    static let hud = NSWindow.Level.statusBar
    static let ghost = NSWindow.Level.popUpMenu
}
