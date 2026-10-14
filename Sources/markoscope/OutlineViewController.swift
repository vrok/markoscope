import AppKit

/// The document's headings as a tree (shown in the sidebar). Clicking one scrolls to it,
/// and the section being read is highlighted as the document scrolls.
final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// A heading, as reported by the page (see `postOutline` in app.js).
    struct Heading {
        let id: String
        let title: String
        let level: Int
    }

    /// Called with the anchor id of the heading the user picked.
    var onSelectHeading: ((String) -> Void)?

    private final class Node {
        let heading: Heading
        weak var parent: Node?
        var children: [Node] = []
        init(_ heading: Heading) { self.heading = heading }
    }

    private var roots: [Node] = []
    private var nodesByID: [String: Node] = [:]
    /// Headings the user collapsed; kept across reloads of the same document.
    private var collapsedIDs: Set<String> = []
    private var isUpdating = false

    private let outlineView = NSOutlineView()
    private let emptyLabel = NSTextField(labelWithString: "No headings")

    override func loadView() {
        let root = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 12
        outlineView.dataSource = self
        outlineView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.textColor = .tertiaryLabelColor

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

    func update(headings: [Heading]) {
        _ = view
        // Build the tree: each heading nests under the closest previous heading of a higher level.
        var newRoots: [Node] = []
        var stack: [Node] = []
        nodesByID = [:]
        for heading in headings {
            let node = Node(heading)
            nodesByID[heading.id] = node
            while let last = stack.last, last.heading.level >= heading.level { stack.removeLast() }
            if let parent = stack.last {
                node.parent = parent
                parent.children.append(node)
            } else {
                newRoots.append(node)
            }
            stack.append(node)
        }
        roots = newRoots

        isUpdating = true
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
        for id in collapsedIDs {
            if let node = nodesByID[id] { outlineView.collapseItem(node) }
        }
        isUpdating = false
        emptyLabel.isHidden = !headings.isEmpty
    }

    /// Highlights the heading of the section currently in view.
    func setActiveHeading(_ id: String?) {
        _ = view
        isUpdating = true
        defer { isUpdating = false }
        var node = id.flatMap { nodesByID[$0] }
        // If its section is collapsed, highlight the nearest visible ancestor instead.
        while let current = node, outlineView.row(forItem: current) < 0 { node = current.parent }
        guard let node else { outlineView.deselectAll(nil); return }
        let row = outlineView.row(forItem: node)
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: - Outline view

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("HeadingCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = node.heading.title
        cell.textField?.font = node.heading.level <= 1
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        cell.toolTip = node.heading.title
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating, let node = outlineView.item(atRow: outlineView.selectedRow) as? Node else { return }
        onSelectHeading?(node.heading.id)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isUpdating, let node = notification.userInfo?["NSObject"] as? Node else { return }
        collapsedIDs.insert(node.heading.id)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isUpdating, let node = notification.userInfo?["NSObject"] as? Node else { return }
        collapsedIDs.remove(node.heading.id)
    }
}
