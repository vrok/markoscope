import AppKit

/// The app's document controller: keeps the recent-documents list (File ▸ Open Recent) at the
/// length set in ~/.markoscope.toml, and shows the welcome window when the last document closes.
/// Created in main.swift so it becomes `NSDocumentController.shared`.
final class DocumentController: NSDocumentController {
    override var maximumRecentDocumentCount: Int { Preferences.shared.recentFilesCount }

    /// Closing the last document brings back the welcome window.
    override func removeDocument(_ document: NSDocument) {
        super.removeDocument(document)
        guard documents.isEmpty else { return }
        // Wait a run-loop turn: the closing window is still on screen, and a file may be opening.
        DispatchQueue.main.async {
            if self.documents.isEmpty, !AppDelegate.isTerminating {
                WelcomeWindowController.shared.show()
            }
        }
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        WelcomeWindowController.shared.reloadIfVisible()
    }
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
