import AppKit

/// Builds the menu bar in code (the app has no nib).
enum MainMenu {
    static func make() -> NSMenu {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Markoscope"
        let mainMenu = NSMenu()

        let appMenu = submenu(in: mainMenu, title: appName)
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(in: mainMenu, title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recentMenu = NSMenu(title: "Open Recent")
        // AppKit fills this menu with recent documents because it contains "Clear Menu".
        recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recentMenu
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Reload", action: #selector(DocumentWindowController.reloadDocument(_:)), keyEquivalent: "r")

        let editMenu = submenu(in: mainMenu, title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenu = submenu(in: mainMenu, title: "View")
        for (index, theme) in Theme.allCases.enumerated() {
            let item = viewMenu.addItem(withTitle: theme.title, action: #selector(AppDelegate.selectTheme(_:)), keyEquivalent: "\(index + 1)")
            item.representedObject = theme.rawValue
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Larger Text", action: #selector(AppDelegate.increaseTextSize(_:)), keyEquivalent: "+")
        let largerAlias = viewMenu.addItem(withTitle: "Larger Text", action: #selector(AppDelegate.increaseTextSize(_:)), keyEquivalent: "=")
        largerAlias.isHidden = true
        largerAlias.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(withTitle: "Smaller Text", action: #selector(AppDelegate.decreaseTextSize(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(AppDelegate.resetTextSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        let windowMenu = submenu(in: mainMenu, title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private static func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let submenu = NSMenu(title: title)
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        return submenu
    }
}
