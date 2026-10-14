import AppKit

_ = DocumentController() // the first one created becomes NSDocumentController.shared
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
