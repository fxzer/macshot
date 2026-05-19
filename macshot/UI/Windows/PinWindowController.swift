import Cocoa
import UniformTypeIdentifiers

@MainActor
protocol PinWindowControllerDelegate: AnyObject {
    func pinWindowDidClose(_ controller: PinWindowController)
}

@MainActor
class PinWindowController {

    weak var delegate: PinWindowControllerDelegate?

    private var window: NSPanel?
    private var pinView: PinView?
    private let imageAsset: CaptureImageAsset
    private let image: NSImage

    init(imageAsset: CaptureImageAsset, at origin: NSPoint? = nil) {
        self.imageAsset = imageAsset
        self.image = imageAsset.displayImage

        let size = imageAsset.displaySize
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame

        // Center on screen, cap at 80% of screen size
        let scale = PinWindowSizing.fittedScale(imageSize: size, visibleFrame: screenFrame)
        let windowSize = PinWindowSizing.windowSize(imageSize: size, scale: scale)

        // Use provided origin, or center on screen
        let windowOrigin: NSPoint
        if let origin = origin {
            windowOrigin = origin
        } else {
            windowOrigin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2
            )
        }

        let panel = PinPanel(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = size
        // Allow scroll/magnify events to reach the view even when panel is not key
        panel.becomesKeyOnlyIfNeeded = true

        let view = PinView(imageAsset: imageAsset)
        view.frame = NSRect(origin: .zero, size: windowSize)
        view.autoresizingMask = [.width, .height]
        view.onClose = { [weak self] in
            self?.close()
        }
        view.onEdit = { [weak self] in
            self?.openInEditor()
        }
        view.onZoom = { [weak self] factor, viewPoint in
            self?.zoom(by: factor, around: viewPoint)
        }
        view.onResetZoom = { [weak self] in
            self?.resetZoom()
        }
        view.zoomPercent = Int(round(scale * 100))

        panel.contentView = view
        self.window = panel
        self.pinView = view
    }

    convenience init(image: NSImage, at origin: NSPoint? = nil) {
        self.init(imageAsset: Self.makeImageAsset(from: image), at: origin)
    }

    private static func makeImageAsset(from image: NSImage) -> CaptureImageAsset {
        let standardizer: @Sendable (CGImage) -> CGImage? = { rawImage in
            ScreenCaptureManager.convertTo8BitBGRA(rawImage)
        }

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CaptureImageAsset(
                displayCGImage: cgImage,
                pointSize: image.size,
                standardizer: standardizer
            )
        }

        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let cgImage = bitmap.cgImage {
            return CaptureImageAsset(
                displayCGImage: cgImage,
                pointSize: image.size,
                standardizer: standardizer
            )
        }

        let description = NSStringFromSize(image.size)
        assertionFailure("PinWindowController 无法从 NSImage 创建 CGImage，已退回透明占位图。size=\(description)")
        NSLog("[macshot] PinWindowController: failed to create CGImage for pinned image, using transparent placeholder. size=\(description)")

