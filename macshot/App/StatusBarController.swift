import Cocoa

@MainActor
final class StatusBarController: NSObject {

    struct Actions {
        let captureArea: () -> Void
        let captureFullScreen: () -> Void
        let captureOCR: () -> Void
        let quickCapture: () -> Void
        let scrollCapture: () -> Void
        let setDelaySeconds: (Int) -> Void
        let showHistoryOverlay: () -> Void
        let openImage: () -> Void
        let openFromClipboard: () -> Void
        let openSettings: () -> Void
        let quit: () -> Void
    }

    private let historyMenuController: HistoryMenuController
    private let actions: Actions
    private let statusItem: NSStatusItem

    private var statusBarMenu: NSMenu?
    private var pendingMenuAction: (@Sendable () -> Void)?
    private(set) var interactionScreen: NSScreen?

    init(historyMenuController: HistoryMenuController, actions: Actions) {
        self.historyMenuController = historyMenuController
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func setup() {
        applyNormalStatusBarIcon()
        rebuildMenu()
    }

    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let captureAreaItem = makeMenuItem(
            title: L("Capture Area"),
            image: "crop",
            action: #selector(captureAreaFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .captureArea, to: captureAreaItem)
        menu.addItem(captureAreaItem)

        let captureFullItem = makeMenuItem(
            title: L("Capture Screen"),
            image: "desktopcomputer",
            action: #selector(captureFullScreenFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .captureFullScreen, to: captureFullItem)
        menu.addItem(captureFullItem)

        let captureOCRItem = makeMenuItem(
            title: L("Capture OCR"),
            image: "text.viewfinder",
            action: #selector(captureOCRFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .captureOCR, to: captureOCRItem)
        menu.addItem(captureOCRItem)

        let quickCaptureItem = makeMenuItem(
            title: L("Quick Capture"),
            image: "square.and.arrow.down",
            action: #selector(quickCaptureFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .quickCapture, to: quickCaptureItem)
        menu.addItem(quickCaptureItem)

        let scrollCaptureItem = makeMenuItem(
            title: L("Scroll Capture"),
            image: "scroll",
            action: #selector(scrollCaptureFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .scrollCapture, to: scrollCaptureItem)
        menu.addItem(scrollCaptureItem)

        let delayItem = NSMenuItem(title: L("Capture Delay"), action: nil, keyEquivalent: "")
        delayItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let delaySubmenu = NSMenu()
        delaySubmenu.autoenablesItems = false
        let currentDelay = UserDefaults.standard.integer(forKey: DefaultsKey.captureDelaySeconds)
        for seconds in [0, 3, 5, 10, 30] {
            let title = seconds == 0 ? L("None") : String(format: L("%d seconds"), seconds)
            let item = NSMenuItem(title: title, action: #selector(setDelaySeconds(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = seconds == currentDelay ? .on : .off
            delaySubmenu.addItem(item)
        }
        delayItem.submenu = delaySubmenu
        menu.addItem(delayItem)

        menu.addItem(.separator())
        menu.addItem(historyMenuController.makeMenuItem())

        let historyOverlayItem = makeMenuItem(
            title: L("Show History Panel"),
            image: "square.grid.2x2",
            action: #selector(showHistoryOverlayFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .historyOverlay, to: historyOverlayItem)
        menu.addItem(historyOverlayItem)

        menu.addItem(.separator())

        let openImageItem = makeMenuItem(
            title: L("Open Image..."),
            image: "photo.on.rectangle.angled",
            action: #selector(openImageFromMenu)
        )
        menu.addItem(openImageItem)

        let pasteImageItem = makeMenuItem(
            title: L("Open from Clipboard"),
            image: "doc.on.clipboard",
            action: #selector(openImageFromClipboard)
        )
        HotkeyManager.applyMenuShortcut(for: .openFromClipboard, to: pasteImageItem)
        menu.addItem(pasteImageItem)

        menu.addItem(.separator())

        let prefsItem = makeMenuItem(
            title: L("Settings..."),
            image: "gear",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("Quit macshot"), action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarMenu = menu
    }

    private func makeMenuItem(
        title: String,
        image systemName: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        return item
    }

    private func applyNormalStatusBarIcon() {
        guard let button = statusItem.button else { return }

        if let img = NSImage(named: "StatusBarIcon") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            button.image = img
        } else {
            button.title = "MacShot"
        }
        button.target = self
        button.action = #selector(statusBarIconClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        (button.cell as? NSButtonCell)?.highlightsBy = []
    }

    @objc private func statusBarIconClicked(_ sender: NSStatusBarButton) {
        interactionScreen = sender.window?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        ScreenCaptureManager.prewarm(screen: interactionScreen, mode: .full)

        if let modalWindow = NSApp.modalWindow {
            NSApp.stopModal()
            modalWindow.close()
            DispatchQueue.main.async { [weak self] in
                self?.showStatusBarMenu(from: sender)
            }
        } else {
            showStatusBarMenu(from: sender)
        }
    }

    private func showStatusBarMenu(from button: NSStatusBarButton) {
        guard let menu = statusBarMenu else { return }
        pendingMenuAction = nil
        let previousMenu = statusItem.menu
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = previousMenu
        runPendingMenuActionIfNeeded()
    }

    private func enqueueMenuAction(_ action: @escaping @Sendable () -> Void) {
        pendingMenuAction = action
    }

    private func runPendingMenuActionIfNeeded() {
        guard let action = pendingMenuAction else { return }
        pendingMenuAction = nil
        DispatchQueue.main.async(execute: action)
    }

    @objc private func captureAreaFromMenu() {
        enqueueMenuAction(actions.captureArea)
    }

    @objc private func captureFullScreenFromMenu() {
        enqueueMenuAction(actions.captureFullScreen)
    }

    @objc private func captureOCRFromMenu() {
        enqueueMenuAction(actions.captureOCR)
    }

    @objc private func quickCaptureFromMenu() {
        enqueueMenuAction(actions.quickCapture)
    }

    @objc private func scrollCaptureFromMenu() {
        enqueueMenuAction(actions.scrollCapture)
    }

    @objc private func showHistoryOverlayFromMenu() {
        enqueueMenuAction(actions.showHistoryOverlay)
    }

    @objc private func openImageFromMenu() {
        enqueueMenuAction(actions.openImage)
    }

    @objc private func openImageFromClipboard() {
        enqueueMenuAction(actions.openFromClipboard)
    }

    @objc private func openSettingsFromMenu() {
        enqueueMenuAction(actions.openSettings)
    }

    @objc private func quitFromMenu() {
        enqueueMenuAction(actions.quit)
    }

    @objc private func setDelaySeconds(_ sender: NSMenuItem) {
        actions.setDelaySeconds(sender.tag)
        if let menu = sender.menu {
            for item in menu.items {
                item.state = item.tag == sender.tag ? .on : .off
            }
        }
    }
}
