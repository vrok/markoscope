import AppKit

/// Read-only document holding the raw Markdown text of a file.
/// The Objective-C name is referenced by `NSDocumentClass` in Info.plist.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private(set) var markdown = ""

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController())
    }

    override func read(from data: Data, ofType typeName: String) throws {
        markdown = String(decoding: data, as: UTF8.self)
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { [] }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    /// Re-reads the file after an external change. Returns false if it can't be read.
    func reloadFromDisk() -> Bool {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return false }
        markdown = String(decoding: data, as: UTF8.self)
        return true
    }
}
