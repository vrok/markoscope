import AppKit
import WebKit

/// Opens Markdown files dropped onto a document window, each as its own document.
/// (Drops on the Dock icon come in through Info.plist's document types instead.)
enum FileDrop {
    static func markdownURLs(in info: NSDraggingInfo) -> [URL] {
        markdownURLs(on: info.draggingPasteboard)
    }

    static func markdownURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter { DocumentWindowController.markdownExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func operation(for info: NSDraggingInfo) -> NSDragOperation {
        markdownURLs(in: info).isEmpty ? [] : .copy
    }

    static func open(_ info: NSDraggingInfo) -> Bool {
        let urls = markdownURLs(in: info)
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        return !urls.isEmpty
    }
}

/// The document's web view. It takes over drag-and-drop entirely: the page is read-only,
/// so the only useful drop is a Markdown file to open.
final class DocumentWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { FileDrop.operation(for: sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { FileDrop.operation(for: sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) {}
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { FileDrop.open(sender) }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}
}

/// Background of the history pane, accepting the same drops as the web view.
final class FileDropEffectView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { FileDrop.operation(for: sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { FileDrop.operation(for: sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { FileDrop.open(sender) }
}
