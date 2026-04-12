import Cocoa

/// A custom tab bar that displays icons with labels, mimicking macOS Settings window tab style.
class TabBarView: NSView {
    struct TabItem {
        let identifier: String
        let title: String
        let iconName: String
    }

    private var tabs: [TabItem] = []
    private var tabButtons: [NSButton] = []
    private var tabBackgrounds: [NSView] = []
    private var tabIcons: [NSImageView] = []
    private var tabLabels: [NSTextField] = []
    private var tabContainers: [NSView] = []
    private var tabTrackingAreas: [NSTrackingArea] = []
    private var hoveredTabIndex: Int? = nil
    private var selectedTabIndex: Int? = nil
    private var stackView: NSStackView!
    private var separatorLine: NSBox?

    var onTabSelected: ((String) -> Void)?

    init(tabs: [TabItem], initialSelection: String) {
        self.tabs = tabs
        super.init(frame: .zero)
        setupUI(selectedTab: initialSelection)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(selectedTab: String) {
        // Container for centering
        let centeringContainer = NSView()
        centeringContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centeringContainer)

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .equalCentering  // Allow tabs to compress to content size
        stackView.spacing = 0  // No spacing between tabs
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        centeringContainer.addSubview(stackView)

        for (index, tab) in tabs.enumerated() {
            let isSelected = tab.identifier == selectedTab
            if isSelected {
                selectedTabIndex = index
            }
            let container = createTabItem(tab: tab, isSelected: isSelected, index: index)
            stackView.addArrangedSubview(container)
        }

        // Bottom separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        separatorLine = separator

        NSLayoutConstraint.activate([
            // Centering container fills available width
            centeringContainer.topAnchor.constraint(equalTo: topAnchor),
            centeringContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            centeringContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            centeringContainer.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -0),

            // StackView centered in container (justify-center effect)
            stackView.centerXAnchor.constraint(equalTo: centeringContainer.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centeringContainer.centerYAnchor),
            // No fixed height constraint - let tabs size themselves

            // Separator at bottom
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func createTabItem(tab: TabItem, isSelected: Bool, index: Int) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.clipsToBounds = false  // Important: prevent text clipping

        // Add tracking area for hover detection
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: ["tabIndex": index]
        )
        container.addTrackingArea(trackingArea)
        tabTrackingAreas.append(trackingArea)
        tabContainers.append(container)

        // Set minimum width for each tab item - no fixed height
        let widthConstraint = container.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
        widthConstraint.priority = .required  // High priority to ensure minimum width
        widthConstraint.isActive = true

        // Set minimum height but allow growth
        let heightConstraint = container.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        heightConstraint.priority = .defaultLow  // Allow to grow if needed
        heightConstraint.isActive = true

        // Background view for selected state - light gray like system Preferences
        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 6
        backgroundView.layer?.masksToBounds = false  // Important: prevent content clipping
        // Use a light gray color for selected tab background
        backgroundView.layer?.backgroundColor = (isSelected ? NSColor(hex: 0xE5E5E5, alpha: 0.8) : .clear).cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        tabBackgrounds.append(backgroundView)

        // Button
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.masksToBounds = false  // Don't clip subviews
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier(tab.identifier)
        button.target = self
        button.action = #selector(tabButtonClicked(_:))
        tabButtons.append(button)

        // Icon
        let iconView = NSImageView()
        if let icon = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.title) {
            iconView.image = icon
            iconView.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)  // Slightly smaller to fit better
        tabIcons.append(iconView)

        // Label
        let label = NSTextField(labelWithString: tab.title)
        label.font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.lineBreakMode = .byClipping
        label.clipsToBounds = false  // Important: prevent text clipping
        tabLabels.append(label)

        // Add subviews
        container.addSubview(backgroundView)
        container.addSubview(button)

        button.addSubview(iconView)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            // Background fills container with padding
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 1),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),

            // Button fills background
            button.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            button.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            // Icon centered in button
            iconView.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
            iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            // Label below icon
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4),

            // Ensure label is not compressed
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
        ])

        return container
    }

    @objc private func tabButtonClicked(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        selectTab(identifier: identifier)
    }

    func selectTab(identifier: String) {
        // Update selected index
        for (index, button) in tabButtons.enumerated() {
            guard let tabIdentifier = button.identifier?.rawValue else { continue }
            if tabIdentifier == identifier {
                selectedTabIndex = index
                break
            }
        }

        for (index, button) in tabButtons.enumerated() {
            guard let tabIdentifier = button.identifier?.rawValue else { continue }
            let isSelected = tabIdentifier == identifier

            // Update background color to light gray
            if index < tabBackgrounds.count {
                tabBackgrounds[index].layer?.backgroundColor = (isSelected ? NSColor(hex: 0xE5E5E5, alpha: 0.8) : .clear).cgColor
            }

            // Update icon color
            if index < tabIcons.count {
                tabIcons[index].contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            }

            // Update label style
            if index < tabLabels.count {
                tabLabels[index].font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular)
                tabLabels[index].textColor = isSelected ? .labelColor : .secondaryLabelColor
            }
        }

        onTabSelected?(identifier)
    }

    // MARK: - Mouse Tracking

    override func mouseEntered(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo,
              let tabIndex = userInfo["tabIndex"] as? Int else { return }

        hoveredTabIndex = tabIndex
        updateTabAppearance(for: tabIndex)
    }

    override func mouseExited(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo,
              let tabIndex = userInfo["tabIndex"] as? Int else { return }

        if hoveredTabIndex == tabIndex {
            hoveredTabIndex = nil
        }
        updateTabAppearance(for: tabIndex)
    }

    private func updateTabAppearance(for index: Int) {
        guard index < tabBackgrounds.count else { return }

        let isSelected = (selectedTabIndex == index)
        let isHovered = (hoveredTabIndex == index)

        // Determine background color
        if isSelected {
            // Selected state: darker gray
            tabBackgrounds[index].layer?.backgroundColor = NSColor(hex: 0xE5E5E5, alpha: 0.8).cgColor
        } else if isHovered {
            // Hover state: slightly lighter than selected
            tabBackgrounds[index].layer?.backgroundColor = NSColor(hex: 0xEAEAEA, alpha: 0.8).cgColor
        } else {
            // Normal state: clear
            tabBackgrounds[index].layer?.backgroundColor = .clear
        }
    }
}

// Helper extension for creating colors from hex values
extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
