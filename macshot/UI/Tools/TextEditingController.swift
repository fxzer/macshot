import Cocoa

/// Protocol for the minimal canvas state that TextEditingController needs for commit/show.
@MainActor
protocol TextEditingCanvas: AnyObject {
    func viewToCanvas(_ p: NSPoint) -> NSPoint
    func canvasToView(_ p: NSPoint) -> NSPoint
    func opacityAppliedColor(for tool: AnnotationTool) -> NSColor
    var currentStrokeWidth: CGFloat { get }
    var annotations: [Annotation] { get set }
    var undoStack: [UndoEntry] { get set }
    var redoStack: [UndoEntry] { get set }
    var currentColor: NSColor { get }
    var textEditingBounds: NSRect { get }
}

/// Strips all layer-based borders that macOS applies on focus transitions.
private func stripLayerBorders(_ view: NSView) {
    view.layer?.borderWidth = 0
    view.layer?.borderColor = nil
    for child in view.subviews {
        stripLayerBorders(child)
    }
}

/// 会导致重新编辑时出现强调色/描边观感的临时文本属性。
private let transientEditingAttributeKeys: [NSAttributedString.Key] = [
    .backgroundColor,
    .strokeColor,
    .strokeWidth,
    .underlineColor,
    NSAttributedString.Key("NSMarkedClauseSegment"),
    NSAttributedString.Key("NSTextAlternatives"),
    NSAttributedString.Key("NSOriginalFont"),
]

private func sanitizedTextForEditing(
    _ source: NSAttributedString,
    defaultFont: NSFont,
    defaultColor: NSColor,
    alignment: NSTextAlignment
) -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: source)
    let fullRange = NSRange(location: 0, length: mutable.length)
    guard fullRange.length > 0 else { return mutable }

    mutable.beginEditing()
    for key in transientEditingAttributeKeys {
        mutable.removeAttribute(key, range: fullRange)
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment

    mutable.enumerateAttributes(in: fullRange) { attrs, range, _ in
        if attrs[.font] == nil {
            mutable.addAttribute(.font, value: defaultFont, range: range)
        }
        if attrs[.foregroundColor] == nil {
            mutable.addAttribute(.foregroundColor, value: defaultColor, range: range)
        }
    }
    mutable.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
    mutable.endEditing()
    return mutable
}

private final class NoFocusRingScrollView: NSScrollView {
    override func drawFocusRingMask() {}
    override var focusRingMaskBounds: NSRect { .zero }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
    override var allowsVibrancy: Bool { false }
    override func noteFocusRingMaskChanged() {}
    override func updateLayer() {
        super.updateLayer()
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stripLayerBorders(self)
    }
}

private final class NoFocusRingClipView: NSClipView {
    override func drawFocusRingMask() {}
    override var focusRingMaskBounds: NSRect { .zero }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
    override func noteFocusRingMaskChanged() {}
    override func updateLayer() {
        super.updateLayer()
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stripLayerBorders(self)
    }
}

private final class NoFocusRingTextView: NSTextView {
    override func drawFocusRingMask() {}
    override var focusRingMaskBounds: NSRect { .zero }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
    override func noteFocusRingMaskChanged() {}

