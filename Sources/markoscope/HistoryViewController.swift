import AppKit

/// The right-hand pane: every version of the file seen since it was opened (newest first),
/// and a checkbox that highlights what changed in the selected version.
final class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// Called with the id of the version the user picked.
    var onSelectVersion: ((Int) -> Void)?
    var onShowChangesChanged: ((Bool) -> Void)?

    private var versions: [MarkdownDocument.Version] = [] // newest first
    private let tableView = NSTableView()
    private let changesCheckbox = NSButton(checkboxWithTitle: "Show changes", target: nil, action: nil)
    private var isUpdatingSelection = false

    var showChanges: Bool {
        get { changesCheckbox.state == .on }
        set { changesCheckbox.state = newValue ? .on : .off }
    }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow

        let title = NSTextField(labelWithString: "History")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor

        changesCheckbox.target = self
        changesCheckbox.action = #selector(checkboxToggled(_:))
        changesCheckbox.toolTip = "Highlight what changed in the selected version"

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("version"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.rowHeight = 40
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        for subview in [title, changesCheckbox, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: background.safeAreaLayoutGuide.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            changesCheckbox.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            changesCheckbox.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: changesCheckbox.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        view = background
    }

    func update(versions newVersions: [MarkdownDocument.Version], selectedID: Int?) {
        _ = view
        versions = newVersions.reversed()
        isUpdatingSelection = true
        tableView.reloadData()
        if let selectedID, let row = versions.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        isUpdatingSelection = false
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        onShowChangesChanged?(sender.state == .on)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        versions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: VersionCell.identifier, owner: self) as? VersionCell ?? VersionCell()
        cell.configure(with: versions[row], isCurrent: row == 0)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, versions.indices.contains(tableView.selectedRow) else { return }
        onSelectVersion?(versions[tableView.selectedRow].id)
    }
}

/// Two-line row: the time of the version, and how many lines it added/removed.
private final class VersionCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("VersionCell")

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with version: MarkdownDocument.Version, isCurrent: Bool) {
        let today = Calendar.current.isDateInToday(version.updated)
        let time = version.updated.formatted(date: today ? .omitted : .abbreviated, time: .standard)

        let title = NSMutableAttributedString(string: time)
        if isCurrent {
            title.append(NSAttributedString(string: "  Current", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            ]))
        }
        titleLabel.attributedStringValue = title

        if version.id == 0 {
            detailLabel.stringValue = "Opened · \(version.added) lines"
        } else {
            let detail = NSMutableAttributedString()
            if version.added > 0 {
                detail.append(NSAttributedString(string: "+\(version.added)", attributes: [.foregroundColor: NSColor.systemGreen]))
            }
            if version.removed > 0 {
                if detail.length > 0 { detail.append(NSAttributedString(string: " ")) }
                detail.append(NSAttributedString(string: "−\(version.removed)", attributes: [.foregroundColor: NSColor.systemRed]))
            }
            let noun = version.added + version.removed == 1 ? "line" : "lines"
            detail.append(NSAttributedString(string: " \(noun)", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            detailLabel.attributedStringValue = detail
        }
    }
}
