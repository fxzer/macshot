import Cocoa

class OCRResultController: NSObject {

    private var window: NSPanel?
    private var textView: NSTextView?
    private var charCountLabel: NSTextField?
    private var copyButton: NSButton?
    private var aiSearchButton: NSButton?
    private var detectedLanguageLabel: NSTextField?
    private var detectedLanguageCode: String?

    private var originalText: String
    private var isLoading = false
    private var hasDetectedText = false

    init(text: String, isLoading: Bool = false) {
        self.originalText = text
        self.isLoading = isLoading
        super.init()
        buildWindow(text: text)
        if isLoading {
            applyLoadingState()
        } else {
            showRecognizedText(text)
        }
    }

    static func loading() -> OCRResultController {
        OCRResultController(text: "", isLoading: true)
    }

    // MARK: - Build

    private func buildWindow(text: String) {
        let W: CGFloat = 520
        let H: CGFloat = 460

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(
            x: screen.visibleFrame.midX - W / 2,
            y: screen.visibleFrame.midY - H / 2
        )

        let panel = KeyablePanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: W, height: H)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = L("Text Recognition")
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 420, height: 300)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let cv = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        cv.autoresizingMask = [.width, .height]

        let contentX: CGFloat = 0
        let contentW = W
        let footerH: CGFloat = 52
        let headerH: CGFloat = 44

        // Header bar (language selector + stats)
        let header = NSView(frame: NSRect(x: contentX, y: H - headerH, width: contentW, height: headerH))
        header.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(header)

        // Detected language label (left side)
        let detectedLabel = NSTextField(labelWithString: "")
        detectedLabel.font = NSFont.systemFont(ofSize: 12)
        detectedLabel.textColor = .secondaryLabelColor
        detectedLabel.lineBreakMode = .byTruncatingTail
        detectedLabel.frame = NSRect(x: 12, y: (headerH - 16) / 2, width: 114, height: 16)
        header.addSubview(detectedLabel)
        self.detectedLanguageLabel = detectedLabel

        // Char/word count label (right side of header)
        let charCount = text.count
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let countLbl = NSTextField(labelWithString: String(format: L("%d chars · %d words"), charCount, wordCount))
        countLbl.font = NSFont.systemFont(ofSize: 11)
        countLbl.textColor = .tertiaryLabelColor
        countLbl.frame = NSRect(x: contentW - 180, y: (headerH - 14) / 2, width: 168, height: 14)
        countLbl.alignment = .right
        countLbl.autoresizingMask = [.minXMargin]
        header.addSubview(countLbl)
        self.charCountLabel = countLbl

        // Header separator
        let headerSep = NSBox(frame: NSRect(x: contentX, y: H - headerH - 1, width: contentW, height: 1))
        headerSep.boxType = .separator
        headerSep.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(headerSep)

        // Footer separator
        let footerSep = NSBox(frame: NSRect(x: contentX, y: footerH, width: contentW, height: 1))
        footerSep.boxType = .separator
        footerSep.autoresizingMask = [.width]
        cv.addSubview(footerSep)

        // Footer bar
        let footer = NSView(frame: NSRect(x: contentX, y: 0, width: contentW, height: footerH))
        footer.autoresizingMask = [.width]
        cv.addSubview(footer)

        // Copy button (primary, right-aligned)
        let copyBtn = NSButton(title: L("Copy") + "  ⌘↩", target: self, action: #selector(copyAll))
        copyBtn.bezelStyle = .rounded
        copyBtn.frame = NSRect(x: contentW - 110, y: (footerH - 28) / 2, width: 100, height: 28)
        copyBtn.autoresizingMask = [.minXMargin]
        copyBtn.keyEquivalent = "\r"
        copyBtn.keyEquivalentModifierMask = [.command]
        (copyBtn.cell as? NSButtonCell)?.backgroundColor = NSColor.controlAccentColor
        footer.addSubview(copyBtn)
        self.copyButton = copyBtn

        // AI Search button
        let aiSearchBtn = NSButton(title: L("AI Search"), target: self, action: #selector(openAISearch))
        aiSearchBtn.bezelStyle = .rounded
        aiSearchBtn.frame = NSRect(x: contentW - 220, y: (footerH - 28) / 2, width: 100, height: 28)
        aiSearchBtn.autoresizingMask = [.minXMargin]
        footer.addSubview(aiSearchBtn)
        self.aiSearchButton = aiSearchBtn

        // Scrollable text view
        let textAreaY = footerH + 1
        let textAreaH = H - headerH - 1 - footerH - 1
        let scrollView = NSScrollView(frame: NSRect(x: contentX, y: textAreaY, width: contentW, height: textAreaH))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        cv.addSubview(scrollView)

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: contentW, height: textAreaH))
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width, .height]
        tv.drawsBackground = false
        tv.usesFindBar = true
        scrollView.documentView = tv
        self.textView = tv

        panel.contentView = cv
        self.window = panel
    }

    // MARK: - Show / Close

    func show() {
        window?.makeKeyAndOrderFront(nil)
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.updateDockIconVisibility()
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tv = self.textView else { return }
            self.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.returnFocusIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func copyAll() {
        guard hasDetectedText, let text = textView?.string, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        close()
    }

    @objc private func openAISearch() {
        guard hasDetectedText, let text = textView?.string, !text.isEmpty else { return }
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)&csuir=1&udm=50") else { return }
        NSWorkspace.shared.open(url)
        close()
    }

    /// Detects the dominant language of the recognized text and shows it.
    /// Also auto-picks the sensible default target: Chinese text → English,
    /// English text → Chinese; other languages keep the saved preference.
    private func updateDetectedLanguage(for text: String) {
        detectedLanguageCode = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detected = Self.detectLanguage(trimmed) else {
            detectedLanguageLabel?.stringValue = ""
            return
        }
        detectedLanguageCode = detected
        detectedLanguageLabel?.stringValue = String(format: L("Detected: %@"), Self.displayName(for: detected))
    }

    /// Chinese/English detection by script counting. This app's OCR workflow
    /// only ever produces Chinese, English, or a mix — no other language logic.
    /// Kana/hangul are deliberately not counted: OCR misreads symbols as
    /// kana (⇄ came back as マ), and one stray glyph must not flip the result.
    private static func detectLanguage(_ text: String) -> String? {
        var cjk = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FAF, 0x3400...0x4DBF, 0xF900...0xFAFF: cjk += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        if cjk > 0, cjk * 2 >= latin { return "zh-Hans" }
        if latin > 0 { return "en" }
        return nil
    }

    private static func displayName(for code: String) -> String {
        switch code {
        case "zh-Hans": return L("Simplified Chinese")
        case "en": return L("English")
        default: return code
        }
    }

    private func updateCharCount(for text: String) {
        let chars = text.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        charCountLabel?.stringValue = String(format: L("%d chars · %d words"), chars, words)
    }

    func showRecognizedText(_ text: String) {
        isLoading = false
        originalText = text

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = trimmed.isEmpty ? L("(No text detected in the selected area)") : text

        textView?.string = displayText
        textView?.textColor = trimmed.isEmpty ? .secondaryLabelColor : .labelColor
        textView?.isEditable = true
        textView?.setSelectedRange(NSRange(location: 0, length: 0))
        textView?.scrollRangeToVisible(NSRange(location: 0, length: 0))

        hasDetectedText = !trimmed.isEmpty
        updateActionAvailability()
        updateCharCount(for: trimmed)
        updateDetectedLanguage(for: text)
    }

    /// Terminal state for a failed recognition (Vision error / timeout). Keeps
    /// result actions disabled — there is no text to copy or translate.
    func showOCRFailure(_ message: String) {
        isLoading = false
        originalText = ""
        hasDetectedText = false
        detectedLanguageCode = nil
        detectedLanguageLabel?.stringValue = ""

        textView?.string = message
        textView?.textColor = .secondaryLabelColor
        textView?.isEditable = false
        textView?.setSelectedRange(NSRange(location: 0, length: 0))

        charCountLabel?.stringValue = ""
        updateActionAvailability()
    }

    private func applyLoadingState() {
        isLoading = true
        originalText = ""
        hasDetectedText = false
        detectedLanguageCode = nil
        detectedLanguageLabel?.stringValue = ""

        textView?.string = L("Recognizing text...")
        textView?.textColor = .secondaryLabelColor
        textView?.isEditable = false
        textView?.setSelectedRange(NSRange(location: 0, length: 0))
        textView?.scrollRangeToVisible(NSRange(location: 0, length: 0))

        charCountLabel?.stringValue = L("Recognizing text...")
        updateActionAvailability()
    }

    private func updateActionAvailability() {
        let canUseResultActions = !isLoading && hasDetectedText
        copyButton?.isEnabled = canUseResultActions
        aiSearchButton?.isEnabled = canUseResultActions
    }

    func updateLocalization() {
        window?.title = L("Text Recognition")
        copyButton?.title = L("Copy")
        aiSearchButton?.title = L("AI Search")
        if let code = detectedLanguageCode, !isLoading {
            detectedLanguageLabel?.stringValue = String(format: L("Detected: %@"), Self.displayName(for: code))
        }
        if isLoading {
            applyLoadingState()
        } else {
            if let tv = textView, let text = tv.textStorage?.string, hasDetectedText {
                updateCharCount(for: text)
            } else {
                textView?.string = L("(No text detected in the selected area)")
                textView?.textColor = .secondaryLabelColor
                updateCharCount(for: "")
            }
        }
    }
}

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Ensure Cmd+C, Cmd+A, Cmd+Z etc. always reach the first responder (NSTextView).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the first responder handle standard text editing shortcuts first.
        if let fr = firstResponder as? NSTextView {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.keyCode {
                case 8:  fr.copy(nil);      return true  // C
                case 7:  fr.cut(nil);       return true  // X
                case 9:  fr.paste(nil);     return true  // V
                case 0:  fr.selectAll(nil); return true  // A
                case 6:  fr.undoManager?.undo(); return true  // Z
                default: break
                }
            }
            if flags == [.command, .shift], event.keyCode == 6 {  // Z
                fr.undoManager?.redo(); return true
            }
        }
        // Cmd+W to close — handle outside the text view check so it always works
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 13 {  // W
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
