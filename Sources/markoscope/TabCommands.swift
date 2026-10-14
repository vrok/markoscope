import AppKit

/// "Close Tabs to the Left/Right", in the Window menu (for the current tab) and in the menu
/// macOS shows when right-clicking a tab (for the tab that was clicked).
///
/// AppKit has no API for extending the tab menu, so this watches for AppKit building it
/// (recognised by its "Close Other Tabs" item) and adds the two commands after that item.
final class TabCommands: NSObject, NSMenuItemValidation {
    static let shared = TabCommands()

    /// The tab under the most recent right-click (or Control-click) in a tab bar.
    private weak var clickedTab: NSWindow?
    private var isAddingItems = false

    func install() {
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                self?.clickedTab = Self.tab(at: event)
            }
            return event
        }
        // The tab menu is built fresh for each right-click; catch it as its items are added,
        // and again when it opens in case the first chance was missed.
        NotificationCenter.default.addObserver(self, selector: #selector(menuChanged(_:)), name: NSMenu.didAddItemNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuChanged(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
    }

    // MARK: - Commands

    /// The current tab's windows, left to right, and its index.
    private func tabs(around window: NSWindow?) -> (windows: [NSWindow], index: Int)? {
        guard let window else { return nil }
        let windows = window.tabbedWindows ?? [window]
        guard let index = windows.firstIndex(of: window) else { return nil }
        return (windows, index)
    }

    private func closeTabs(_ side: Side, of window: NSWindow?) {
        guard let (windows, index) = tabs(around: window) else { return }
        let doomed = side == .left ? Array(windows[..<index]) : Array(windows[(index + 1)...])
        doomed.forEach { $0.performClose(nil) }
    }

    private enum Side { case left, right }

    @objc func closeTabsToTheLeft(_ sender: Any?) {
        closeTabs(.left, of: target(of: sender))
    }

    @objc func closeTabsToTheRight(_ sender: Any?) {
        closeTabs(.right, of: target(of: sender))
    }

    /// Items in the tab menu carry the clicked tab; Window-menu items act on the current tab.
    private func target(of sender: Any?) -> NSWindow? {
        ((sender as? NSMenuItem)?.representedObject as? WeakWindow)?.window ?? NSApp.keyWindow
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let (windows, index) = tabs(around: target(of: menuItem)) else { return false }
        switch menuItem.action {
        case #selector(closeTabsToTheLeft(_:)): return index > 0
        case #selector(closeTabsToTheRight(_:)): return index < windows.count - 1
        default: return true
        }
    }

    // MARK: - The tab context menu

    private final class WeakWindow: NSObject {
        weak var window: NSWindow?
        init(_ window: NSWindow?) { self.window = window }
    }

    @objc private func menuChanged(_ notification: Notification) {
        guard !isAddingItems, let menu = notification.object as? NSMenu,
              !menu.items.contains(where: { $0.representedObject is WeakWindow }),
              let closeOthers = menu.items.firstIndex(where: Self.isCloseOtherTabs) else { return }
        isAddingItems = true
        defer { isAddingItems = false }

        let tab = WeakWindow(clickedTab ?? NSApp.keyWindow)
        let left = NSMenuItem(title: "Close Tabs to the Left", action: #selector(closeTabsToTheLeft(_:)), keyEquivalent: "")
        let right = NSMenuItem(title: "Close Tabs to the Right", action: #selector(closeTabsToTheRight(_:)), keyEquivalent: "")
        for (offset, item) in [left, right].enumerated() {
            item.target = self
            item.representedObject = tab
            menu.insertItem(item, at: closeOthers + 1 + offset)
        }
    }

    private static func isCloseOtherTabs(_ item: NSMenuItem) -> Bool {
        let action = item.action.map(NSStringFromSelector) ?? ""
        return item.title == "Close Other Tabs" || action.localizedCaseInsensitiveContains("closeOtherTabs")
    }

    /// Finds which tab of the event's window was clicked, from the tab bar's buttons.
    private static func tab(at event: NSEvent) -> NSWindow? {
        guard let window = event.window, let tabs = window.tabbedWindows, tabs.count > 1,
              let frameView = window.contentView?.superview,
              var view = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil)) else { return nil }
        // Walk up to the view that has one sibling of its kind per tab: that's the tab button.
        while let parent = view.superview {
            let buttons = parent.subviews.filter { type(of: $0) == type(of: view) && !$0.isHidden }
            if buttons.count == tabs.count {
                let ordered = buttons.sorted { $0.frame.minX < $1.frame.minX }
                return ordered.firstIndex(of: view).map { tabs[$0] }
            }
            view = parent
        }
        return nil
    }
}

