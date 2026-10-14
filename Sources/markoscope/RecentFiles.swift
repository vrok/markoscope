import AppKit

/// The app's document controller: opens folders as workspaces (their files as tabs), keeps the
/// recently opened files and folders in ~/.markoscope/history (shown in File ▸ Open Recent and
/// the welcome window), and shows the welcome window when the last document closes.
/// Created in main.swift so it becomes `NSDocumentController.shared`.
final class DocumentController: NSDocumentController {
    override var maximumRecentDocumentCount: Int { Preferences.shared.recentFilesCount }

    override var recentDocumentURLs: [URL] { RecentFiles.urls }

    /// macOS's own recent-documents list (still kept up to date, e.g. for the Dock menu).
    var systemRecentDocumentURLs: [URL] { super.recentDocumentURLs }

    /// Files being opened from a folder's list; the folder is remembered instead of each file.
    private var filesOpeningInWorkspace: Set<URL> = []

    override func noteNewRecentDocument(_ document: NSDocument) {
        if let url = document.fileURL?.standardizedFileURL, filesOpeningInWorkspace.remove(url) != nil { return }
        super.noteNewRecentDocument(document)
    }

    override func noteNewRecentDocumentURL(_ url: URL) {
        super.noteNewRecentDocumentURL(url)
        RecentFiles.add(url)
    }

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        RecentFiles.clear()
        WelcomeWindowController.shared.reloadIfVisible()
    }

    // MARK: - Folders

    /// The Open panel accepts folders as well as files.
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        openPanel.canChooseDirectories = true
        openPanel.message = "Choose a Markdown file, or a folder to browse its Markdown files"
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }

    /// Every way of opening (Open panel, Finder, Dock, drops, recent files) comes through here;
    /// folders open as a workspace.
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        openFolder(url, completionHandler: completionHandler)
    }

    private func openFolder(_ folder: URL, completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        let workspace = Workspace.shared(for: folder)
        noteNewRecentDocumentURL(workspace.root)

        // Already open: bring its window forward.
        if let existing = windowControllers(in: workspace).first {
            existing.window?.makeKeyAndOrderFront(nil)
            completionHandler(existing.document as? NSDocument, true, nil)
            return
        }
        guard let first = workspace.initialFile else {
            let error = CocoaError(.fileReadNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "“\(folder.lastPathComponent)” has no Markdown files.",
                NSLocalizedRecoverySuggestionErrorKey: "Markoscope lists .md files in the folder and its subfolders.",
            ])
            completionHandler(nil, false, error)
            return
        }
        open(first, in: workspace, tabbedWith: nil, completionHandler: completionHandler)
    }

    /// Opens a file of a folder as a tab of `window` (or in a new window), or switches to its tab.
    func open(_ url: URL, in workspace: Workspace, tabbedWith window: NSWindow?,
              completionHandler: ((NSDocument?, Bool, Error?) -> Void)? = nil) {
        if let document = document(for: url) {
            let controller = document.windowControllers.first as? DocumentWindowController
            if let controller, controller.workspace == nil, let tab = controller.window, let window {
                // Open on its own so far: move it into this folder's tabs.
                controller.workspace = workspace
                window.addTabbedWindow(tab, ordered: .above)
            }
            controller?.window?.makeKeyAndOrderFront(nil)
            completionHandler?(document, true, nil)
            return
        }
        filesOpeningInWorkspace.insert(url.standardizedFileURL)
        super.openDocument(withContentsOf: url, display: false) { document, wasOpen, error in
            self.filesOpeningInWorkspace.remove(url.standardizedFileURL)
            guard let document else {
                if let error { NSApp.presentError(error) }
                completionHandler?(nil, wasOpen, error)
                return
            }
            document.makeWindowControllers()
            if let controller = document.windowControllers.first as? DocumentWindowController {
                controller.workspace = workspace
                if let window, let tab = controller.window { window.addTabbedWindow(tab, ordered: .above) }
            }
            document.showWindows()
            completionHandler?(document, wasOpen, error)
        }
    }

    private func windowControllers(in workspace: Workspace) -> [DocumentWindowController] {
        documents.flatMap(\.windowControllers).compactMap { $0 as? DocumentWindowController }
            .filter { $0.workspace === workspace }
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

/// The recently opened files and folders, newest first, stored one path per line in ~/.markoscope/history.
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
