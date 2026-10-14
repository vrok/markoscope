import Foundation

/// A folder opened in Markoscope: the Markdown files in it (and its subfolders), shared by
/// all the tabs showing files from it.
final class Workspace {
    final class Item {
        let url: URL
        let isFolder: Bool
        let children: [Item]

        init(url: URL, isFolder: Bool, children: [Item] = []) {
            self.url = url
            self.isFolder = isFolder
            self.children = children
        }
    }

    static let didChange = Notification.Name("WorkspaceDidChange")
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    private static let skippedFolders: Set<String> = ["node_modules", "DerivedData", "Pods", ".build"]
    private static let maxFiles = 2000
    private static let maxEntries = 50_000

    let root: URL
    /// Folders first, then files, each sorted like Finder; folders without Markdown files are left out.
    private(set) var items: [Item]
    private(set) var files: [URL]
    private var lastScan = Date()
    private var isScanning = false

    private struct WeakWorkspace { weak var value: Workspace? }
    private static var openWorkspaces: [String: WeakWorkspace] = [:]

    /// The workspace for a folder, shared while any tab still uses it.
    static func shared(for folder: URL) -> Workspace {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        if let existing = openWorkspaces[root.path]?.value { return existing }
        let workspace = Workspace(root: root)
        openWorkspaces[root.path] = WeakWorkspace(value: workspace)
        return workspace
    }

    private init(root: URL) {
        self.root = root
        (items, files) = Self.scan(root)
    }

    /// The file to show first: a README or index at the top, otherwise the first file.
    var initialFile: URL? {
        let topLevel = items.filter { !$0.isFolder }.map(\.url)
        for name in ["readme", "index"] {
            if let match = topLevel.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }) {
                return match
            }
        }
        return topLevel.first ?? files.first
    }

    /// Re-reads the folder in the background (at most every few seconds) and posts `didChange`
    /// if the list of files changed.
    func rescan() {
        guard !isScanning, Date().timeIntervalSince(lastScan) > 2 else { return }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [root] in
            let (items, files) = Self.scan(root)
            DispatchQueue.main.async {
                self.isScanning = false
                self.lastScan = Date()
                guard files != self.files else { return }
                self.items = items
                self.files = files
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }

    private static func scan(_ root: URL) -> ([Item], [URL]) {
        var fileCount = 0, entryCount = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        func children(of folder: URL, depth: Int) -> [Item] {
            guard depth < 12, fileCount < maxFiles, entryCount < maxEntries,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
            entryCount += entries.count
            var folders: [Item] = [], files: [Item] = []
            let sorted = entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for entry in sorted {
                // Built from the folder's own path, so every file has one spelling (no /private/tmp vs /tmp).
                let url = folder.appendingPathComponent(entry.lastPathComponent)
                let values = try? entry.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    guard values?.isPackage != true, !skippedFolders.contains(url.lastPathComponent) else { continue }
                    let nested = children(of: url, depth: depth + 1)
                    if !nested.isEmpty { folders.append(Item(url: url, isFolder: true, children: nested)) }
                } else if markdownExtensions.contains(url.pathExtension.lowercased()), fileCount < maxFiles {
                    fileCount += 1
                    files.append(Item(url: url, isFolder: false))
                }
            }
            return folders + files
        }

        func flatten(_ items: [Item]) -> [URL] {
            items.flatMap { $0.isFolder ? flatten($0.children) : [$0.url] }
        }

        let items = children(of: root, depth: 0)
        return (items, flatten(items))
    }
}