    /// 锁住选中文本样式，防止系统在重新聚焦时恢复强调色描边效果。
    private var lockedSelectedTextAttributes: [NSAttributedString.Key: Any]?

    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { super.selectedTextAttributes }
        set {
            super.selectedTextAttributes = lockedSelectedTextAttributes ?? newValue
        }
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        // Re-strip every draw cycle to catch system-applied borders
        layer?.borderWidth = 0
        layer?.borderColor = nil
        if let sv = enclosingScrollView {
            sv.layer?.borderWidth = 0
            sv.layer?.borderColor = nil
            sv.contentView.layer?.borderWidth = 0
            sv.contentView.layer?.borderColor = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        applyEditingChrome()
        super.draw(dirtyRect)
        stripAllFocusBorders()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Recursively strip focus ring from entire scroll view hierarchy
        if let sv = enclosingScrollView {
            stripLayerBorders(sv)
            stripLayerBorders(sv.contentView)
        }
        stripLayerBorders(self)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            inputContext?.discardMarkedText()
            collapseSelection()
            sanitizeTextStorage()
            applyEditingChrome()
            stripAllFocusBorders()
            // Multiple deferred strips to catch system-applied borders at different timings
            DispatchQueue.main.async { [weak self] in
                self?.stripAllFocusBorders()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.stripAllFocusBorders()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.stripAllFocusBorders()
            }
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            inputContext?.discardMarkedText()
            collapseSelection()
            sanitizeTextStorage()
            applyEditingChrome()
            stripAllFocusBorders()
        }
        return result
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        sanitizeTextStorage()
        applyEditingChrome()
        stripAllFocusBorders()
    }

    private func stripAllFocusBorders() {
        if let sv = enclosingScrollView {
            stripLayerBorders(sv)
            stripLayerBorders(sv.contentView)
        }
        stripLayerBorders(self)
    }

    private func collapseSelection() {
        let range = selectedRange()
        let insertionLocation = range.location + range.length
        super.setSelectedRange(NSRange(location: insertionLocation, length: 0))
    }

    private func sanitizeTextStorage() {
        guard let textStorage, textStorage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        for key in transientEditingAttributeKeys {
            textStorage.removeAttribute(key, range: fullRange)
        }
        textStorage.endEditing()
    }

    func applyEditingChrome(explicitColor: NSColor? = nil) {
        let color =
            explicitColor
            ?? (typingAttributes[.foregroundColor] as? NSColor)
            ?? textColor
            ?? .white

        focusRingType = .none
        insertionPointColor = color
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .backgroundColor: NSColor.clear,
            .foregroundColor: color,
            .strokeColor: NSColor.clear,
            .strokeWidth: 0,
        ]
        lockedSelectedTextAttributes = selectedAttrs
        super.selectedTextAttributes = selectedAttrs
        markedTextAttributes = [
            .backgroundColor: NSColor.clear,
            .foregroundColor: color,
            .strokeColor: NSColor.clear,
            .strokeWidth: 0,
            .underlineStyle: 0,
        ]
    }
}

/// Manages inline text editing for the text annotation tool.
/// Owns ALL text state: style, NSTextView lifecycle, formatting, commit, cancel.
@MainActor
class TextEditingController {

    // MARK: - Text style state

    var fontSize: CGFloat = UserDefaults.standard.object(forKey: "textFontSize") as? CGFloat ?? 20
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var strikethrough: Bool = false
    var alignment: NSTextAlignment = .left
    var fontFamily: String = UserDefaults.standard.string(forKey: "textFontFamily") ?? "System"
    var bgEnabled: Bool = UserDefaults.standard.bool(forKey: "textBgEnabled")
    var outlineEnabled: Bool = UserDefaults.standard.bool(forKey: "textOutlineEnabled")

