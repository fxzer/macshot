import Cocoa

final class BeautifyPopoverView: NSView {
    private let contentWidth: CGFloat = 280
    private var currentY: CGFloat = 12

    weak var overlayView: OverlayView?

    override var isFlipped: Bool { true }
    var preferredSize: NSSize { frame.size }

    init(overlayView: OverlayView) {
        self.overlayView = overlayView
        super.init(frame: .zero)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        currentY = 12

        guard let overlayView else {
            frame.size = NSSize(width: contentWidth, height: 120)
            return
        }

        addTitleRow(L("Beautify"), isOn: overlayView.beautifyEnabled) { [weak self] isOn in
            guard let overlayView = self?.overlayView else { return }
            overlayView.beautifyEnabled = isOn
            UserDefaults.standard.set(isOn, forKey: "beautifyEnabled")
            overlayView.refreshBeautifyRendering()
        }

        if !overlayView.selectionIsWindowSnap {
            let segmented = makeOverlaySegmented(
                [L("Window"), L("Rounded")],
                selected: overlayView.beautifyMode == .window ? 0 : 1
            ) { [weak self] index in
                guard let overlayView = self?.overlayView else { return }
                overlayView.beautifyMode = index == 0 ? .window : .rounded
                UserDefaults.standard.set(overlayView.beautifyMode.rawValue, forKey: "beautifyMode")
                overlayView.refreshBeautifyRendering()
            }
            segmented.frame = NSRect(x: 14, y: currentY, width: contentWidth - 28, height: 24)
            addSubview(segmented)
            currentY += 34
        }

        addSlider(L("Padding"), value: overlayView.beautifyPadding, range: 16...96) { [weak self] value in
            self?.overlayView?.beautifyPadding = value
            UserDefaults.standard.set(Double(value), forKey: "beautifyPadding")
            self?.overlayView?.refreshBeautifyRendering()
        }

        if !overlayView.selectionIsWindowSnap {
            addSlider(L("Radius"), value: overlayView.beautifyCornerRadius, range: 0...100) { [weak self] value in
                self?.overlayView?.beautifyCornerRadius = value
                UserDefaults.standard.set(Double(value), forKey: "beautifyCornerRadius")
                self?.overlayView?.refreshBeautifyRendering()
            }
        }

        addSlider(L("Shadow"), value: overlayView.beautifyShadowRadius, range: 0...100) { [weak self] value in
            self?.overlayView?.beautifyShadowRadius = value
            UserDefaults.standard.set(Double(value), forKey: "beautifyShadowRadius")
            self?.overlayView?.refreshBeautifyRendering()
        }

        if overlayView.beautifyStyleIndex == -1 {
            addSlider(L("Blur"), value: overlayView.beautifyBackgroundBlur, range: 0...50) { [weak self] value in
                self?.overlayView?.beautifyBackgroundBlur = value
                UserDefaults.standard.set(Double(value), forKey: "beautifyBgBlur")
                self?.overlayView?.refreshBeautifyRendering()
            }
        }

        let picker = BeautifyBackgroundPickerView(selectedIndex: overlayView.beautifyStyleIndex, columns: 8, horizontalPadding: 0)
        picker.onSelect = { [weak self] index in
            self?.overlayView?.applyBeautifyStyleSelection(index)
            self?.rebuild()
        }
        picker.onCustomImage = { [weak self] in
            self?.overlayView?.pickCustomBeautifyBackground { [weak self] in
                self?.rebuild()
            }
        }
        picker.onRemoveCustomImage = { [weak self] in
            self?.overlayView?.removeCustomBeautifyBackgroundSelection()
            self?.rebuild()
        }
        picker.frame.origin = NSPoint(x: 14, y: currentY)
        addSubview(picker)
        currentY += picker.frame.height + 12

        frame.size = NSSize(width: contentWidth, height: currentY)
    }

    private func addTitleRow(_ title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = ToolbarLayout.iconColor
        label.frame = NSRect(x: 14, y: currentY + 2, width: 200, height: 18)
        addSubview(label)

        let toggle = makeOverlayCheckbox("", isOn: isOn, onChange: onToggle)
        toggle.frame = NSRect(x: contentWidth - 28, y: currentY + 2, width: 24, height: 18)
        addSubview(toggle)
        currentY += 28
    }

    private func addSlider(_ title: String, value: CGFloat, range: ClosedRange<CGFloat>, onChange: @escaping (CGFloat) -> Void) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = OverlayPopoverPalette.labelFont
        titleLabel.textColor = OverlayPopoverPalette.label
        titleLabel.frame = NSRect(x: 14, y: currentY + 2, width: 60, height: 16)
        addSubview(titleLabel)

        let slider = NSSlider(
            value: Double(value),
            minValue: Double(range.lowerBound),
            maxValue: Double(range.upperBound),
            target: nil,
            action: nil
        )
        slider.frame = NSRect(x: 78, y: currentY, width: 140, height: 20)
        slider.isContinuous = true
        addSubview(slider)

        let valueLabel = NSTextField(labelWithString: "\(Int(value))")
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.textColor = OverlayPopoverPalette.value
        valueLabel.frame = NSRect(x: 224, y: currentY + 2, width: 40, height: 16)
        addSubview(valueLabel)

        slider.bindOverlayAction {
            let value = CGFloat(($0 as? NSSlider)?.floatValue ?? Float(range.lowerBound))
            valueLabel.stringValue = "\(Int(value))"
            onChange(value)
        }
        currentY += 28
    }
}
