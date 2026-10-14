import AppKit

/// Shown when no document is open: the app's name and an Open button on the left,
/// recently opened files on the right (one click re-opens them). Files can be dropped onto it.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = WelcomeWindowController()

    private var recents: [URL] = []
    private let tableView = RecentFilesTableView()
    private let emptyLabel = NSTextField(labelWithString: "No recent files yet")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Markoscope"
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        reload()
        reloadSoonIfEmpty()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(tableView)
    }

    func reloadIfVisible() {
        if window?.isVisible == true { reload() }
    }

    func closeIfVisible() {
        if window?.isVisible == true { close() }
    }

    private func reload() {
        recents = RecentFiles.urls
        tableView.reloadData()
        emptyLabel.isHidden = !recents.isEmpty
    }

    // Right after launch macOS may not have loaded the recent list yet; check again shortly.
    private func reloadSoonIfEmpty() {
        guard recents.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reloadIfVisible() }
    }

    // MARK: - Layout

    private func makeContent() -> NSView {
        let root = FileDropView()

        // Left: identity and the primary action.
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: "Markoscope")
        name.font = .systemFont(ofSize: 30, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let tagline = NSTextField(labelWithString: "A calm place to read Markdown")
        tagline.font = .systemFont(ofSize: 13)
        tagline.textColor = .secondaryLabelColor
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor

        let openButton = NSButton(title: "Open a File…", target: self, action: #selector(openFile(_:)))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        let dropHint = NSTextField(labelWithString: "or drop a Markdown file here")
        dropHint.font = .systemFont(ofSize: 11)
        dropHint.textColor = .tertiaryLabelColor

        let identity = NSStackView(views: [icon, name, tagline, versionLabel])
        identity.orientation = .vertical
        identity.spacing = 4
        identity.setCustomSpacing(14, after: icon)
        identity.setCustomSpacing(10, after: tagline)
        let actions = NSStackView(views: [openButton, dropHint])
        actions.orientation = .vertical
        actions.spacing = 8
        let left = NSStackView(views: [identity, actions])
        left.orientation = .vertical
        left.spacing = 36

        // Right: recent files on a sidebar-style background.
        let right = NSVisualEffectView()
        right.material = .sidebar
        right.blendingMode = .behindWindow
        let header = NSTextField(labelWithString: "Recent Files")
        header.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        header.textColor = .secondaryLabelColor

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file")))
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.rowHeight = 52
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.onReturn = { [weak self] in self?.openSelected() }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor

        for view in [header, scrollView, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            right.addSubview(view)
        }
        for view in [left, right, icon] { view.translatesAutoresizingMaskIntoConstraints = false }
        root.addSubview(left)
        root.addSubview(right)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 128),
            icon.heightAnchor.constraint(equalToConstant: 128),

            left.centerXAnchor.constraint(equalTo: root.leadingAnchor, constant: 170),
            left.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 6),

            right.topAnchor.constraint(equalTo: root.topAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            right.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 340),

            header.topAnchor.constraint(equalTo: right.topAnchor, constant: 40),
            header.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 22),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: right.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: right.centerYAnchor),
        ])
        return root
    }

    // MARK: - Actions

    @objc private func openFile(_ sender: Any?) {
        NSDocumentController.shared.openDocument(sender)
    }

    @objc private func rowClicked(_ sender: Any?) {
        guard recents.indices.contains(tableView.clickedRow) else { return }
        RecentFiles.open(recents[tableView.clickedRow])
    }

    private func openSelected() {
        guard recents.indices.contains(tableView.selectedRow) else { return }
        RecentFiles.open(recents[tableView.selectedRow])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        recents.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: RecentFileCell.identifier, owner: self) as? RecentFileCell ?? RecentFileCell()
        cell.configure(with: recents[row])
        return cell
    }
}

/// Opens the selected file on Return.
private final class RecentFilesTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
    }
}

/// File icon, name, and the folder it's in.
private final class RecentFileCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("RecentFileCell")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let folderLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        folderLabel.font = .systemFont(ofSize: 11)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle

        let text = NSStackView(views: [nameLabel, folderLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        for view in [iconView, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -60),
            folderLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -60),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with url: URL) {
        iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        nameLabel.stringValue = url.lastPathComponent
        folderLabel.stringValue = RecentFiles.folder(of: url)
        toolTip = (url.path as NSString).abbreviatingWithTildeInPath
    }
}
