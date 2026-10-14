import AppKit
import WebKit

private extension NSToolbarItem.Identifier {
    static let theme = NSToolbarItem.Identifier("theme")
    static let textSize = NSToolbarItem.Identifier("textSize")
    static let history = NSToolbarItem.Identifier("history")
    static let outline = NSToolbarItem.Identifier("outline")
}

/// One window per open document: a web view that renders the Markdown (see Resources/web),
/// a collapsible outline on the left, a collapsible version-history pane on the right,
/// and a toolbar for theme and text size.
final class DocumentWindowController: NSWindowController, NSToolbarDelegate, WKNavigationDelegate,
    WKScriptMessageHandler, NSMenuItemValidation {
    private static let messageHandlerName = "markoscope"
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"]

    private let webView: DocumentWebView
    private let pageURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")!
    private var pageLoaded = false
    private var watcher: FileWatcher?
    private var pendingReload: DispatchWorkItem?
    private var preferencesObserver: NSObjectProtocol?
    private var paneObservations: [NSKeyValueObservation] = []
    private weak var themePopup: NSPopUpButton?
    private weak var textSizeControl: NSSegmentedControl?

    private let outlineController = OutlineViewController()
    private let outlineItem: NSSplitViewItem
    private let historyController = HistoryViewController()
    private let historyItem: NSSplitViewItem
    /// The version being viewed; nil follows the latest one as the file changes.
    private var selectedVersionID: Int?
    private var showChanges = Preferences.shared.showChanges

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    init() {
        let configuration = WKWebViewConfiguration()
        let messageProxy = ScriptMessageProxy()
        configuration.userContentController.add(messageProxy, name: Self.messageHandlerName)
        webView = DocumentWebView(frame: .zero, configuration: configuration)

        // The window's content runs under the toolbar (so the outline sidebar can, like in Mail);
        // the document itself stays below it.
        let contentController = NSViewController()
        let container = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentController.view = container
        let contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = 360

        outlineItem = NSSplitViewItem(sidebarWithViewController: outlineController)
        outlineItem.canCollapse = true
        outlineItem.minimumThickness = 160
        outlineItem.maximumThickness = 400
        outlineItem.holdingPriority = NSLayoutConstraint.Priority(260)
        outlineItem.isCollapsed = !Preferences.shared.showOutline

        historyItem = NSSplitViewItem(viewController: historyController)
        historyItem.canCollapse = true
        historyItem.minimumThickness = 200
        historyItem.maximumThickness = 420
        historyItem.holdingPriority = NSLayoutConstraint.Priority(260) // window resizes go to the document
        historyItem.isCollapsed = !Preferences.shared.showHistory

        let splitController = NSSplitViewController()
        splitController.splitView.dividerStyle = .thin
        splitController.view.frame = NSRect(x: 0, y: 0, width: 1140, height: 900)
        container.frame = NSRect(x: 0, y: 0, width: 880, height: 900)
        historyController.view.frame = NSRect(x: 0, y: 0, width: 260, height: 900)
        outlineController.view.frame = NSRect(x: 0, y: 0, width: 230, height: 900)
        splitController.splitViewItems = [outlineItem, contentItem, historyItem]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 420, height: 320)
        window.toolbarStyle = .unified
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 1140, height: 900))
        window.center()
        super.init(window: window)
        windowFrameAutosaveName = "DocumentWindow"

        messageProxy.target = self
        // Remember whether the panes are open, however they were opened or closed
        // (button, menu, or dragging the divider), for the next window and the next launch.
        paneObservations = [
            outlineItem.observe(\.isCollapsed) { item, _ in Preferences.shared.showOutline = !item.isCollapsed },
            historyItem.observe(\.isCollapsed) { item, _ in Preferences.shared.showHistory = !item.isCollapsed },
        ]
        outlineController.onSelectHeading = { [weak self] id in self?.callJS("MV.scrollToHeading", id) }
        historyController.showChanges = showChanges
        historyController.onSelectVersion = { [weak self] id in self?.selectVersion(id) }
        historyController.onShowChangesChanged = { [weak self] on in self?.setShowChanges(on) }

        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")

        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        preferencesObserver = NotificationCenter.default.addObserver(
            forName: Preferences.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyPreferences()
        }
        applyPreferences()

        // Read access to "/" lets the page show images referenced relative to the Markdown file.
        webView.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
    }

    // MARK: - Messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "outline":
            let headings = (body["headings"] as? [[String: Any]] ?? []).compactMap { item -> OutlineViewController.Heading? in
                guard let id = item["id"] as? String, let title = item["title"] as? String,
                      let level = (item["level"] as? NSNumber)?.intValue else { return nil }
                return OutlineViewController.Heading(id: id, title: title, level: level)
            }
            outlineController.update(headings: headings)
        case "activeHeading":
            outlineController.setActiveHeading(body["id"] as? String)
        default:
            break
        }
    }

    override var document: AnyObject? {
        didSet {
            startWatching()
            refreshHistory()
            render()
        }
    }

    // MARK: - Rendering

    private var displayedIndex: Int? {
        guard let versions = markdownDocument?.versions, !versions.isEmpty else { return nil }
        if let selectedVersionID, let index = versions.firstIndex(where: { $0.id == selectedVersionID }) {
            return index
        }
        return versions.count - 1
    }

    /// Shows the selected version; with "Show changes" on, highlighted against the version before it.
    private func render(scrollToChange: Bool = false) {
        guard pageLoaded, let doc = markdownDocument, let index = displayedIndex else { return }
        let previous: Any = showChanges && index > 0 ? doc.versions[index - 1].text : NSNull()
        callJS("MV.load", [
            "markdown": doc.versions[index].text,
            "previous": previous,
            "baseURL": doc.fileURL?.deletingLastPathComponent().absoluteString ?? "",
            "scrollToChange": scrollToChange,
        ])
    }

    private func applyPreferences() {
        let prefs = Preferences.shared
        let theme = prefs.theme

        window?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        window?.backgroundColor = theme.background
        webView.underPageBackgroundColor = theme.background
        themePopup?.selectItem(at: Theme.allCases.firstIndex(of: theme) ?? 0)
        textSizeControl?.setEnabled(prefs.canDecreaseFontSize, forSegment: 0)
        textSizeControl?.setEnabled(prefs.canIncreaseFontSize, forSegment: 1)

        guard pageLoaded else { return }
        callJS("MV.setFontSize", prefs.fontSize)
        callJS("MV.setTheme", theme.rawValue)
    }

    /// Calls a page function with one JSON-encodable argument.
    private func callJS(_ function: String, _ argument: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: [argument]),
              let json = String(data: data, encoding: .utf8) else { return }
        // Trailing `undefined` so WebKit doesn't try to serialize a returned Promise.
        webView.evaluateJavaScript("\(function)(...\(json)); undefined") { _, error in
            if let error { NSLog("JavaScript error in \(function): \(error)") }
        }
    }

    // MARK: - History

    private func refreshHistory() {
        guard let doc = markdownDocument else { return }
        historyController.update(versions: doc.versions, selectedID: doc.versions[safe: displayedIndex]?.id)
    }

    private func selectVersion(_ id: Int) {
        // Picking the newest version means "follow the file" again.
        selectedVersionID = id == markdownDocument?.versions.last?.id ? nil : id
        render(scrollToChange: showChanges)
    }

    private func setShowChanges(_ on: Bool) {
        showChanges = on
        Preferences.shared.showChanges = on
        render(scrollToChange: on)
    }

    @objc func toggleOutline(_ sender: Any?) {
        outlineItem.animator().isCollapsed.toggle()
    }

    @objc func toggleHistory(_ sender: Any?) {
        historyItem.animator().isCollapsed.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHistory(_:)) {
            menuItem.title = historyItem.isCollapsed ? "Show History" : "Hide History"
        }
        if menuItem.action == #selector(toggleOutline(_:)) {
            menuItem.title = outlineItem.isCollapsed ? "Show Outline" : "Hide Outline"
        }
        return true
    }

    // MARK: - Live reload

    @objc func reloadDocument(_ sender: Any?) {
        reloadFromDisk()
    }

    private func reloadFromDisk() {
        guard let doc = markdownDocument, doc.reloadFromDisk() else { return }
        // A viewed older version doesn't change; only re-render when following the latest.
        if selectedVersionID == nil || displayedIndex == doc.versions.count - 1 { render() }
        refreshHistory()
    }

    private func startWatching() {
        watcher = nil
        guard let url = markdownDocument?.fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] replaced in
            self?.fileDidChange(replaced: replaced)
        }
    }

    private func fileDidChange(replaced: Bool) {
        // Debounce: editors often emit several events per save.
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if replaced { self.startWatching() }
            self.reloadFromDisk()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Items before the tracking separator sit over the outline sidebar, next to the window buttons.
        [.outline, .flexibleSpace, .sidebarTrackingSeparator, .flexibleSpace, .theme, .textSize, .history]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .theme:
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: Theme.allCases.map(\.title))
            popup.selectItem(at: Theme.allCases.firstIndex(of: Preferences.shared.theme) ?? 0)
            popup.target = self
            popup.action = #selector(themeChosen(_:))
            item.view = popup
            item.label = "Theme"
            item.toolTip = "Reading theme"
            themePopup = popup
        case .textSize:
            let smaller = NSImage(systemSymbolName: "textformat.size.smaller", accessibilityDescription: "Smaller text")!
            let larger = NSImage(systemSymbolName: "textformat.size.larger", accessibilityDescription: "Larger text")!
            let control = NSSegmentedControl(
                images: [smaller, larger], trackingMode: .momentary,
                target: self, action: #selector(textSizeClicked(_:))
            )
            control.setToolTip("Smaller text (⌘−)", forSegment: 0)
            control.setToolTip("Larger text (⌘+)", forSegment: 1)
            control.setEnabled(Preferences.shared.canDecreaseFontSize, forSegment: 0)
            control.setEnabled(Preferences.shared.canIncreaseFontSize, forSegment: 1)
            item.view = control
            item.label = "Text Size"
            textSizeControl = control
        case .outline:
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Outline")
            item.label = "Outline"
            item.toolTip = "Show or hide the outline (⌃⌘S)"
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleOutline(_:))
        case .history:
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "History")
            item.label = "History"
            item.toolTip = "Show or hide the version history (⌥⌘0)"
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleHistory(_:))
        default:
            return nil
        }
        return item
    }

    @objc private func themeChosen(_ sender: NSPopUpButton) {
        Preferences.shared.theme = Theme.allCases[sender.indexOfSelectedItem]
    }

    @objc private func textSizeClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            Preferences.shared.decreaseFontSize()
        } else {
            Preferences.shared.increaseFontSize()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        applyPreferences()
        render()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if url.scheme == "about" || (url.isFileURL && url.path == pageURL.path) {
            return decisionHandler(.allow)
        }
        // Everything else (clicked links, files dropped on the window) is handled natively.
        decisionHandler(.cancel)
        open(url)
    }

    private func open(_ url: URL) {
        if url.isFileURL {
            let fileURL = URL(fileURLWithPath: url.path)
            if Self.markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        } else if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension Array {
    subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}

/// Forwards page messages without the web view's content controller retaining the window controller.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
