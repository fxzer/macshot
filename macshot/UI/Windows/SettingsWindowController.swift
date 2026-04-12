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

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    // Tab content views
    private var tabContentViews: [String: NSView] = [:]
    private var currentTabIdentifier: String = "interface"
    private var contentContainerView: NSView!
    private var tabBarView: TabBarView!

    var onHotkeyChanged: (() -> Void)?

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

        // Listen for language changes
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

    // MARK: - Top-level layout

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // Create tab bar with icons (all use outline style)
        let tabs = [
            TabBarView.TabItem(identifier: "interface", title: L("Interface"), iconName: "rectangle.3.group"),
            TabBarView.TabItem(identifier: "capture", title: L("Capture"), iconName: "camera"),
            TabBarView.TabItem(identifier: "output", title: L("Output"), iconName: "arrow.down.doc"),
            TabBarView.TabItem(identifier: "shortcuts", title: L("Shortcuts"), iconName: "command"),
            TabBarView.TabItem(identifier: "tools", title: L("Tools"), iconName: "wrench.and.screwdriver"),
            TabBarView.TabItem(identifier: "recording", title: L("Recording"), iconName: "record.circle"),
            TabBarView.TabItem(identifier: "uploads", title: L("Uploads"), iconName: "cloud"),
            TabBarView.TabItem(identifier: "about", title: L("About"), iconName: "info.circle"),
        ]

        let tabBar = TabBarView(tabs: tabs, initialSelection: currentTabIdentifier)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onTabSelected = { [weak self] identifier in
            self?.switchTab(to: identifier)
        }
        tabBarView = tabBar  // Save reference

        // Content container for tab views
        contentContainerView = NSView()
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.wantsLayer = true

        // Prepare all tab content views
        tabContentViews["interface"] = makeInterfaceTabView()
        tabContentViews["capture"] = makeCaptureTabView()
        tabContentViews["output"] = makeOutputTabView()
        tabContentViews["shortcuts"] = makeShortcutsTabView()
        tabContentViews["tools"] = makeToolsTabView()
        tabContentViews["recording"] = makeRecordingTabView()
        tabContentViews["uploads"] = makeUploadsTabView()
        tabContentViews["about"] = makeAboutTabView()

        // Add initial tab content
        if let initialView = tabContentViews[currentTabIdentifier] {
            contentContainerView.addSubview(initialView)
            initialView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                initialView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
                initialView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
                initialView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
                initialView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            ])
        }

        // Footer separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        // Footer labels
        let madeBy = NSTextField(labelWithString: "\(L("Made by")) sw33tLie")
        madeBy.font = NSFont.systemFont(ofSize: 11)
        madeBy.textColor = .secondaryLabelColor
        madeBy.translatesAutoresizingMaskIntoConstraints = false

        let linkBtn = NSButton(title: "github.com/sw33tLie/macshot", target: self, action: #selector(openGitHub))
        linkBtn.bezelStyle = .inline
        linkBtn.isBordered = false
        linkBtn.font = NSFont.systemFont(ofSize: 11)
        linkBtn.attributedTitle = NSAttributedString(string: "github.com/sw33tLie/macshot", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        linkBtn.translatesAutoresizingMaskIntoConstraints = false

        let footerStack = NSStackView(views: [madeBy, NSView(), linkBtn])
        footerStack.orientation = .horizontal
        footerStack.spacing = 0
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(tabBar)
        cv.addSubview(contentContainerView)
        cv.addSubview(sep)
        cv.addSubview(footerStack)

        NSLayoutConstraint.activate([
            // Tab bar at top
            tabBar.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
            tabBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 57),  // 56 bar + 1 separator

            // Content container below tab bar
            contentContainerView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: sep.topAnchor, constant: -0),

            // Footer separator
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -6),
            sep.heightAnchor.constraint(equalToConstant: 1),

            // Footer
            footerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            footerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            footerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            footerStack.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Tab View Factories (SwiftUI via NSHostingView)

    private func makeInterfaceTabView() -> NSView {
        return NSHostingView(rootView: InterfaceSettingsView())
    }

    private func makeCaptureTabView() -> NSView {
        return NSHostingView(rootView: CaptureSettingsView())
    }

    private func makeOutputTabView() -> NSView {
        return NSHostingView(rootView: OutputSettingsView())
    }

    private func makeShortcutsTabView() -> NSView {
        return NSHostingView(rootView: ShortcutsSettingsView(onHotkeyChanged: onHotkeyChanged))
    }

    private func makeToolsTabView() -> NSView {
        return NSHostingView(rootView: ToolsSettingsView())
    }

    private func makeRecordingTabView() -> NSView {
        return NSHostingView(rootView: RecordingSettingsView())
    }

    private func makeUploadsTabView() -> NSView {
        return NSHostingView(rootView: UploadsSettingsView())
    }

    private func makeAboutTabView() -> NSView {
        return NSHostingView(rootView: AboutSettingsView())
    }

    // MARK: - Language Change

    @objc private func languageDidChangeNotification(_ notification: Notification) {
        // Refresh window title
        window?.title = L("macshot Settings")

        // Refresh tab bar labels
        updateTabBarLabels()

        // Refresh footer text
        updateFooterText()

        // Recreate the current tab view with new language
        refreshCurrentTabView()
    }

    private func updateTabBarLabels() {
        guard let tabBar = tabBarView else { return }

        let tabs: [TabBarView.TabItem] = [
            TabBarView.TabItem(identifier: "interface", title: L("Interface"), iconName: "rectangle.3.group"),
            TabBarView.TabItem(identifier: "capture", title: L("Capture"), iconName: "camera"),
            TabBarView.TabItem(identifier: "output", title: L("Output"), iconName: "arrow.down.doc"),
            TabBarView.TabItem(identifier: "shortcuts", title: L("Shortcuts"), iconName: "command"),
            TabBarView.TabItem(identifier: "tools", title: L("Tools"), iconName: "wrench.and.screwdriver"),
            TabBarView.TabItem(identifier: "recording", title: L("Recording"), iconName: "record.circle"),
            TabBarView.TabItem(identifier: "uploads", title: L("Uploads"), iconName: "cloud"),
            TabBarView.TabItem(identifier: "about", title: L("About"), iconName: "info.circle"),
        ]

        tabBar.updateTabs(tabs, selectedIdentifier: currentTabIdentifier)
    }

    private func updateFooterText() {
        guard let cv = window?.contentView else { return }

        // Find the "Made by" label in the footer
        for subview in cv.subviews {
            if let stack = subview as? NSStackView, stack.orientation == .horizontal {
                for stackSubview in stack.arrangedSubviews {
                    if let label = stackSubview as? NSTextField, label.stringValue.contains("sw33tLie") {
                        label.stringValue = "\(L("Made by")) sw33tLie"
                        break
                    }
                }
            }
        }
    }

    private func refreshCurrentTabView() {
        // Remove current tab view
        if let currentView = tabContentViews[currentTabIdentifier] {
            currentView.removeFromSuperview()
        }

        // Clear all cached tab views so they will be recreated with new language when needed
        tabContentViews.removeAll()

        // Recreate and add the current tab view with new language
        let newView: NSView
        switch currentTabIdentifier {
        case "interface": newView = makeInterfaceTabView()
        case "capture": newView = makeCaptureTabView()
        case "output": newView = makeOutputTabView()
        case "shortcuts": newView = makeShortcutsTabView()
        case "tools": newView = makeToolsTabView()
        case "recording": newView = makeRecordingTabView()
        case "uploads": newView = makeUploadsTabView()
        case "about": newView = makeAboutTabView()
        default: newView = NSView()
        }

        tabContentViews[currentTabIdentifier] = newView
        contentContainerView.addSubview(newView)
        newView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            newView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            newView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/sw33tLie/macshot") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Tab Switching

    private func switchTab(to identifier: String) {
        guard identifier != currentTabIdentifier else { return }

        // Get or create the tab view
        var newView = tabContentViews[identifier]
        if newView == nil {
            // Tab view doesn't exist, create it
            switch identifier {
            case "interface": newView = makeInterfaceTabView()
            case "capture": newView = makeCaptureTabView()
            case "output": newView = makeOutputTabView()
            case "shortcuts": newView = makeShortcutsTabView()
            case "tools": newView = makeToolsTabView()
            case "recording": newView = makeRecordingTabView()
            case "uploads": newView = makeUploadsTabView()
            case "about": newView = makeAboutTabView()
            default: newView = NSView()
            }
            tabContentViews[identifier] = newView
        }

        guard let view = newView else { return }

        // Remove old view
        if let oldView = tabContentViews[currentTabIdentifier] {
            oldView.removeFromSuperview()
        }

        // Add new view
        contentContainerView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])

        currentTabIdentifier = identifier
    }

    func showWindow() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.returnFocusIfNeeded()
    }
}
