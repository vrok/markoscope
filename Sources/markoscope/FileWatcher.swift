import Foundation

/// Watches a single file for changes. `onChange(replaced)` is called on the main queue;
/// `replaced` is true when the file was deleted or renamed (e.g. an editor's atomic save),
/// in which case the watcher is dead and the caller should create a new one.
final class FileWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping (_ replaced: Bool) -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [source] in
            let replaced = !source.data.isDisjoint(with: [.delete, .rename])
            if replaced { source.cancel() }
            onChange(replaced)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
