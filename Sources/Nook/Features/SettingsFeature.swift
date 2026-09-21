import AppKit
import SwiftUI

/// The settings window: defaults for new agents, hotkeys, voice, quiet mode.
///
/// Nook is an accessory app. While the window is open it becomes a regular app (so the window
/// can be key, shows in ⌘-Tab and has a menu bar with ⌘W and ⌘,), and it goes back to being an
/// accessory the moment the window closes. The panes and their preference keys live in
/// Control/SettingsViews.swift.
final class SettingsFeature: NSObject, Feature, NSWindowDelegate {
    private var window: NSWindow?
    private var temporaryMenus: [NSMenuItem] = []

    func install(in app: AppController) {
        let item = NSMenuItem(title: "Settings…", action: #selector(open), keyEquivalent: ",")
        item.target = self
        app.addMenuItem(item)
    }

    @objc func open() {
        if window == nil {
            let tabs = SettingsTabs()
            tabs.tabStyle = .toolbar
            tabs.add("General", "gearshape", GeneralSettings())
            tabs.add("Hotkeys", "keyboard", HotkeySettings())
            tabs.add("Notifications", "bell.badge", NotificationSettings())
            tabs.add("Quiet Mode", "moon", QuietSettings())
            tabs.add("Voice", "mic", VoiceSettings())
            tabs.add("About", "info.circle", AboutSettings())

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window

            NSApp.setActivationPolicy(.regular)
            installMenus()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        temporaryMenus.forEach { NSApp.mainMenu?.removeItem($0) }
        temporaryMenus = []
        // Deferred so the window has finished closing before the app drops out of the Dock.
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    /// A regular app needs an application menu in front of AppController's Edit menu.
    private func installMenus() {
        guard let main = NSApp.mainMenu else { return }
        let appMenu = NSMenu(title: "Nook")
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(open), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Nook", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.insertItem(appItem, at: 0)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        main.insertItem(fileItem, at: 1)
        temporaryMenus = [appItem, fileItem]
    }
}

/// Toolbar-style tabs whose window resizes to fit each pane, as system settings windows do.
private final class SettingsTabs: NSTabViewController {
    func add<Pane: View>(_ title: String, _ symbol: String, _ pane: Pane) {
        let host = NSHostingController(rootView: pane)
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = view.window, let pane = tabViewItem?.viewController?.view else { return }
        let size = pane.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - target.height // keep the title bar where it is
        frame.size = target.size
        window.setFrame(frame, display: true, animate: true)
    }
}