        return CaptureImageAsset(
            displayCGImage: makeFallbackDisplayImage(size: image.size),
            pointSize: image.size,
            standardizer: standardizer
        )
    }

    private static func makeFallbackDisplayImage(size: NSSize) -> CGImage {
        let width = max(1, Int(round(size.width)))
        let height = max(1, Int(round(size.height)))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let image = context.makeImage() else {
            let provider = CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!
            return CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
        }
        return image
    }

    private func zoom(by factor: CGFloat, around viewPoint: NSPoint) {
        guard let window = window else { return }
        let oldFrame = window.frame
        let oldSize = oldFrame.size

        // Compute new size, clamped
        let currentScale = oldSize.width / imageAsset.displaySize.width
        let newScale = PinWindowSizing.clampedScale(currentScale * factor)
        if abs(newScale - currentScale) < 0.001 { return }

        let newSize = PinWindowSizing.windowSize(imageSize: imageAsset.displaySize, scale: newScale)

        // Anchor: the screen point under the cursor stays fixed
        let cursorScreenPoint = NSPoint(
            x: oldFrame.origin.x + viewPoint.x,
            y: oldFrame.origin.y + viewPoint.y
        )
        let fractionX = viewPoint.x / oldSize.width
        let fractionY = viewPoint.y / oldSize.height
        let newOrigin = NSPoint(
            x: cursorScreenPoint.x - fractionX * newSize.width,
            y: cursorScreenPoint.y - fractionY * newSize.height
        )

        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        pinView?.zoomPercent = Int(round(newScale * 100))
    }

    private func resetZoom() {
        guard let window = window else { return }
        let oldFrame = window.frame
        let centerX = oldFrame.midX
        let centerY = oldFrame.midY
        let oneToOneSize = PinWindowSizing.windowSize(
            imageSize: imageAsset.displaySize,
            scale: PinWindowSizing.oneToOneScale
        )
        let newOrigin = NSPoint(
            x: centerX - oneToOneSize.width / 2,
            y: centerY - oneToOneSize.height / 2
        )
        window.setFrame(NSRect(origin: newOrigin, size: oneToOneSize), display: true)
        pinView?.zoomPercent = 100
    }

    func show() {
        window?.orderFrontRegardless()
    }

    func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        pinView = nil
        delegate?.pinWindowDidClose(self)
    }

    private func openInEditor() {
        DetachedEditorWindowController.open(image: imageAsset.displayImage)
        close()
    }

    func updateLocalization() {
        // Pin window is borderless, no title to update
        pinView?.needsDisplay = true
    }
}

// MARK: - Pin Panel (receives gesture events without activating the app)

