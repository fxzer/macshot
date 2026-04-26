import Cocoa

// MARK: - Custom Window subclass

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var autorecalculatesKeyViewLoop: Bool {
        get { false }
        set { }
    }

    /// Tags on `OverlayView` inline numeric `NSTextField`s (zoom). Field editor stays transparent so rounded pills drawn in `OverlayView` remain visible.
    private static let overlayInlineNumericFieldTags: Set<Int> = [889]

    override func fieldEditor(_ createFlag: Bool, for obj: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: obj)
        guard let textView = editor as? NSTextView,
              let field = obj as? NSTextField,
              Self.overlayInlineNumericFieldTags.contains(field.tag)
        else { return editor }

        let font =
            field.font
            ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        // Transparent so `OverlayView.drawSizeLabel` / `drawZoomLabel` rounded pills stay visible; opaque editor would hide corner radius and look taller.
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.white.withAlphaComponent(0.35),
            .foregroundColor: NSColor.white,
        ]
        return textView
    }
}
