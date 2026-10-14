import AppKit

/// The left-hand pane. For a single file it shows the outline; for a file opened from a folder
/// it can switch between the folder's files and the outline.
final class SidebarViewController: NSViewController {
    enum Mode: Int {
        case files, outline
    }

    let outline = OutlineViewController()
    let files = FilesViewController()

    private let modeControl = NSSegmentedControl(labels: ["Files", "Outline"], trackingMode: .selectOne, target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "Outline")
    private var mode: Mode = .outline

    /// Whether the Files list is available (the document was opened from a folder).
    var showsFiles = false {
        didSet {
            guard showsFiles != oldValue else { return }
            setMode(showsFiles ? .files : .outline)
        }
    }

    override func loadView() {
        let background = FileDropEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow

        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        modeControl.segmentDistribution = .fillEqually
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))

        addChild(outline)
        addChild(files)
        for subview in [titleLabel, modeControl, outline.view, files.view] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(subview)
        }
        let top = background.safeAreaLayoutGuide.topAnchor
        var constraints = [
            titleLabel.topAnchor.constraint(equalTo: top, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            modeControl.topAnchor.constraint(equalTo: top, constant: 10),
            modeControl.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            modeControl.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
        ]
        for child in [outline.view, files.view] {
            constraints += [
                child.topAnchor.constraint(equalTo: top, constant: 40),
                child.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                child.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        view = background
        setMode(mode)
    }

    private func setMode(_ newMode: Mode) {
        mode = newMode
        guard isViewLoaded else { return }
        modeControl.isHidden = !showsFiles
        titleLabel.isHidden = showsFiles
        modeControl.selectedSegment = newMode.rawValue
        files.view.isHidden = newMode != .files
        outline.view.isHidden = newMode != .outline
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        setMode(Mode(rawValue: sender.selectedSegment) ?? .outline)
    }
}
