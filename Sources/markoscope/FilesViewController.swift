import AppKit

/// The Markdown files of an opened folder, as a tree. Clicking a file (or pressing Return)
/// opens it in a tab; the file shown in this window is highlighted.
final class FilesViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onOpenFile: ((URL) -> Void)?

    private var items: [Workspace.Item] = []
    private var currentFile: URL?
    /// Folders the user collapsed; kept when the folder is re-read.
    private var collapsedPaths: Set<String> = []
    private var isUpdating = false

    private let outlineView = FileOutlineView()
    private let emptyLabel = NSTextField(labelWithString: "No Markdown files")

    override func loadView() {
        let root = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.indentationPerLevel = 14
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        outlineView.onReturn = { [weak self] in self?.openSelected() }

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.isHidden = true

        for subview in [scrollView, emptyLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
    }

    func update(items newItems: [Workspace.Item], currentFile file: URL?) {
        _ = view
        items = newItems
        currentFile = file?.standardizedFileURL
        isUpdating = true
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        collapse(items)
        isUpdating = false
        emptyLabel.isHidden = !items.isEmpty
        highlightCurrentFile()
    }

    private func collapse(_ items: [Workspace.Item]) {
        for item in items where item.isFolder {
            if collapsedPaths.contains(item.url.path) { outlineView.collapseItem(item) } else { collapse(item.children) }
        }
    }

    private func highlightCurrentFile() {
        isUpdating = true
        defer { isUpdating = false }
        guard let currentFile, let item = find(currentFile, in: items) else { outlineView.deselectAll(nil); return }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { outlineView.deselectAll(nil); return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    private func find(_ url: URL, in items: [Workspace.Item]) -> Workspace.Item? {
        for item in items {
            if item.isFolder {
                if let match = find(url, in: item.children) { return match }
            } else if item.url.standardizedFileURL == url {
                return item
            }
        }
        return nil
    }

    // MARK: - Actions

    @objc private func rowClicked(_ sender: Any?) {
        open(outlineView.item(atRow: outlineView.clickedRow) as? Workspace.Item)
    }

    private func openSelected() {
        open(outlineView.item(atRow: outlineView.selectedRow) as? Workspace.Item)
    }

    private func open(_ item: Workspace.Item?) {
        guard let item else { return }
        if item.isFolder {
            outlineView.isItemExpanded(item) ? outlineView.collapseItem(item) : outlineView.expandItem(item)
            return
        }
        onOpenFile?(item.url)
        // This window keeps showing its own file; the clicked one opens in another tab.
        highlightCurrentFile()
    }

    // MARK: - Outline view

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Workspace.Item)?.children.count ?? items.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Workspace.Item)?.children[index] ?? items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Workspace.Item)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Workspace.Item else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let icon = NSImageView()
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            for view in [icon, label] {
                view.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(view)
            }
            cell.imageView = icon
            cell.textField = label
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
        cell.textField?.stringValue = item.url.lastPathComponent
        cell.toolTip = (item.url.path as NSString).abbreviatingWithTildeInPath
        return cell
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdating, let item = notification.userInfo?["NSObject"] as? Workspace.Item else { return }
        collapsedPaths.insert(item.url.path)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdating, let item = notification.userInfo?["NSObject"] as? Workspace.Item else { return }
        collapsedPaths.remove(item.url.path)
    }
}

/// Opens the selected file on Return.
private final class FileOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
    }
}
