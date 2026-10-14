import AppKit

/// Read-only document holding the Markdown text of a file, plus every version of it
/// seen while the document was open (the file is watched for changes).
/// The Objective-C name is referenced by `NSDocumentClass` in Info.plist.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    struct Version {
        let id: Int
        /// When the version started; later changes within the merge window are folded into it.
        let date: Date
        /// When the version last changed.
        let updated: Date
        let text: String
        /// Lines added/removed compared with the previous version (for the first one, `added` is its line count).
        let added: Int
        let removed: Int
    }

    static let maxVersions = 200

    private(set) var versions: [Version] = []
    private var nextVersionID = 0

    var markdown: String { versions.last?.text ?? "" }

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    override func read(from data: Data, ofType typeName: String) throws {
        record(String(decoding: data, as: UTF8.self))
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { [] }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    /// Re-reads the file after an external change. Returns true if its content changed.
    func reloadFromDisk() -> Bool {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return false }
        return record(String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    private func record(_ text: String) -> Bool {
        guard let last = versions.last else {
            append(text, id: nextID(), date: Date())
            return true
        }
        if last.text == text { return false }

        // Changes in quick succession (an editor saving repeatedly, a tool writing in steps)
        // become one version. The first, "opened" version is never merged into.
        let now = Date()
        if versions.count > 1, now.timeIntervalSince(last.date) < Preferences.shared.mergeWindow {
            versions.removeLast()
            if versions.last?.text != text { append(text, id: last.id, date: last.date) } // else: the burst undid itself
            return true
        }

        append(text, id: nextID(), date: now)
        if versions.count > Self.maxVersions { versions.removeFirst() }
        return true
    }

    private func nextID() -> Int {
        defer { nextVersionID += 1 }
        return nextVersionID
    }

    private func append(_ text: String, id: Int, date: Date) {
        let lines = text.components(separatedBy: "\n")
        var added = lines.count, removed = 0
        if let previous = versions.last {
            let difference = lines.difference(from: previous.text.components(separatedBy: "\n"))
            added = difference.insertions.count
            removed = difference.removals.count
        }
        versions.append(Version(id: id, date: date, updated: Date(), text: text, added: added, removed: removed))
    }
}