    var bgColor: NSColor = {
        if let data = UserDefaults.standard.data(forKey: "textBgColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) { return color }
        return NSColor.black.withAlphaComponent(0.5)
    }()

    var outlineColor: NSColor = {
        if let data = UserDefaults.standard.data(forKey: "textOutlineColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) { return color }
        return NSColor.white
    }()

    // MARK: - NSTextView

    private(set) var textView: NSTextView?
    private(set) var scrollView: NSScrollView?
    private var windowKeyObserver: NSObjectProtocol?

    var isEditing: Bool { textView != nil }

    /// The annotation being re-edited (removed from canvas, restored on cancel).
    var editingAnnotation: Annotation?

    /// When true, the text box auto-expands width as the user types (new text).
    /// Set to false when editing existing text or after user manually resizes.
    var isAutoWidth: Bool = false

    /// Maximum width for auto-expanding text boxes (set from parent view bounds).
    private var maxAutoWidth: CGFloat = 800

    // MARK: - Font construction

    func currentFont() -> NSFont {
        let fm = NSFontManager.shared
        let baseFont: NSFont
        if fontFamily == "System" {
            baseFont = NSFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        } else if let font = NSFont(name: fontFamily, size: fontSize) {
            baseFont = bold ? fm.convert(font, toHaveTrait: .boldFontMask) : font
        } else {
            baseFont = NSFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        }
        if italic {
            return fm.convert(baseFont, toHaveTrait: .italicFontMask)
        }
        return baseFont
    }

    /// Apply bold/italic to a font, handling system fonts that NSFontManager can't convert via traits.
    func applyBoldItalic(to font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let size = font.pointSize
        let familyName = font.familyName ?? "System"

        // System font: use NSFont.systemFont directly (NSFontManager can't convert SF traits)
        if familyName.hasPrefix(".") || familyName == "System" || fontFamily == "System" {
            var base: NSFont
            if bold && italic {
                base = NSFont.systemFont(ofSize: size, weight: .bold)
                let desc = base.fontDescriptor.withSymbolicTraits(.italic)
                base = NSFont(descriptor: desc, size: size) ?? base
            } else if bold {
                base = NSFont.systemFont(ofSize: size, weight: .bold)
            } else if italic {
                let regular = NSFont.systemFont(ofSize: size, weight: .regular)
                let desc = regular.fontDescriptor.withSymbolicTraits(.italic)
                base = NSFont(descriptor: desc, size: size) ?? regular
            } else {
                base = NSFont.systemFont(ofSize: size, weight: .regular)
            }
            return base
        }

        // Non-system fonts: use NSFontManager trait conversion
        let fm = NSFontManager.shared
        var result = font
        if bold {
            result = fm.convert(result, toHaveTrait: .boldFontMask)
        } else {
            result = fm.convert(result, toNotHaveTrait: .boldFontMask)
        }
        if italic {
            result = fm.convert(result, toHaveTrait: .italicFontMask)
        } else {
            result = fm.convert(result, toNotHaveTrait: .italicFontMask)
        }
        return result
    }

    // MARK: - Style toggles

    private func selectedOrAllRange() -> NSRange {
        guard let tv = textView else { return NSRange(location: 0, length: 0) }
        let sel = tv.selectedRange()
        if sel.length > 0 { return sel }
        return NSRange(location: 0, length: tv.textStorage?.length ?? 0)
    }

    func toggleBold() {
        guard let tv = textView, let ts = tv.textStorage else {
            bold.toggle()
            return
        }
        bold.toggle()
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newFont = self.applyBoldItalic(to: font, bold: self.bold, italic: self.italic)
                    ts.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            ts.endEditing()
        }
        tv.typingAttributes[.font] = currentFont()
        tv.window?.makeFirstResponder(tv)
    }

    func toggleItalic() {
        guard let tv = textView, let ts = tv.textStorage else {
            italic.toggle()
            return
        }
        italic.toggle()
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newFont = self.applyBoldItalic(to: font, bold: self.bold, italic: self.italic)
                    ts.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            ts.endEditing()
        }
        tv.typingAttributes[.font] = currentFont()
        tv.window?.makeFirstResponder(tv)
    }

