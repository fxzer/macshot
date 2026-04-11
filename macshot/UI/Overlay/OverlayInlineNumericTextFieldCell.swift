import Cocoa

/// Centers single-line text vertically in the cell bounds so overlay size / zoom pills match `NSString.draw(at:)` layout next to `padding / 2` baselines.
final class OverlayInlineNumericTextFieldCell: NSTextFieldCell {

    override init(textCell string: String) {
        super.init(textCell: string)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func textHeight() -> CGFloat {
        let f = font ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let s = (stringValue as NSString).size(withAttributes: [.font: f])
        return ceil(s.height)
    }

    private func verticallyCentered(_ inner: NSRect, in rect: NSRect) -> NSRect {
        let th = textHeight()
        guard rect.height > th else { return inner }
        var r = inner
        r.origin.y = rect.minY + floor((rect.height - th) / 2)
        r.size.height = th
        return r
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        verticallyCentered(super.drawingRect(forBounds: rect), in: rect)
    }

    override func select(
        withFrame aRect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
        start selStart: Int, length selLength: Int
    ) {
        let inner = super.drawingRect(forBounds: aRect)
        let r = verticallyCentered(inner, in: aRect)
        super.select(withFrame: r, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame aRect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let inner = super.drawingRect(forBounds: aRect)
        let r = verticallyCentered(inner, in: aRect)
        super.edit(withFrame: r, in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}
