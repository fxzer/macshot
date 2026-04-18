import AppKit
import Foundation
import UniformTypeIdentifiers

class BeautifyPickerView: NSView {
    weak var overlayView: OverlayView?
    private let contentWidth: CGFloat = 280
    private var currentY: CGFloat = 0

    override var isFlipped: Bool { true }
    var preferredSize: NSSize { frame.size }

    init(overlayView: OverlayView) {
        self.overlayView = overlayView
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let ov = overlayView else {
            frame.size = NSSize(width: contentWidth, height: 120)
            return
        }

        subviews.forEach { $0.removeFromSuperview() }
        currentY = 12

        addSectionTitle(L("Wrap"), isOn: ov.beautifyEnabled, action: #selector(toggleChanged(_:)))

        if !ov.selectionIsWindowSnap {
            addSegmentedControl(
                labels: [L("Window"), L("Rounded")],
                selectedIndex: ov.beautifyMode == .window ? 0 : 1,
                action: #selector(modeChanged(_:)))
        }

        addSliderRow(
            title: L("Padding"),
            value: ov.beautifyPadding,
            min: 16,
            max: 96,
            tag: 900,
            action: #selector(sliderChanged(_:)))

        if !ov.selectionIsWindowSnap {
            addSliderRow(
                title: L("Radius"),
                value: ov.beautifyCornerRadius,
                min: 0,
                max: 100,
                tag: 901,
                action: #selector(sliderChanged(_:)))
        }

        addSliderRow(
            title: L("Shadow"),
            value: ov.beautifyShadowRadius,
            min: 0,
            max: 100,
            tag: 902,
            action: #selector(sliderChanged(_:)))

        if ov.beautifyStyleIndex == -1 {
            addSliderRow(
                title: L("Blur"),
                value: ov.beautifyBackgroundBlur,
                min: 0,
                max: 50,
                tag: 903,
                action: #selector(sliderChanged(_:)))
        }

        addGradientPicker()

        frame.size = NSSize(width: contentWidth, height: currentY + 12)
    }

    private func addSectionTitle(_ text: String, isOn: Bool = false, action: Selector? = nil) {
        // 左侧标题
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = ToolbarLayout.iconColor
        label.frame = NSRect(x: 14, y: currentY + 2, width: 200, height: 18)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        addSubview(label)

        // 右侧复选框
        if let action = action {
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: action)
            toggle.state = isOn ? .on : .off
            toggle.frame = NSRect(x: contentWidth - 28, y: currentY + 2, width: 24, height: 18)
            addSubview(toggle)
        }

        currentY += 28
    }

    private func addSegmentedControl(labels: [String], selectedIndex: Int, action: Selector) {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: action)
        control.selectedSegment = selectedIndex
        control.frame = NSRect(x: 14, y: currentY, width: contentWidth - 28, height: 24)
        addSubview(control)
        currentY += 34
    }

    private func addSliderRow(title: String, value: CGFloat, min: CGFloat, max: CGFloat, tag: Int, action: Selector) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.78)
        titleLabel.frame = NSRect(x: 14, y: currentY + 2, width: 60, height: 16)
        addSubview(titleLabel)

        let slider = NSSlider(value: Double(value), minValue: Double(min), maxValue: Double(max), target: self, action: action)
        slider.tag = tag
        slider.frame = NSRect(x: 78, y: currentY, width: 140, height: 20)
        slider.isContinuous = true
        addSubview(slider)

        let valueLabel = NSTextField(labelWithString: "\(Int(value))")
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.62)
        valueLabel.tag = tag + 100
        valueLabel.frame = NSRect(x: 224, y: currentY + 2, width: 40, height: 16)
        addSubview(valueLabel)

        currentY += 28
    }

    private func addGradientPicker() {
        guard let ov = overlayView else { return }

        // 创建8列的渐变选择器
        let picker = InlineGradientPickerView(selectedIndex: ov.beautifyStyleIndex)
        picker.onSelect = { [unowned self] idx in
            guard let ov = self.overlayView else { return }
            ov.beautifyStyleIndex = idx
            UserDefaults.standard.set(idx, forKey: "beautifyStyleIndex")
            if idx >= 0 {
                ov.customBeautifyBackground = nil
            } else {
                ov.loadCustomBeautifyBackground()
            }
            ov.cachedCompositedImage = nil
            ov.needsDisplay = true
            // 重建UI以显示/隐藏模糊滑块
            self.buildUI()
        }
        picker.onCustomImage = { [unowned self] in
            self.pickCustomImage()
        }
        picker.frame.origin = NSPoint(x: 14, y: currentY)
        addSubview(picker)
        currentY += picker.frame.height + 12
    }

    private func pickCustomImage() {
        guard let ov = overlayView else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        let savedLevel = ov.window?.level
        ov.window?.level = .normal
        panel.beginSheetModal(for: ov.window!) { [weak self] response in
            ov.window?.level = savedLevel ?? .normal
            guard let self = self, response == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url) else { return }
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                UserDefaults.standard.set(png, forKey: "beautifyCustomBgImageData")
            }
            ov.beautifyStyleIndex = -1
            UserDefaults.standard.set(-1, forKey: "beautifyStyleIndex")
            ov.customBeautifyBackground = image
            ov.cachedCompositedImage = nil
            ov.needsDisplay = true
            self.buildUI()
        }
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.beautifyEnabled = sender.state == .on
        UserDefaults.standard.set(ov.beautifyEnabled, forKey: "beautifyEnabled")
        ov.cachedCompositedImage = nil
        ov.updateEditorFrameForBeautify()
        ov.rebuildToolbarLayout()
        ov.needsDisplay = true
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        ov.beautifyMode = sender.selectedSegment == 0 ? .window : .rounded
        UserDefaults.standard.set(ov.beautifyMode.rawValue, forKey: "beautifyMode")
        ov.cachedCompositedImage = nil
        ov.updateEditorFrameForBeautify()
        ov.rebuildToolbarLayout()
        ov.needsDisplay = true
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        let value = CGFloat(sender.floatValue)
        var affectsEditorFrame = false
        switch sender.tag {
        case 900:
            ov.beautifyPadding = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyPadding")
            affectsEditorFrame = true
        case 901:
            ov.beautifyCornerRadius = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyCornerRadius")
        case 902:
            ov.beautifyShadowRadius = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyShadowRadius")
            affectsEditorFrame = true
        case 903:
            ov.beautifyBackgroundBlur = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyBgBlur")
        default:
            break
        }
        if let label = viewWithTag(sender.tag + 100) as? NSTextField {
            label.stringValue = "\(Int(sender.floatValue))"
        }
        if affectsEditorFrame { ov.updateEditorFrameForBeautify() }
        ov.cachedCompositedImage = nil
        ov.needsDisplay = true
    }
}

