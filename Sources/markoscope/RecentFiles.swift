import AppKit

/// Keeps macOS's recent-documents list at the length set in ~/.markoscope.toml.
/// Created in main.swift so it becomes `NSDocumentController.shared`.
final class DocumentController: NSDocumentController {
    override var maximumRecentDocumentCount: Int { Preferences.shared.recentFilesCount }
}

/// The recently opened files that still exist, newest first.
enum RecentFiles {
    static var urls: [URL] {
        let limit = Preferences.shared.recentFilesCount
        return NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(limit)
            .map { $0 }
    }

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    /// "~/notes" for a file in /Users/me/notes.
    static func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

/// Fills File ▸ Open Recent each time it opens.
final class RecentFilesMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = RecentFiles.urls
        let names = urls.map(\.lastPathComponent)
        for url in urls {
            // Same-named files (every project has a README.md) get their folder added.
            let name = url.lastPathComponent
            let title = names.filter { $0 == name }.count > 1 ? "\(name) — \(url.deletingLastPathComponent().lastPathComponent)" : name
            let item = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { RecentFiles.open(url) }
    }

    @objc private func clearRecent(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(nil)
        WelcomeWindowController.shared.reloadIfVisible()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(clearRecent(_:)) ? !RecentFiles.urls.isEmpty : true
    }
}
