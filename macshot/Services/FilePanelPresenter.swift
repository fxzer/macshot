import Cocoa

enum FilePanelPresenter {
    private static let foregroundLevel = NSWindow.Level(258)

    static func begin(
        _ panel: NSSavePanel,
        ownerWindow: NSWindow? = nil,
        completionHandler: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        prepare(panel, ownerWindow: ownerWindow)
        panel.begin(completionHandler: completionHandler)
    }

    private static func prepare(_ panel: NSSavePanel, ownerWindow: NSWindow?) {
        let ownerRawLevel = ownerWindow?.level.rawValue ?? NSWindow.Level.normal.rawValue
        let requiredLevel = max(foregroundLevel.rawValue, ownerRawLevel + 1)
        panel.level = NSWindow.Level(max(panel.level.rawValue, requiredLevel))
        NSApp.activate(ignoringOtherApps: true)
    }
}