/// 8列的内嵌渐变选择器，用于BeautifyPickerView内部
private class InlineGradientPickerView: NSView {
    var selectedIndex: Int = 0
    var onSelect: ((Int) -> Void)?
    var onCustomImage: (() -> Void)?

    private let styles = BeautifyRenderer.styles
    private let cols = 8  // 改为8列
    private let swSize: CGFloat = 28
    /// 仅上下内边距；水平方向与 `BeautifyPickerView` 的 x:14 + 宽 252 对齐，避免与分段控件/滑块行错位或超出 280 宽弹窗
    private let paddingV: CGFloat = 8
    private let gap: CGFloat = 4

    private var hasCustomImage: Bool {
        UserDefaults.standard.data(forKey: "beautifyCustomBgImageData") != nil
    }

    init(selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        let hasCustom = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData") != nil
        let total = BeautifyRenderer.styles.count + (hasCustom ? 1 : 0) + 1
        let rows = (total + 7) / 8  // 8列
        let w = CGFloat(cols) * swSize + CGFloat(cols - 1) * gap
        let h = paddingV * 2 + CGFloat(rows) * swSize + CGFloat(max(0, rows - 1)) * gap
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func rectForIndex(_ i: Int) -> NSRect {
        let col = i % cols
        let row = i / cols
        let sx = CGFloat(col) * (swSize + gap)
        let sy = paddingV + CGFloat(row) * (swSize + gap)
        return NSRect(x: sx, y: sy, width: swSize, height: swSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        var idx = 0

        // Draw gradient swatches
        for (i, style) in styles.enumerated() {
            let sr = rectForIndex(idx)
            let path = NSBezierPath(roundedRect: sr, xRadius: 6, yRadius: 6)
            if #available(macOS 15.0, *), let mesh = style.meshDef,
               let img = BeautifyRenderer.renderMeshSwatch(mesh, size: swSize) {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                img.draw(in: sr, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
            } else if let grad = NSGradient(colors: style.stops.map { $0.0 }, atLocations: style.stops.map { $0.1 }, colorSpace: .deviceRGB) {
                grad.draw(in: path, angle: style.angle - 90)
            }
            if i == selectedIndex {
                ToolbarLayout.accentColor.setStroke()
                let ring = NSBezierPath(roundedRect: sr.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
            idx += 1
        }

        // Custom image thumbnail swatch
        if let thumb = customBackgroundThumbnail() {
            let sr = rectForIndex(idx)
            let path = NSBezierPath(roundedRect: sr, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            thumb.draw(in: sr, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            if selectedIndex == -1 {
                ToolbarLayout.accentColor.setStroke()
                let ring = NSBezierPath(roundedRect: sr.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
            idx += 1
        }

        // "Choose Image" button swatch
        let btnRect = rectForIndex(idx)
        let btnPath = NSBezierPath(roundedRect: btnRect, xRadius: 6, yRadius: 6)
        ToolbarLayout.iconColor.withAlphaComponent(0.15).setFill()
        btnPath.fill()

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let plusIcon = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            let tinted = plusIcon.copy() as! NSImage
            tinted.lockFocus()
            ToolbarLayout.iconColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let iconSize = tinted.size
            let iconRect = NSRect(
                x: btnRect.midX - iconSize.width / 2,
                y: btnRect.midY - iconSize.height / 2,
                width: iconSize.width, height: iconSize.height)
            tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.7)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hasCustom = hasCustomImage
        let total = BeautifyRenderer.styles.count + (hasCustom ? 1 : 0) + 1

        for i in 0..<total {
            if rectForIndex(i).contains(point) {
                let styleCount = BeautifyRenderer.styles.count
                if i == styleCount && hasCustom {
                    // Clicked custom image swatch
                    selectedIndex = -1
                    onSelect?(-1)
                } else if i == total - 1 {
                    // Clicked "Choose Image" button
                    onCustomImage?()
                } else if i < styleCount {
                    // Clicked gradient swatch
                    selectedIndex = i
                    onSelect?(i)
                }
                needsDisplay = true
                return
            }
        }
    }

    private func customBackgroundThumbnail() -> NSImage? {
        guard let data = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData"),
              let image = NSImage(data: data) else { return nil }
        let size = NSSize(width: swSize, height: swSize)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}