private class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // Don't let Cmd+Q propagate to the app — just close the pin
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == 12 {  // Q
            (contentView as? PinView)?.onClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Pin Content View

private class PinView: NSView {

    var onClose: (() -> Void)?
    var onEdit: (() -> Void)?
    var onZoom: ((CGFloat, NSPoint) -> Void)?
    var onResetZoom: (() -> Void)?

    private let imageAsset: CaptureImageAsset
    private let image: NSImage
    private var closeButton: NSButton?
    private var editButton: NSButton?
    private var zoomLabel: NSTextField?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var showsDecorations = true  // Controls corner, border, and shadow together

    var zoomPercent: Int = 100 {
        didSet {
            zoomLabel?.stringValue = "\(zoomPercent)%"
            zoomLabel?.sizeToFit()
            needsLayout = true
        }
    }

    init(imageAsset: CaptureImageAsset) {
        self.imageAsset = imageAsset
        self.image = imageAsset.displayImage
        super.init(frame: .zero)
        setupButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeOverlayButton(symbol: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 12
        btn.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.image = img
        btn.contentTintColor = .white
        btn.target = self
        btn.action = action
        btn.isHidden = true
        return btn
    }

    private func setupButtons() {
        let edit = makeOverlayButton(symbol: "pencil", action: #selector(editClicked))
        addSubview(edit)
        editButton = edit

        let close = makeOverlayButton(symbol: "xmark", action: #selector(closeClicked))
        addSubview(close)
        closeButton = close

        let label = VerticallyCenteredTextField(labelWithString: "100%")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 12
        label.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        label.alignment = .center
        label.isHidden = true
        addSubview(label)
        zoomLabel = label
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func editClicked() {
        onEdit?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        editButton?.isHidden = false
        closeButton?.isHidden = false
        zoomLabel?.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        editButton?.isHidden = true
        closeButton?.isHidden = true
        zoomLabel?.isHidden = true
    }

    override func layout() {
        super.layout()
        // Close button top-right, edit button to its left, zoom label to its left
        let btnSize: CGFloat = 24
        let btnY = bounds.maxY - 30
        closeButton?.frame = NSRect(x: bounds.maxX - 30, y: btnY, width: btnSize, height: btnSize)
        editButton?.frame  = NSRect(x: bounds.maxX - 58, y: btnY, width: btnSize, height: btnSize)
        if let label = zoomLabel {
            let labelW = max(label.intrinsicContentSize.width + 14, 42)
            label.frame = NSRect(
                x: bounds.maxX - 58 - labelW - 6,
                y: btnY,
                width: labelW,
                height: btnSize
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsDecorations {
            // Apply clipping path with rounded corners
            let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
            path.addClip()

            // Draw the image
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

            // Draw border
            NSColor.white.withAlphaComponent(0.3).setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            border.lineWidth = 1
            border.stroke()
        } else {
            // No decorations - just draw the image directly
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
        }
    }

    // Right-click context menu
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = menu.addItem(withTitle: NSLocalizedString("Copy to Clipboard", comment: ""), action: #selector(copyImage), keyEquivalent: "c")
        copyItem.target = self

        let saveItem = menu.addItem(withTitle: NSLocalizedString("Save As...", comment: ""), action: #selector(saveImage), keyEquivalent: "s")
        saveItem.target = self

        menu.addItem(NSMenuItem.separator())

        // Decorations toggle (corner + border + shadow together)
        let decorationsTitle = showsDecorations ? NSLocalizedString("Hide Decorations", comment: "") : NSLocalizedString("Show Decorations", comment: "")
        let decorationsItem = menu.addItem(withTitle: decorationsTitle, action: #selector(toggleDecorations), keyEquivalent: "")
        decorationsItem.target = self

        menu.addItem(NSMenuItem.separator())

        let closeItem = menu.addItem(withTitle: NSLocalizedString("Close", comment: ""), action: #selector(closeClicked), keyEquivalent: "")
        closeItem.target = self

        return menu
    }

    @objc private func copyImage() {
        ImageEncoder.copyToClipboard(imageAsset, source: .display)
    }

    @objc private func saveImage() {
        guard let imageData = ImageEncoder.encode(imageAsset, source: .display) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [ImageEncoder.utType]
        savePanel.nameFieldStringValue = "macshot_\(OverlayWindowController.formattedTimestamp()).\(ImageEncoder.fileExtension)"

        savePanel.directoryURL = SaveDirectoryAccess.directoryHint()

        FilePanelPresenter.begin(savePanel, ownerWindow: window) { response in
            if response == .OK, let url = savePanel.url {
                try? imageData.write(to: url)
                SaveDirectoryAccess.save(url: url.deletingLastPathComponent())
            }
        }
    }

    @objc private func toggleDecorations() {
        showsDecorations.toggle()
        needsDisplay = true

        // Update window shadow
        guard let window = window as? NSPanel else { return }
        window.hasShadow = showsDecorations
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if let label = zoomLabel, !label.isHidden, label.frame.contains(loc) {
            onResetZoom?()
            return
        }
        super.mouseDown(with: event)
    }

    // Scroll to zoom (mouse wheel and trackpad two-finger scroll)
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return }
        // Trackpad sends fine-grained deltas; mouse wheel sends larger discrete steps
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.005 : 0.03
        let factor: CGFloat = 1.0 + delta * sensitivity
        let loc = convert(event.locationInWindow, from: nil)
        onZoom?(factor, loc)
    }

    // Pinch to zoom
    override func magnify(with event: NSEvent) {
        let factor = 1.0 + event.magnification
        let loc = convert(event.locationInWindow, from: nil)
        onZoom?(factor, loc)
    }

    // Keyboard: Escape to close
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Vertically centered NSTextField

private class VerticallyCenteredCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let textSize = cellSize(forBounds: rect)
        let y = max(0, (rect.height - textSize.height) / 2)
        return NSRect(x: rect.origin.x, y: rect.origin.y + y, width: rect.width, height: textSize.height)
    }
}

private class VerticallyCenteredTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { VerticallyCenteredCell.self }
        set {}
    }
}
