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
        let recordArea: () -> Void
        let recordScreen: () -> Void
        let showHistoryOverlay: () -> Void
        let openImage: () -> Void
        let openFromClipboard: () -> Void
        let openSettings: () -> Void
        let checkForUpdates: () -> Void
        let quit: () -> Void
        let stopRecording: () -> Void
        let pauseRecording: () -> Void
        let resumeRecording: () -> Void
    }

    private let historyMenuController: HistoryMenuController
    private let actions: Actions
    private let statusItem: NSStatusItem

    private var statusBarMenu: NSMenu?
    private var recordingStatusItemView: RecordingStatusItemView?
    private var pendingMenuAction: (() -> Void)?
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
        let currentDelay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")
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

        let recordAreaItem = makeMenuItem(
            title: L("Record Area"),
            image: "record.circle",
            action: #selector(recordAreaFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .recordArea, to: recordAreaItem)
        menu.addItem(recordAreaItem)

        let recordScreenItem = makeMenuItem(
            title: L("Record Screen"),
            image: "menubar.dock.rectangle",
            action: #selector(recordScreenFromMenu)
        )
        HotkeyManager.applyMenuShortcut(for: .recordScreen, to: recordScreenItem)
        menu.addItem(recordScreenItem)

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

        let updateItem = makeMenuItem(
            title: L("Check for Updates..."),
            image: "arrow.triangle.2.circlepath",
            action: #selector(checkForUpdatesFromMenu)
        )
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("Quit macshot"), action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarMenu = menu
    }

    func enterRecordingMode(controlsMode: RecordingControlsMode) {
        removeRecordingStatusItemView()

        if controlsMode == .menuBar {
            installRecordingStatusItemView()
        } else if let button = statusItem.button {
            statusItem.length = NSStatusItem.variableLength
            button.title = ""
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording")
            button.image?.isTemplate = true
            button.image?.size = NSSize(width: 22, height: 22)
            button.target = self
            button.action = #selector(stopRecordingFromStatusItem)
        }

        statusItem.menu = nil
    }

    func exitRecordingMode() {
        removeRecordingStatusItemView()
        statusItem.length = NSStatusItem.variableLength
        applyNormalStatusBarIcon()
        rebuildMenu()
    }

    func updateRecording(seconds: Int) {
        recordingStatusItemView?.update(elapsedSeconds: seconds)
    }

    func setRecordingPaused(_ paused: Bool) {
        recordingStatusItemView?.setPaused(paused)
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
        ScreenCaptureManager.prewarm()
        interactionScreen = sender.window?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        let fallbackAnchorRect = statusBarMenuAnchorRect(for: sender)

        if let modalWindow = NSApp.modalWindow {
            NSApp.stopModal()
            modalWindow.close()
            DispatchQueue.main.async { [weak self] in
                self?.showStatusBarMenu(from: sender, fallbackAnchorRect: fallbackAnchorRect)
            }
        } else {
            showStatusBarMenu(from: sender, fallbackAnchorRect: fallbackAnchorRect)
        }
    }

    private func statusBarMenuAnchorRect(for button: NSStatusBarButton) -> NSRect? {
        guard let window = button.window else { return nil }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRectInWindow)
    }

    private func statusBarMenuAnchorPoint(for button: NSStatusBarButton) -> NSPoint {
        if button.isFlipped {
            return NSPoint(x: button.bounds.minX, y: button.bounds.maxY + 7)
        }
        return NSPoint(x: button.bounds.minX, y: button.bounds.minY - 7)
    }

    private func showStatusBarMenu(from button: NSStatusBarButton, fallbackAnchorRect: NSRect? = nil) {
        guard let menu = statusBarMenu else { return }
        pendingMenuAction = nil

        let oldAction = button.action
        let oldTarget = button.target
        button.action = nil
        button.target = nil
        defer {
            button.action = oldAction
            button.target = oldTarget
        }

        if button.window != nil {
            menu.popUp(positioning: nil, at: statusBarMenuAnchorPoint(for: button), in: button)
            runPendingMenuActionIfNeeded()
            return
        }

        guard let screenFrame = fallbackAnchorRect ?? statusBarMenuAnchorRect(for: button) else { return }
        let menuPoint = NSPoint(x: screenFrame.minX, y: screenFrame.minY - 7)
        menu.popUp(positioning: nil, at: menuPoint, in: nil)
        runPendingMenuActionIfNeeded()
    }

    private func enqueueMenuAction(_ action: @escaping () -> Void) {
        pendingMenuAction = action
    }

    private func runPendingMenuActionIfNeeded() {
        guard let action = pendingMenuAction else { return }
        pendingMenuAction = nil
        DispatchQueue.main.async(execute: action)
    }

    private func installRecordingStatusItemView() {
        guard let button = statusItem.button else { return }

        let controlsView = RecordingStatusItemView(frame: .zero)
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.update(elapsedSeconds: 0)
        controlsView.onStopRecording = { [weak self] in
            self?.actions.stopRecording()
        }
        controlsView.onPauseRecording = { [weak self] in
            self?.actions.pauseRecording()
        }
        controlsView.onResumeRecording = { [weak self] in
            self?.actions.resumeRecording()
        }

        button.image = nil
        button.title = ""
        button.target = nil
        button.action = nil

        statusItem.length = RecordingStatusItemView.preferredWidth + 6
        button.addSubview(controlsView)
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 3),
            controlsView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
            controlsView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            controlsView.heightAnchor.constraint(equalToConstant: controlsView.intrinsicContentSize.height),
        ])

        recordingStatusItemView = controlsView
    }

    private func removeRecordingStatusItemView() {
        recordingStatusItemView?.removeFromSuperview()
        recordingStatusItemView = nil
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

    @objc private func recordAreaFromMenu() {
        enqueueMenuAction(actions.recordArea)
    }

    @objc private func recordScreenFromMenu() {
        enqueueMenuAction(actions.recordScreen)
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

    @objc private func checkForUpdatesFromMenu() {
        enqueueMenuAction(actions.checkForUpdates)
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

    @objc private func stopRecordingFromStatusItem() {
        actions.stopRecording()
    }
}
