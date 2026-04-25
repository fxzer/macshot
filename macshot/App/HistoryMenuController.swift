import Cocoa

@MainActor
final class HistoryMenuController: NSObject, NSMenuDelegate {

    private let onPlayCopySound: () -> Void
    private weak var managedMenu: NSMenu?

    init(onPlayCopySound: @escaping () -> Void) {
        self.onPlayCopySound = onPlayCopySound
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("Recent Captures"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let menu = NSMenu()
        menu.delegate = self
        managedMenu = menu
        item.submenu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === managedMenu else { return }
        menu.removeAllItems()

        let entries = ScreenshotHistory.shared.entries
        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: L("No recent captures"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for (index, entry) in entries.enumerated() {
            let title = "\(entry.pixelWidth) \u{00D7} \(entry.pixelHeight)  —  \(entry.timeAgoString)"
            let item = NSMenuItem(title: title, action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = ScreenshotHistory.shared.loadThumbnail(for: entry)
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: L("Clear History"), action: #selector(clearHistory(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
    }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = L("Clear History?")
        alert.informativeText = L("This will permanently delete all screenshots from history.")
        alert.addButton(withTitle: L("Clear All"))
        alert.addButton(withTitle: L("Cancel"))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenshotHistory.shared.clear()
        }
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        ScreenshotHistory.shared.copyEntry(at: sender.tag)
        onPlayCopySound()
    }

    @objc private func clearHistory(_ sender: NSMenuItem) {
        confirmClearHistory()
    }
}
