import Cocoa
import SwiftUI

/// Settings window that intercepts Cmd+Q to close itself instead of quitting the app.
private class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Status-bar windows do not get the standard Edit menu handling,
        // so forward common text-editing shortcuts to the active field editor.
        if let textResponder = firstResponder as? NSTextView {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.keyCode {
                case 8:  textResponder.copy(nil); return true  // C
                case 7:  textResponder.cut(nil); return true  // X
                case 9:  textResponder.paste(nil); return true  // V
                case 0:  textResponder.selectAll(nil); return true  // A
                case 6:  textResponder.undoManager?.undo(); return true  // Z
                default: break
                }
            }
            if flags == [.command, .shift], event.keyCode == 6 {  // Z
                textResponder.undoManager?.redo()
                return true
            }
        }

        if event.modifierFlags.contains(.command) && event.keyCode == 12 {  // Q
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class SettingsHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onHotkeyChanged: (() -> Void)? {
        didSet {
            updateRootView()
        }
    }
    private var hostingView: NSView?

    init(onHotkeyChanged: (() -> Void)? = nil) {
        self.onHotkeyChanged = onHotkeyChanged
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("macshot Settings")
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()

        // Listen for language changes to update window title
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChangeNotification),
            name: LanguageManager.changedNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let hostingView = SettingsHostingView(rootView: makeSettingsView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView = hostingView

        // Add hosting view to window
        contentView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Language Change

    @objc private func languageDidChangeNotification(_ notification: Notification) {
        // Update window title when language changes
        window?.title = L("macshot Settings")
        // SwiftUI view will automatically refresh via NotificationCenter publisher
    }

    private func makeSettingsView() -> SwiftUISettingsView {
        SwiftUISettingsView(
            onHotkeyChanged: onHotkeyChanged,
            onWindowClose: { [weak self] in
                self?.close()
            }
        )
    }

    private func updateRootView() {
        guard let hostingView = hostingView as? SettingsHostingView<SwiftUISettingsView> else { return }
        hostingView.rootView = makeSettingsView()
    }

    // MARK: - Public Methods

    func showWindow() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let hostingView {
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(hostingView)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.returnFocusIfNeeded()
    }
}