    func toggleUnderline() {
        guard let tv = textView, let ts = tv.textStorage else {
            underline.toggle()
            return
        }
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.underlineStyle, in: range) { value, attrRange, _ in
                let current = (value as? Int) ?? 0
                if current != 0 {
                    ts.removeAttribute(.underlineStyle, range: attrRange)
                } else {
                    ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: attrRange)
                }
            }
            ts.endEditing()
        }
        underline.toggle()
        if underline {
            tv.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            tv.typingAttributes.removeValue(forKey: .underlineStyle)
        }
        tv.window?.makeFirstResponder(tv)
    }

    func toggleStrikethrough() {
        guard let tv = textView, let ts = tv.textStorage else {
            strikethrough.toggle()
            return
        }
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.strikethroughStyle, in: range) { value, attrRange, _ in
                let current = (value as? Int) ?? 0
                if current != 0 {
                    ts.removeAttribute(.strikethroughStyle, range: attrRange)
                } else {
                    ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: attrRange)
                }
            }
            ts.endEditing()
        }
        strikethrough.toggle()
        if strikethrough {
            tv.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            tv.typingAttributes.removeValue(forKey: .strikethroughStyle)
        }
        tv.window?.makeFirstResponder(tv)
    }

    func applyAlignment() {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = NSRange(location: 0, length: ts.length)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = alignment
        ts.beginEditing()
        ts.addAttribute(.paragraphStyle, value: paraStyle, range: range)
        ts.endEditing()
        tv.alignment = alignment
        tv.typingAttributes[.paragraphStyle] = paraStyle
        tv.window?.makeFirstResponder(tv)
    }

    func applyFontSizeChange() {
        guard let tv = textView else { return }
        let range = selectedOrAllRange()
        tv.textStorage?.addAttribute(.font, value: currentFont(), range: range)
    }

    func applyColorToLiveText(color: NSColor) {
        guard let tv = textView else { return }
        let range = selectedOrAllRange()
        if range.length > 0 {
            tv.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
        }
        tv.typingAttributes[.foregroundColor] = color
        (tv as? NoFocusRingTextView)?.applyEditingChrome(explicitColor: color)
    }

    // MARK: - Show / Create text view

    func show(in parentView: NSView, at canvasPoint: NSPoint, color: NSColor,
              existingText: NSAttributedString? = nil, existingFrame: NSRect = .zero,
              canvas: TextEditingCanvas) {
        dismiss()

        let viewFrame: NSRect
        let isNewText = existingText == nil
        if existingFrame != .zero {
            viewFrame = NSRect(origin: canvas.canvasToView(existingFrame.origin), size: existingFrame.size)
            isAutoWidth = false
            let rightMargin: CGFloat = 20
            let availableCanvasWidth = canvas.textEditingBounds.maxX - canvasPoint.x - rightMargin
            maxAutoWidth = max(1, availableCanvasWidth)
        } else {
            // New text: start narrow and auto-expand
            let height = max(28, fontSize + 12)
            let rightMargin: CGFloat = 20
            let editableBounds = canvas.textEditingBounds
            let preferredWidth = max(40, fontSize * 2 + 16) // ~2 chars + inset
            let maxCanvasWidth = max(1, editableBounds.width - rightMargin)
            var originX = min(max(canvasPoint.x, editableBounds.minX), editableBounds.maxX - 1)
            var initialWidth = min(preferredWidth, maxCanvasWidth)

            if originX + initialWidth > editableBounds.maxX - rightMargin {
                originX = max(editableBounds.minX, editableBounds.maxX - rightMargin - initialWidth)
            }

            let availableCanvasWidth = max(1, editableBounds.maxX - originX - rightMargin)
            initialWidth = min(initialWidth, availableCanvasWidth)
            maxAutoWidth = availableCanvasWidth

            let viewPt = canvas.canvasToView(NSPoint(x: originX, y: canvasPoint.y))
            viewFrame = NSRect(x: viewPt.x, y: viewPt.y - height, width: initialWidth, height: height)
            isAutoWidth = true
        }

        let sv = NoFocusRingScrollView(frame: viewFrame)
        let cv = NoFocusRingClipView(frame: sv.contentView.frame)
        sv.contentView = cv
        
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        // Disable layer to prevent visual artifacts
        sv.wantsLayer = false

        let tv = NoFocusRingTextView(frame: NSRect(origin: .zero, size: viewFrame.size))
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        // Disable layer to prevent visual artifacts
        tv.wantsLayer = false
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        if isNewText {
            // Auto-width: use a very wide container so text doesn't wrap initially
            tv.textContainer?.containerSize = NSSize(width: maxAutoWidth - 8, height: CGFloat.greatestFiniteMagnitude)
            tv.textContainer?.widthTracksTextView = false
        } else {
            tv.textContainer?.containerSize = NSSize(width: viewFrame.width - 8, height: CGFloat.greatestFiniteMagnitude)
            tv.textContainer?.widthTracksTextView = true
        }

        let font = currentFont()
        tv.font = font
        tv.textColor = color

        // Keep selection rendering transparent even after focus changes.
        tv.applyEditingChrome(explicitColor: color)

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = alignment

        if let existing = existingText {
            let sanitized = sanitizedTextForEditing(
                existing,
                defaultFont: font,
                defaultColor: color,
                alignment: alignment
            )
            tv.textStorage?.setAttributedString(sanitized)
        }

        // Build typingAttributes with ALL current style state
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paraStyle,
        ]
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        tv.typingAttributes = attrs
        tv.alignment = alignment

        // Apply paragraph style to any existing text
        let range = NSRange(location: 0, length: tv.textStorage?.length ?? 0)
        if range.length > 0 {
            tv.textStorage?.addAttribute(.paragraphStyle, value: paraStyle, range: range)
        }

        sv.documentView = tv
        parentView.addSubview(sv)

        self.scrollView = sv
        self.textView = tv

        // Watch for window becoming key (e.g. user switches back from another app)
        // to re-strip any system-applied focus decorations
        if let window = parentView.window {
            windowKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak tv, weak sv, weak cv] _ in
                if let tv { stripLayerBorders(tv); tv.applyEditingChrome() }
                if let sv { stripLayerBorders(sv) }
                if let cv { stripLayerBorders(cv) }
                // Deferred strip for system-applied borders after key change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak tv, weak sv, weak cv] in
                    if let tv { stripLayerBorders(tv) }
                    if let sv { stripLayerBorders(sv) }
                    if let cv { stripLayerBorders(cv) }
                }
            }
        }

        parentView.window?.makeFirstResponder(tv)

        // Aggressively strip layer borders after focus change at multiple timings
        // to catch system-applied focus decorations
        stripLayerBorders(sv)
        stripLayerBorders(cv)
        stripLayerBorders(tv)
        for delay in [0.0, 0.05, 0.15, 0.3] as [Double] {
            if delay == 0.0 {
                DispatchQueue.main.async { [weak tv, weak sv, weak cv] in
                    if let tv { tv.applyEditingChrome(); stripLayerBorders(tv) }
                    if let sv { stripLayerBorders(sv) }
                    if let cv { stripLayerBorders(cv) }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak tv, weak sv, weak cv] in
                    if let tv { stripLayerBorders(tv) }
                    if let sv { stripLayerBorders(sv) }
                    if let cv { stripLayerBorders(cv) }
                }
            }
        }

        if existingText != nil { resizeToFit() }
    }

    // MARK: - Commit / Cancel

    /// Commit the current text editing to an annotation on the canvas.
    func commit(canvas: TextEditingCanvas) {
        guard let tv = textView, let sv = scrollView else { return }
        let text = tv.string
        if !text.isEmpty {
            // Ensure scrollView frame matches actual text height before snapshotting
            resizeToFit()
            let attrStr = sanitizedTextForEditing(
                NSAttributedString(attributedString: tv.textStorage!),
                defaultFont: currentFont(),
                defaultColor: (tv.typingAttributes[.foregroundColor] as? NSColor) ?? tv.textColor ?? .white,
                alignment: alignment
            )
            let inset = tv.textContainerInset
            let drawWidth = sv.frame.width - inset.width * 2

            // Measure with NSAttributedString.boundingRect — this matches the
            // layout engine used by attrStr.draw(in:), which can differ from
            // NSLayoutManager.usedRect (used by resizeToFit for live editing).
            // Using the wrong measurement caused the last line to be clipped.
            let textBounds = attrStr.boundingRect(
                with: NSSize(width: drawWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let minH = max(28, fontSize + 12)
            let imgHeight = max(minH, ceil(textBounds.height) + inset.height * 2)
            let imgSize = NSSize(width: sv.frame.width, height: imgHeight)

            // Update scrollView frame to match the measured height so canvas
            // coordinates are correct (pin top edge).
            if abs(imgHeight - sv.frame.height) > 0.5 {
                let topEdge = sv.frame.maxY
                sv.frame = NSRect(x: sv.frame.minX, y: topEdge - imgHeight,
                                  width: sv.frame.width, height: imgHeight)
            }

            let img = NSImage(size: imgSize, flipped: true) { _ in
                attrStr.draw(
                    in: NSRect(
                        x: inset.width, y: inset.height,
                        width: imgSize.width - inset.width * 2,
                        height: imgSize.height - inset.height * 2))
                return true
            }

            let canvasOrigin = canvas.viewToCanvas(sv.frame.origin)
            let canvasEnd = canvas.viewToCanvas(NSPoint(x: sv.frame.maxX, y: sv.frame.maxY))
            let canvasFrame = NSRect(
                x: canvasOrigin.x, y: canvasOrigin.y,
                width: canvasEnd.x - canvasOrigin.x,
                height: canvasEnd.y - canvasOrigin.y)

            let annotation = Annotation(
                tool: .text,
                startPoint: canvasFrame.origin,
                endPoint: NSPoint(x: canvasFrame.maxX, y: canvasFrame.maxY),
                color: canvas.opacityAppliedColor(for: .text),
                strokeWidth: canvas.currentStrokeWidth)
            annotation.attributedText = attrStr
            annotation.text = text
            annotation.fontSize = fontSize
            annotation.isBold = bold
            annotation.isItalic = italic
            annotation.isUnderline = underline
            annotation.isStrikethrough = strikethrough
            annotation.fontFamilyName = fontFamily == "System" ? nil : fontFamily
            annotation.textBgColor = bgEnabled ? bgColor : nil
            annotation.textOutlineColor = outlineEnabled ? outlineColor : nil
            annotation.textAlignment = alignment
            annotation.textImage = img
            annotation.textDrawRect = canvasFrame
            canvas.annotations.append(annotation)
            canvas.undoStack.append(.added(annotation))
            canvas.redoStack.removeAll()
        }
        editingAnnotation = nil
        sv.removeFromSuperview()
        dismiss()
    }

    /// Cancel editing, restoring the original annotation if re-editing.
    func cancel(canvas: TextEditingCanvas) {
        if let ann = editingAnnotation {
            canvas.annotations.append(ann)
            editingAnnotation = nil
        }
        scrollView?.removeFromSuperview()
        dismiss()
    }

    func dismiss() {
        if let observer = windowKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowKeyObserver = nil
        }
        scrollView?.removeFromSuperview()
        scrollView = nil
        textView = nil
    }

    // MARK: - Resize

    /// Auto-resize the text view to fit content, pinning the top edge.
    /// In auto-width mode (new text), also expands width to fit the longest line.
    func resizeToFit() {
        guard let tv = textView, let sv = scrollView else { return }
        guard let textStorage = tv.textStorage else { return }

        let minH = max(28, fontSize + 12)
        let inset = tv.textContainerInset

        // Width: auto-expand in auto-width mode
        var width = sv.frame.width
        let measurementOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        if isAutoWidth {
            let minW = max(40, fontSize * 2 + 16)
            let unconstrainedBounds = textStorage.boundingRect(
                with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                options: measurementOptions
            )
            let contentWidth = ceil(unconstrainedBounds.width) + inset.width * 2
            width = min(maxAutoWidth, max(minW, contentWidth))
        }

        let contentBounds = textStorage.boundingRect(
            with: NSSize(width: max(1, width - inset.width * 2), height: CGFloat.greatestFiniteMagnitude),
            options: measurementOptions
        )
        let newHeight = max(minH, ceil(contentBounds.height) + inset.height * 2)

        let topEdge = sv.frame.maxY
        sv.frame = NSRect(x: sv.frame.minX, y: topEdge - newHeight, width: width, height: newHeight)
        tv.frame.size = NSSize(width: width, height: newHeight)
    }

    func applyLiveFrame(_ frame: NSRect, fitHeightToContent: Bool) {
        guard let tv = textView, let sv = scrollView else { return }

        sv.frame = frame
        tv.frame.size = frame.size
        updateTextContainerWidth(for: frame.width)

        if fitHeightToContent {
            resizeToFit()
        }

        (tv as? NoFocusRingTextView)?.applyEditingChrome()
    }

    func scaleLiveText(to newFontSize: CGFloat) {
        let clampedSize = max(6, min(200, newFontSize))
        let previousSize = max(fontSize, 1)
        fontSize = clampedSize

        guard let tv = textView, let textStorage = tv.textStorage else { return }
        let scaleFactor = clampedSize / previousSize
        let fullRange = NSRange(location: 0, length: textStorage.length)

        if fullRange.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                let baseFont = (value as? NSFont) ?? self.currentFont()
                let resizedFont = NSFontManager.shared.convert(
                    baseFont,
                    toSize: max(6, min(200, baseFont.pointSize * scaleFactor))
                )
                textStorage.addAttribute(.font, value: resizedFont, range: range)
            }
            textStorage.endEditing()
        }

        var typingAttrs = tv.typingAttributes
        typingAttrs[.font] = currentFont()
        tv.typingAttributes = typingAttrs
        tv.font = currentFont()
        (tv as? NoFocusRingTextView)?.applyEditingChrome()
    }

    /// Lock auto-width mode off (called when user manually resizes the text box).
    func lockWidth() {
        guard isAutoWidth else { return }
        isAutoWidth = false
        // Switch text container to wrap at current width
        guard let sv = scrollView else { return }
        updateTextContainerWidth(for: sv.frame.width)
    }

    /// Restore formatting state from an existing annotation for re-editing.
    func restoreState(from annotation: Annotation) {
        fontSize = annotation.fontSize
        bold = annotation.isBold
        italic = annotation.isItalic
        underline = annotation.isUnderline
        strikethrough = annotation.isStrikethrough
        fontFamily = annotation.fontFamilyName ?? "System"
        alignment = annotation.textAlignment
        bgEnabled = annotation.textBgColor != nil
        if let bg = annotation.textBgColor { bgColor = bg }
        outlineEnabled = annotation.textOutlineColor != nil
        if let ol = annotation.textOutlineColor { outlineColor = ol }
    }

    private func updateTextContainerWidth(for viewWidth: CGFloat) {
        guard let tv = textView else { return }
        let inset = tv.textContainerInset.width * 2
        tv.textContainer?.containerSize = NSSize(
            width: max(1, viewWidth - inset),
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.widthTracksTextView = true
    }

}
