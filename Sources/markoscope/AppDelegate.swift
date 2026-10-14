import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Set once quitting starts, so closing documents doesn't bring up the welcome window.
    private(set) static var isTerminating = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        TabCommands.shared.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched without a file (e.g. from Finder or the Dock): show the welcome window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSDocumentController.shared.documents.isEmpty {
                WelcomeWindowController.shared.show()
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.isTerminating = true
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindowController.shared.show() }
        return true
    }

    /// The full version, e.g. "0.1.0" for a release or "0.1.0-3-g1a2b3c4" for a build after it (set by run.sh).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "MarkoscopeVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: Self.version])
    }

    @objc func showWelcome(_ sender: Any?) {
        WelcomeWindowController.shared.show()
    }

    // MARK: - View menu actions (reached through the responder chain)

    @objc func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw) else { return }
        Preferences.shared.theme = theme
    }

    @objc func increaseTextSize(_ sender: Any?) { Preferences.shared.increaseFontSize() }
    @objc func decreaseTextSize(_ sender: Any?) { Preferences.shared.decreaseFontSize() }
    @objc func resetTextSize(_ sender: Any?) { Preferences.shared.resetFontSize() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let prefs = Preferences.shared
        switch menuItem.action {
        case #selector(selectTheme(_:)):
            menuItem.state = (menuItem.representedObject as? String) == prefs.theme.rawValue ? .on : .off
        case #selector(increaseTextSize(_:)):
            return prefs.canIncreaseFontSize
        case #selector(decreaseTextSize(_:)):
            return prefs.canDecreaseFontSize
        case #selector(resetTextSize(_:)):
            return prefs.fontSize != Preferences.defaultFontSize
        default:
            break
        }
        return true
    }
}
