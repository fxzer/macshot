import Cocoa

/// Real NSView top bar for the editor window. Pinned to top of container.
/// Contains: crop/flip/add-capture, zoom − / + (SF Symbols), zoom % menu, pixel dimensions.
class EditorTopBarView: NSView {

    weak var overlayView: OverlayView?
    var onTooltipChange: ((String?, NSView?) -> Void)?
    static let height: CGFloat = ToolbarLayout.stripThickness

    private var sizeLabel: NSTextField!
    private var zoomButton: NSButton!
    private var zoomOutButton: NSButton!
    private var zoomInButton: NSButton!
    private var doneButton: NSButton?
    var onDone: (() -> Void)?

    private var tooltips: [NSButton: String] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = ToolbarLayout.bgColor.cgColor
        autoresizingMask = [.width, .minYMargin]  // pin to top, stretch width

        sizeLabel = makeLabel("")
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.45)
        sizeLabel.alignment = .right
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let cropBtn = makeButton("crop", tooltip: L("Crop"), action: #selector(cropClicked))
        let flipHBtn = makeButton("arrow.left.and.right.righttriangle.left.righttriangle.right", tooltip: L("Flip Horizontal"), action: #selector(flipHClicked))
        let flipVBtn = makeButton("arrow.up.and.down.righttriangle.up.righttriangle.down", tooltip: L("Flip Vertical"), action: #selector(flipVClicked))
        let addCaptureBtn = makeButton("rectangle.badge.plus", tooltip: L("Add Capture"), action: #selector(addCaptureClicked))

        // Zoom: − / + icons (immediate), then percentage menu (presets / fit)
        zoomOutButton = makeButton("minus.magnifyingglass", tooltip: L("Zoom Out"), action: #selector(zoomOutAction))
        zoomInButton = makeButton("plus.magnifyingglass", tooltip: L("Zoom In"), action: #selector(zoomInAction))

        zoomButton = NSButton()
        zoomButton.bezelStyle = .recessed
        zoomButton.isBordered = false
        zoomButton.title = "100% ▾"
        zoomButton.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomButton.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.45)
        zoomButton.target = self
        zoomButton.action = #selector(zoomButtonClicked)

        // Bottom border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1.0).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // Layout with constraints
        for v: NSView in [sizeLabel, cropBtn, flipHBtn, flipVBtn, addCaptureBtn, zoomOutButton, zoomInButton, zoomButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),

            sizeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sizeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            zoomButton.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -12),
            zoomButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            zoomInButton.trailingAnchor.constraint(equalTo: zoomButton.leadingAnchor, constant: -6),
            zoomInButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomInButton.widthAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            zoomInButton.heightAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),

            zoomOutButton.trailingAnchor.constraint(equalTo: zoomInButton.leadingAnchor, constant: -2),
            zoomOutButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            zoomOutButton.widthAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            zoomOutButton.heightAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),

            cropBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cropBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            cropBtn.widthAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            cropBtn.heightAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),

            flipHBtn.leadingAnchor.constraint(equalTo: cropBtn.trailingAnchor, constant: 4),
            flipHBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            flipHBtn.widthAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            flipHBtn.heightAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),

            flipVBtn.leadingAnchor.constraint(equalTo: flipHBtn.trailingAnchor, constant: 4),
            flipVBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            flipVBtn.widthAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            flipVBtn.heightAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),

            addCaptureBtn.leadingAnchor.constraint(equalTo: flipVBtn.trailingAnchor, constant: 12),
            addCaptureBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addCaptureBtn.widthAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            addCaptureBtn.heightAnchor.constraint(equalToConstant: ToolbarLayout.buttonSize),
            addCaptureBtn.trailingAnchor.constraint(lessThanOrEqualTo: zoomOutButton.leadingAnchor, constant: -16),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let btn = HoverTrackingButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: ToolbarLayout.iconPointSize, weight: .medium))
        btn.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.85)
        tooltips[btn] = tooltip
        btn.target = self
        btn.action = action
        btn.onHover = { [weak self, weak btn] hovered in
            guard let self, let btn else { return }
            if hovered, let tooltip = self.tooltips[btn] {
                self.onTooltipChange?(tooltip, btn)
            } else {
                self.onTooltipChange?(nil, nil)
            }
        }
        return btn
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    func updateSizeLabel(width: Int, height: Int) {
        sizeLabel.stringValue = "\(width) × \(height)"
    }

    func updateZoom(_ magnification: CGFloat) {
        zoomButton.title = "\(Int(magnification * 100))% ▾"
    }

    // MARK: - Zoom dropdown

    @objc private func zoomButtonClicked() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let fitCanvas = NSMenuItem(title: L("Fit Canvas"), action: #selector(fitCanvasAction), keyEquivalent: "1")
        fitCanvas.keyEquivalentModifierMask = .command
        fitCanvas.target = self
        menu.addItem(fitCanvas)

        menu.addItem(.separator())

        let presets: [(String, CGFloat, String)] = [
            ("50%", 0.5, ""),
            ("100%", 1.0, "0"),
            ("200%", 2.0, ""),
        ]
        let currentMag = overlayView?.enclosingScrollView?.magnification ?? 1.0
        for (title, mag, key) in presets {
            let item = NSMenuItem(title: title, action: #selector(zoomPresetAction(_:)), keyEquivalent: key)
            if !key.isEmpty { item.keyEquivalentModifierMask = .command }
            item.target = self
            item.tag = Int(mag * 100)
            if abs(currentMag - mag) < 0.01 { item.state = .on }
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: zoomButton.bounds.height + 2), in: zoomButton)
    }

    @objc private func zoomInAction() {
        guard let sv = overlayView?.enclosingScrollView, let doc = sv.documentView else { return }
        let newMag = min(sv.maxMagnification, sv.magnification * 1.25)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            sv.animator().setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
        }
        updateZoom(newMag)
    }

    @objc private func zoomOutAction() {
        guard let sv = overlayView?.enclosingScrollView, let doc = sv.documentView else { return }
        let newMag = max(sv.minMagnification, sv.magnification / 1.25)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            sv.animator().setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
        }
        updateZoom(newMag)
    }

    @objc private func fitCanvasAction() {
        guard let sv = overlayView?.enclosingScrollView, let doc = sv.documentView else { return }
        let docUnscaledW = doc.frame.width / sv.magnification
        let docUnscaledH = doc.frame.height / sv.magnification
        guard docUnscaledW > 0, docUnscaledH > 0 else { return }
        let clipSize = sv.contentView.bounds.size
        let fitMag = min(clipSize.width / docUnscaledW, clipSize.height / docUnscaledH)
        let clamped = max(sv.minMagnification, min(sv.maxMagnification, fitMag))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            sv.animator().magnification = clamped
        }
        updateZoom(clamped)
    }

    @objc private func zoomPresetAction(_ sender: NSMenuItem) {
        let mag = CGFloat(sender.tag) / 100.0
        guard let sv = overlayView?.enclosingScrollView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            sv.animator().magnification = mag
        }
        updateZoom(mag)
    }

    // MARK: - Top bar actions

    /// Show a "Done" button for committing edits back to history.
    func showDoneButton() {
        guard doneButton == nil else { return }
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = true
        btn.title = L("Done")
        btn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        btn.contentTintColor = ToolbarLayout.accentColor
        btn.target = self
        btn.action = #selector(doneClicked)
        btn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(btn)
        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: zoomOutButton.leadingAnchor, constant: -12),
            btn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        doneButton = btn
    }

    @objc private func doneClicked() { onDone?() }

    @objc private func cropClicked() {
        guard let ov = overlayView else { return }
        ov.currentTool = ov.currentTool == .crop ? .arrow : .crop
        ov.rebuildToolbarLayout()
        ov.needsDisplay = true
    }

    @objc private func flipHClicked() { overlayView?.flipImageHorizontally() }
    @objc private func flipVClicked() { overlayView?.flipImageVertically() }
    @objc private func addCaptureClicked() { overlayView?.overlayDelegate?.overlayViewDidRequestAddCapture() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if overlayView?.isSharingActive == true {
            return nil
        }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

private final class HoverTrackingButton: NSButton {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
