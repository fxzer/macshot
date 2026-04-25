import Cocoa

private func tintedBeautifyPickerImage(_ image: NSImage, color: NSColor) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.lockFocus()
    color.set()
    NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
    copy.unlockFocus()
    return copy
}

final class BeautifyBackgroundPickerView: NSView {
    private let selectedRingInset: CGFloat = 2
    private let columns: Int
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let swatchSize: CGFloat = 28
    private let gap: CGFloat = 4
    private let hasCustomImage: Bool
    private let gradients: [NSGradient?] = beautifyStyles.map {
        NSGradient(colors: $0.stops.map(\.0), atLocations: $0.stops.map(\.1), colorSpace: .deviceRGB)
    }
    private var meshImages = Array<NSImage?>(repeating: nil, count: beautifyStyles.count)
    private var cachedThumbnail: NSImage?
    private let plusIcon: NSImage?

    var selectedIndex: Int
    var onSelect: ((Int) -> Void)?
    var onCustomImage: (() -> Void)?
    var onRemoveCustomImage: (() -> Void)?

    init(selectedIndex: Int, columns: Int, horizontalPadding: CGFloat, verticalPadding: CGFloat = 8) {
        self.selectedIndex = selectedIndex
        self.columns = columns
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.hasCustomImage = BeautifyBackgroundStore.hasCustomBackground()
        if let icon = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            self.plusIcon = tintedBeautifyPickerImage(icon, color: ToolbarLayout.iconColor)
        } else {
            self.plusIcon = nil
        }

        let total = beautifyStyles.count + (hasCustomImage ? 1 : 0) + 1
        let rows = Int(ceil(Double(total) / Double(columns)))
        let width = horizontalPadding * 2 + CGFloat(columns) * swatchSize + CGFloat(columns - 1) * gap
        let height = verticalPadding * 2 + CGFloat(rows) * swatchSize + CGFloat(max(0, rows - 1)) * gap
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        clearCachedImages()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var preferredSize: NSSize { frame.size }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            clearCachedImages()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for index in 0..<beautifyStyles.count {
            drawStyle(at: index)
        }
        if let thumbnail = customBackgroundThumbnail() {
            drawImageSwatch(thumbnail, at: beautifyStyles.count, selected: selectedIndex == -1)
        }
        drawAddImageSwatch(at: beautifyStyles.count + (hasCustomImage ? 1 : 0))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let total = beautifyStyles.count + (hasCustomImage ? 1 : 0) + 1
        for slot in 0..<total where rect(for: slot).contains(point) {
            switch slot {
            case beautifyStyles.count where hasCustomImage:
                selectedIndex = -1
                onSelect?(-1)
            case total - 1:
                onCustomImage?()
            default:
                guard slot < beautifyStyles.count else { return }
                selectedIndex = slot
                onSelect?(slot)
            }
            needsDisplay = true
            return
        }
    }

    override func keyDown(with event: NSEvent) {
        let isDelete = event.keyCode == 51 || event.keyCode == 117
        if isDelete, selectedIndex == -1, hasCustomImage {
            onRemoveCustomImage?()
            return
        }
        if moveSelection(for: event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }

    private func rect(for index: Int) -> NSRect {
        let col = index % columns
        let row = index / columns
        return NSRect(
            x: horizontalPadding + CGFloat(col) * (swatchSize + gap),
            y: verticalPadding + CGFloat(row) * (swatchSize + gap),
            width: swatchSize,
            height: swatchSize
        )
    }

    private func drawStyle(at index: Int) {
        let style = beautifyStyles[index]
        let rect = rect(for: index)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if #available(macOS 15.0, *), let mesh = style.meshDef {
            if meshImages[index] == nil {
                meshImages[index] = BeautifyRenderer.renderMeshSwatch(mesh, size: swatchSize)
            }
            drawImage(meshImages[index], in: rect, clippedBy: path)
        } else {
            gradients[index]?.draw(in: path, angle: style.angle - 90)
        }
        if index == selectedIndex {
            drawSelectionRing(around: rect)
        }
    }

    private func drawImageSwatch(_ image: NSImage?, at index: Int, selected: Bool) {
        let rect = rect(for: index)
        drawImage(image, in: rect, clippedBy: NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6))
        if selected {
            drawSelectionRing(around: rect)
        }
    }

    private func drawAddImageSwatch(at index: Int) {
        let rect = rect(for: index)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        ToolbarLayout.iconColor.withAlphaComponent(0.15).setFill()
        path.fill()
        guard let plusIcon else { return }
        let iconRect = NSRect(
            x: rect.midX - plusIcon.size.width / 2,
            y: rect.midY - plusIcon.size.height / 2,
            width: plusIcon.size.width,
            height: plusIcon.size.height
        )
        plusIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.7)
    }

    private func drawImage(_ image: NSImage?, in rect: NSRect, clippedBy path: NSBezierPath) {
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectionRing(around rect: NSRect) {
        ToolbarLayout.accentColor.setStroke()
        let ring = NSBezierPath(
            roundedRect: rect.insetBy(dx: -selectedRingInset, dy: -selectedRingInset),
            xRadius: 7,
            yRadius: 7
        )
        ring.lineWidth = 2
        ring.stroke()
    }

    @discardableResult
    private func moveSelection(for keyCode: UInt16) -> Bool {
        let selectable = beautifyStyles.count + (hasCustomImage ? 1 : 0)
        guard selectable > 0 else { return false }

        let currentSlot = selectedIndex == -1 ? beautifyStyles.count : max(0, min(selectedIndex, beautifyStyles.count - 1))
        let targetSlot: Int?
        switch keyCode {
        case 123:
            targetSlot = currentSlot > 0 ? currentSlot - 1 : nil
        case 124:
            targetSlot = currentSlot < selectable - 1 ? currentSlot + 1 : nil
        case 125:
            targetSlot = verticalMove(from: currentSlot, offset: 1, count: selectable)
        case 126:
            targetSlot = verticalMove(from: currentSlot, offset: -1, count: selectable)
        default:
            targetSlot = nil
        }

        guard let targetSlot else { return false }
        selectedIndex = hasCustomImage && targetSlot == beautifyStyles.count ? -1 : targetSlot
        onSelect?(selectedIndex)
        needsDisplay = true
        return true
    }

    private func verticalMove(from currentSlot: Int, offset: Int, count: Int) -> Int? {
        let targetRow = currentSlot / columns + offset
        let totalRows = Int(ceil(Double(count) / Double(columns)))
        guard targetRow >= 0, targetRow < totalRows else { return nil }
        let rowStart = targetRow * columns
        let rowCount = min(columns, count - rowStart)
        return rowStart + min(currentSlot % columns, rowCount - 1)
    }

    private func customBackgroundThumbnail() -> NSImage? {
        if let cachedThumbnail { return cachedThumbnail }
        guard
            let image = BeautifyBackgroundStore.loadImage()
        else { return nil }

        let thumbnail = NSImage(size: NSSize(width: swatchSize, height: swatchSize))
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: thumbnail.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()
        cachedThumbnail = thumbnail
        return thumbnail
    }

    private func clearCachedImages() {
        meshImages = Array(repeating: nil, count: meshImages.count)
        cachedThumbnail = nil
    }
}
