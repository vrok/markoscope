import AppKit

/// The app's document controller: keeps the recently opened files in ~/.markoscope/history
/// (shown in File ▸ Open Recent and the welcome window), and shows the welcome window when
/// the last document closes. Created in main.swift so it becomes `NSDocumentController.shared`.
final class DocumentController: NSDocumentController {
    override var maximumRecentDocumentCount: Int { Preferences.shared.recentFilesCount }

    override var recentDocumentURLs: [URL] { RecentFiles.urls }

    /// macOS's own recent-documents list (still kept up to date, e.g. for the Dock menu).
    var systemRecentDocumentURLs: [URL] { super.recentDocumentURLs }

    override func noteNewRecentDocumentURL(_ url: URL) {
        super.noteNewRecentDocumentURL(url)
        RecentFiles.add(url)
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        RecentFiles.clear()
        WelcomeWindowController.shared.reloadIfVisible()
    }

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
}

/// The recently opened files, newest first, stored one path per line in ~/.markoscope/history.
enum RecentFiles {
    private static let fileURL = Preferences.directory.appendingPathComponent("history")
    private static var stored: [URL]? = load()

    /// The remembered files that still exist.
    static var urls: [URL] {
        seedFromSystemListIfNeeded()
        return Array((stored ?? []).filter(exists).prefix(Preferences.shared.recentFilesCount))
    }

    static func add(_ url: URL) {
        seedFromSystemListIfNeeded()
        let url = url.standardizedFileURL
        var list = stored ?? []
        list.removeAll { $0.path == url.path }
        list.insert(url, at: 0)
        stored = Array(list.filter(exists).prefix(Preferences.shared.recentFilesCount))
        save()
    }

    static func clear() {
        stored = []
        save()
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// nil when there is no history file yet.
    private static func load() -> [URL]? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) }
    }

    private static func save() {
        let text = (stored ?? []).map { $0.path + "\n" }.joined()
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Could not save recent files to \(fileURL.path): \(error)")
        }
    }

    /// The first time, start from the files macOS remembers (it loads them shortly after launch).
    private static func seedFromSystemListIfNeeded() {
        guard stored == nil,
              let system = (NSDocumentController.shared as? DocumentController)?.systemRecentDocumentURLs,
              !system.isEmpty else { return }
        stored = Array(system.filter(exists).prefix(Preferences.shared.recentFilesCount))
        save()
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
