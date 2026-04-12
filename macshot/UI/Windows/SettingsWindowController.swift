import Cocoa
import SwiftUI

/// Settings window that intercepts Cmd+Q to close itself instead of quitting the app.
private class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
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

    var onHotkeyChanged: (() -> Void)?
    private var hostingView: NSView?

    init() {
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

        // Create SwiftUI settings view
        let settingsView = SwiftUISettingsView(
            onHotkeyChanged: onHotkeyChanged,
            onWindowClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView = SettingsHostingView(rootView: settingsView)
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
