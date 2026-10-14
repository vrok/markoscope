import AppKit

/// Rendering themes. Raw values match the `data-theme` names in style.css.
enum Theme: String, CaseIterable {
    case reader, clean, sepia, night

    var title: String {
        switch self {
        case .reader: "Reader"
        case .clean: "Clean"
        case .sepia: "Sepia"
        case .night: "Night"
        }
    }

    var isDark: Bool { self == .night }

    /// Must match `--bg` for the theme in style.css so there is no flash while loading.
    var background: NSColor {
        switch self {
        case .reader: NSColor(srgbRed: 0xFB / 255, green: 0xFA / 255, blue: 0xF7 / 255, alpha: 1)
        case .clean: .white
        case .sepia: NSColor(srgbRed: 0xF5 / 255, green: 0xEC / 255, blue: 0xD9 / 255, alpha: 1)
        case .night: NSColor(srgbRed: 0x1B / 255, green: 0x1C / 255, blue: 0x1F / 255, alpha: 1)
        }
    }
}

/// App-wide reading preferences, shared by all windows and persisted in ~/.markoscope.toml:
///
///     theme = "reader"
///     font_size = 18
final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("PreferencesDidChange")

    static let fontSizes = [12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 26, 28, 32]
    static let defaultFontSize = 18

    private let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".markoscope.toml")

    var theme: Theme = .reader {
        didSet { changed() }
    }

    var fontSize: Int = Preferences.defaultFontSize {
        didSet {
            let clamped = Self.clamp(fontSize)
            if fontSize != clamped { fontSize = clamped } else { changed() }
        }
    }

    private var isLoading = false

    private init() {
        isLoading = true
        load()
        isLoading = false
        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
    }

    private static func clamp(_ size: Int) -> Int {
        min(max(size, fontSizes.first!), fontSizes.last!)
    }

    private func changed() {
        guard !isLoading else { return }
        save()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: - TOML file

    /// Reads the flat `key = value` subset of TOML this file uses; unknown keys are ignored.
    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), let end = value.dropFirst().firstIndex(of: "\"") {
                value = String(value[value.index(after: value.startIndex)..<end])
            } else if let comment = value.firstIndex(of: "#") {
                value = value[..<comment].trimmingCharacters(in: .whitespaces)
            }
            switch key {
            case "theme":
                if let theme = Theme(rawValue: value.lowercased()) { self.theme = theme }
            case "font_size":
                if let size = Int(value) { fontSize = Self.clamp(size) }
            default:
                break
            }
        }
    }

    private func save() {
        let text = """
        # Markoscope settings (rewritten by the app)
        # theme: \(Theme.allCases.map(\.rawValue).joined(separator: ", "))
        theme = "\(theme.rawValue)"
        font_size = \(fontSize)

        """
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Could not save settings to \(fileURL.path): \(error)")
        }
    }

    var canIncreaseFontSize: Bool { fontSize < Self.fontSizes.last! }
    var canDecreaseFontSize: Bool { fontSize > Self.fontSizes.first! }

    func increaseFontSize() {
        if let next = Self.fontSizes.first(where: { $0 > fontSize }) { fontSize = next }
    }

    func decreaseFontSize() {
        if let previous = Self.fontSizes.last(where: { $0 < fontSize }) { fontSize = previous }
    }

    func resetFontSize() {
        fontSize = Self.defaultFontSize
    }
}
