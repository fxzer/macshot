import Cocoa

/// Real NSView-based tool options row, replacing the custom-drawn drawToolOptionsRow().
/// Dynamically rebuilds its content when the selected tool changes.
class ToolOptionsRowView: NSView {

    weak var overlayView: OverlayView?
    private(set) var currentTool: AnnotationTool?
    private weak var strokeSliderView: NSSlider?
    /// When set, the options row edits this annotation's properties instead of global tool state.
    private(set) var editingAnnotation: Annotation?
    /// Snapshot taken before the first property edit, for undo.
    private var editingSnapshot: Annotation?
    let rowHeight: CGFloat = 34
    private let stackView = NSStackView()
    private let padding: CGFloat = 8

    static let cachedFontFamilies: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
    }()

    static var cachedCustomBgImage: NSImage?
    static var lastCustomBgData: Data?

    enum ToolOptionTag: Int {
        case drawColorSwatch = 974
        case textBgColorSwatch = 975
        case textOutlineColorSwatch = 976
        case annotationOutlineColorSwatch = 978
        case lineStyleSegment = 979
        case textCancelButton = 990
        case textConfirmButton = 991
        
        case strokeValueLabel = 997
        case numberStartValueLabel = 999
        
        // Reassigned to avoid conflicts
        case textFontSizeLabel = 1001
        case beautifyRadiusLabel = 1002
        case beautifyPaddingSlider = 1003
        case beautifyPaddingLabel = 1004
        case beautifyShadowSlider = 1005
        case beautifyShadowLabel = 1006
        case beautifyStyleSwatch = 1007
        case cornerRadiusLabel = 1008
        case fpsSlider = 1009
        case fpsValueLabel = 1010
    }

    /// The natural content width calculated during rebuild, before any external resizing.
    private(set) var contentWidth: CGFloat = 200
    // Consume clicks on gaps between controls so they don't fall through to OverlayView.
    // In editor mode, let gap clicks pass through so drawing works over the options area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let result = super.hitTest(point), result !== self { return result }
        if overlayView?.isEditorMode == true { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    /// Auto-tint controls to match toolbar accent color.
    /// Buttons with tag 990+ are excluded (they have custom colors like red/green/white).
    override func addSubview(_ view: NSView) {
        super.addSubview(view)
        if let btn = view as? NSButton, btn.tag < 990 { btn.contentTintColor = ToolbarLayout.accentColor }
        if let slider = view as? NSSlider { slider.trackFillColor = ToolbarLayout.accentColor }
        if let seg = view as? NSSegmentedControl { seg.selectedSegmentBezelColor = ToolbarLayout.accentColor }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.heightAnchor.constraint(equalTo: heightAnchor)
        ])
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = ToolbarLayout.bgColor.cgColor
        // Match appearance to toolbar background brightness so system controls
        // (NSSegmentedControl labels, NSTextField, NSButton titles) stay readable.
        appearance = ToolbarLayout.appearance
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Lightweight update: sync stroke slider position and value label without rebuilding entire row.
    /// Call this from scroll-wheel adjustments for smooth, jank-free feedback.
    func updateStrokeSlider(value: CGFloat) {
        if strokeSliderView?.superview == nil {
            strokeSliderView = findStrokeSlider(in: stackView)
        }
        strokeSliderView?.doubleValue = Double(value)
        if let label = viewWithTag(ToolOptionTag.strokeValueLabel.rawValue) as? NSTextField {
            label.stringValue = currentTool == .loupe ? "\(Int(value))" : "\(Int(value))px"
        }
    }

    private func findStrokeSlider(in view: NSView) -> NSSlider? {
        if let slider = view as? NSSlider,
            slider.action == #selector(strokeSliderChanged(_:))
        {
            return slider
        }

        for subview in view.subviews {
            if let slider = findStrokeSlider(in: subview) {
                return slider
            }
        }

        return nil
    }

    /// Lightweight update: sync font size label in the text tool options row.
    func updateFontSizeDisplay(value: CGFloat) {
        if let label = viewWithTag(ToolOptionTag.textFontSizeLabel.rawValue) as? NSTextField {
            label.stringValue = "\(Int(value))"
        }
    }

    /// Rebuild the options row for a selected annotation's tool, reading values from the annotation.
    func rebuild(forAnnotation ann: Annotation) {
        editingAnnotation = ann
        editingSnapshot = nil  // snapshot taken on first edit
        rebuild(for: ann.tool)
    }

    /// Clear editing state so future rebuilds use global tool defaults.
    /// Update color swatches in-place without rebuilding the entire row.
    func updateSwatchColors() {
        guard let ov = overlayView else { return }
        // Draw color swatch (tag 974)
        if let swatch = viewWithTag(ToolOptionTag.drawColorSwatch.rawValue) {
            swatch.layer?.backgroundColor = (editingAnnotation?.color ?? ov.currentColor).cgColor
        }
        // Text background swatch (tag 975)
        if let swatch = viewWithTag(ToolOptionTag.textBgColorSwatch.rawValue) {
            swatch.layer?.backgroundColor = ov.textEditor.bgColor.cgColor
        }
        // Text outline swatch (tag 976)
        if let swatch = viewWithTag(ToolOptionTag.textOutlineColorSwatch.rawValue) {
            swatch.layer?.backgroundColor = ov.textEditor.outlineColor.cgColor
        }
        // Annotation outline swatch (tag 978)
        if let swatch = viewWithTag(ToolOptionTag.annotationOutlineColorSwatch.rawValue) {
            let col = editingAnnotation?.outlineColor ?? Self.savedOutlineColor
            swatch.layer?.backgroundColor = col.cgColor
        }
    }

    func clearEditingAnnotation() {
        commitEditingSnapshot()
        editingAnnotation = nil
        editingSnapshot = nil
    }

    /// Push the undo entry if we have a snapshot (i.e., at least one property was changed).
    private func commitEditingSnapshot() {
        guard let ann = editingAnnotation, let snapshot = editingSnapshot else { return }
        overlayView?.pushPropertyChangeUndo(annotation: ann, snapshot: snapshot)
        editingSnapshot = nil
    }

    /// Take a snapshot before the first edit so we can undo.
    func ensureSnapshot() {
        guard let ann = editingAnnotation, editingSnapshot == nil else { return }
        editingSnapshot = ann.clone()
    }

    /// Rebuild the options row for the given tool. Call when tool or state changes.
    func rebuild(for tool: AnnotationTool) {
        strokeSliderView = nil
        // Remove old subviews
        // Properly remove and de-anchor arranged subviews to prevent layout ambiguity or leaks
        while !stackView.arrangedSubviews.isEmpty {
            let v = stackView.arrangedSubviews[0]
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        guard let ov = overlayView else { return }

        currentTool = tool

        if supportsDrawColor(tool) {
            addDrawColorControl(to: stackView, tool: tool, ov: ov)
            addSeparator(to: stackView)
        }

        // ── Stroke width slider (most drawing tools) ──
        let hasStroke = [.pencil, .line, .arrow, .rectangle, .ellipse, .marker, .number, .loupe].contains(tool)
        if hasStroke {
            addStrokeSlider(to: stackView, tool: tool, ov: ov)
            strokeSliderView = findStrokeSlider(in: stackView)
        }

        // ── Line style (line, pencil, rectangle) ──
        let hasLineStyle = [.line, .pencil, .rectangle, .arrow, .ellipse].contains(tool)
        if hasLineStyle {
            if hasStroke { addSeparator(to: stackView) }
            addLineStyleSegment(to: stackView, tool: tool, ov: ov)
        }

        // ── Arrow style + outline + reverse toggle ──
        if tool == .arrow {
            addSeparator(to: stackView)
            addArrowStyleSegment(to: stackView, ov: ov)
            addSeparator(to: stackView)
            addOutlineControls(to: stackView, tool: tool, ov: ov)
            addSeparator(to: stackView)
            let flipIsOn = editingAnnotation?.arrowReversed ?? ov.arrowReversed(for: .arrow)
            addToggle(to: stackView, title: L("Flip"), isOn: flipIsOn) { [weak self, weak ov] isOn in
                if let ann = self?.editingAnnotation {
                    self?.ensureSnapshot()
                    ann.arrowReversed = isOn
                    ov?.invalidateCommittedAnnotationRendering()
                }
                ov?.setArrowReversed(isOn, for: .arrow)
                ov?.needsDisplay = true
            }
        }

        // ── Shape fill style (rectangle, ellipse) ──
        if tool == .rectangle || tool == .ellipse {
            addSeparator(to: stackView)
            addShapeFillSegment(to: stackView, tool: tool, ov: ov)
        }

        // ── Corner radius slider (rectangle) ──
        if tool == .rectangle {
            addSeparator(to: stackView)
            addCornerRadiusSlider(to: stackView, ov: ov)
        }



        // ── Pencil smooth mode selector ──
        if tool == .pencil {
            addSeparator(to: stackView)
            let seg = NSSegmentedControl(labels: [L("None"), L("Smooth"), L("Refined")],
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(pencilSmoothModeChanged(_:)))
            seg.selectedSegment = ov.pencilSmoothMode
            seg.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
            seg.sizeToFit()
            // seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: seg.frame.width, height: 22)
            stackView.addArrangedSubview(seg)

            // ── Pressure sensitivity toggle ──
            addSeparator(to: stackView)
            addToggle(to: stackView, title: L("Pressure"), isOn: ov.pencilPressureEnabled) { [weak ov] isOn in
                ov?.pencilPressureEnabled = isOn
                UserDefaults.standard.set(isOn, forKey: "pencilPressureEnabled")
            }
        }

        // ── Smart marker toggle ──
        if tool == .marker {
            addSeparator(to: stackView)
            addToggle(to: stackView, title: L("Smart"), isOn: ov.smartMarkerEnabled) { [weak ov, weak self] isOn in
                ov?.smartMarkerEnabled = isOn
                UserDefaults.standard.set(isOn, forKey: "smartMarkerEnabled")
                ov?.updateCursorForCurrentTool()
                ov?.needsDisplay = true
                // Rebuild to update stroke slider enabled state
                self?.rebuild(for: .marker)
            }
            // Disable stroke slider when smart marker is on (auto-sized)
            if ov.smartMarkerEnabled {
                for sub in stackView.arrangedSubviews {
                    if let slider = sub as? NSSlider, slider.tag == AnnotationTool.marker.rawValue {
                        slider.isEnabled = false
                        slider.alphaValue = 0.35
                    }
                }
                if let label = viewWithTag(ToolOptionTag.strokeValueLabel.rawValue) as? NSTextField {
                    label.alphaValue = 0.35
                }
                // Also dim the "Stroke" label
                for sub in stackView.arrangedSubviews {
                    if let tf = sub as? NSTextField, tf.stringValue == L("Stroke"), tf.tag == 0 {
                        tf.alphaValue = 0.35
                    }
                }
            }
        }

        // ── Number format + start-at ──
        if tool == .number {
            addSeparator(to: stackView)
            addNumberOptions(to: stackView, ov: ov)
        }

        // ── Text formatting ──
        if tool == .text {
            addTextOptions(to: stackView, ov: ov)
        }

        // ── Measure px/pt toggle ──
        if tool == .measure {
            addMeasureToggle(to: stackView, ov: ov)
        }

        // ── Stamp/emoji row ──
        if tool == .stamp {
            addStampOptions(to: stackView, ov: ov)
        }

        // ── Censor tool: mode selector + redact buttons ──
        if tool == .pixelate {
            addCensorModeSegment(to: stackView, ov: ov)
            addSeparator(to: stackView)
            addRedactOptions(to: stackView, ov: ov)
        }

        // ── Outline toggle + color swatch (line, rectangle, ellipse, number — arrow handled above) ──
        let hasOutlineGeneric: [AnnotationTool] = [.line, .rectangle, .ellipse, .number]
        if hasOutlineGeneric.contains(tool) {
            addSeparator(to: stackView)
            addOutlineControls(to: stackView, tool: tool, ov: ov)
        }

        // Since NSStackView manages layout, we update layout and calculate width
        stackView.needsLayout = true
        stackView.layoutSubtreeIfNeeded()
        let totalW = max(stackView.fittingSize.width + padding * 2, 200)
        contentWidth = totalW
        frame.size = NSSize(width: totalW, height: rowHeight)
        
        // Add a flexible spacer before text buttons if needed to right-align them
        // Actually, for simplicity we just let them sit next to the other options.

    }

    // MARK: - Partial Updates

    /// Update the visual state (background color/toggle state) of formatting buttons
    /// (Bold, Italic, Alignment, etc.) without rebuilding the entire row.
    func updateFormattingButtons() {
        guard let ov = overlayView else { return }
        
        // Find buttons within the stackView hierarchy (recursively)
        func updateInView(_ view: NSView) {
            for sub in view.subviews {
                if let btn = sub as? NSButton {
                    let tag = btn.tag
                    // Bold, Italic, Underline, Strikethrough (tags 980-983)
                    if tag >= 980 && tag <= 983 {
                        let isOn: Bool
                        switch tag {
                        case 980: isOn = ov.textEditor.bold
                        case 981: isOn = ov.textEditor.italic
                        case 982: isOn = ov.textEditor.underline
                        case 983: isOn = ov.textEditor.strikethrough
                        default: isOn = false
                        }
                        btn.layer?.backgroundColor = isOn ? ToolbarLayout.accentColor.withAlphaComponent(0.85).cgColor : nil
                        if let attrTitle = btn.attributedTitle.mutableCopy() as? NSMutableAttributedString {
                            attrTitle.addAttribute(.foregroundColor, value: ToolbarLayout.iconColor.withAlphaComponent(isOn ? 1.0 : 0.6), range: NSRange(location: 0, length: attrTitle.length))
                            btn.attributedTitle = attrTitle
                        }
                    }
                    // Alignment buttons (tags matching NSTextAlignment raw values)
                    else if tag == NSTextAlignment.left.rawValue || tag == NSTextAlignment.center.rawValue || tag == NSTextAlignment.right.rawValue {
                        btn.state = (tag == ov.textEditor.alignment.rawValue) ? .on : .off
                    }
                }
                updateInView(sub)
            }
        }
        
        updateInView(stackView)
    }

    // MARK: - Section builders
}
