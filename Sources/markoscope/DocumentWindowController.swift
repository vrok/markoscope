import AppKit
import WebKit

private extension NSToolbarItem.Identifier {
    static let theme = NSToolbarItem.Identifier("theme")
    static let textSize = NSToolbarItem.Identifier("textSize")
}

/// One window per open document: a web view that renders the Markdown
/// (see Resources/web) and a toolbar for picking the theme and text size.
final class DocumentWindowController: NSWindowController, NSToolbarDelegate, WKNavigationDelegate {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"]

    private let webView: WKWebView
    private let pageURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")!
    private var pageLoaded = false
    private var watcher: FileWatcher?
    private var pendingReload: DispatchWorkItem?
    private var preferencesObserver: NSObjectProtocol?
    private weak var themePopup: NSPopUpButton?
    private weak var textSizeControl: NSSegmentedControl?

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 420, height: 320)
        window.toolbarStyle = .unified
        window.contentView = webView
        window.center()
        super.init(window: window)
        windowFrameAutosaveName = "MarkdownDocumentWindow"

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
    }

    override var document: AnyObject? {
        didSet {
            startWatching()
            render()
        }
    }

    // MARK: - Rendering

    private func render() {
        guard pageLoaded, let doc = markdownDocument else { return }
        let baseURL = doc.fileURL?.deletingLastPathComponent().absoluteString ?? ""
        callJS("MV.load", ["markdown": doc.markdown, "baseURL": baseURL])
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

    // MARK: - Live reload

    @objc func reloadDocument(_ sender: Any?) {
        reloadFromDisk()
    }

    private func reloadFromDisk() {
        guard let doc = markdownDocument, doc.reloadFromDisk() else { return }
        render()
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
        [.flexibleSpace, .theme, .textSize]
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
