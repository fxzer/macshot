import Cocoa
import UniformTypeIdentifiers

extension OverlayView {
    func showBeautifyPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let content = BeautifyPopoverView(overlayView: self)
        presentOverlayPopover(
            content,
            size: content.preferredSize,
            type: .beautify,
            edge: .minX,
            anchorView: anchorView,
            anchorRect: anchorRect,
            fallbackPoint: NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        )
    }

    func showBeautifyGradientPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = BeautifyBackgroundPickerView(selectedIndex: beautifyStyleIndex, columns: 6, horizontalPadding: 8)
        picker.onSelect = { [weak self] index in
            self?.applyBeautifyStyleSelection(index)
        }
        picker.onCustomImage = { [weak self] in
            PopoverHelper.dismiss()
            self?.pickCustomBeautifyBackground()
        }
        picker.onRemoveCustomImage = { [weak self] in
            self?.removeCustomBeautifyBackgroundSelection()
            PopoverHelper.dismiss()
        }

        presentOverlayPopover(
            picker,
            size: picker.preferredSize,
            type: .beautifyGradient,
            edge: .minY,
            anchorView: anchorView,
            anchorRect: anchorRect,
            fallbackPoint: NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        )
    }

    /// Beautify style shortcuts.
    /// Overlay windows stay key even while the popover is open (`.semitransient`),
    /// so arrow keys would otherwise nudge the selection instead of changing styles.
    @discardableResult
    func handleBeautifyStyleKeys(with event: NSEvent) -> Bool {
        let popoverType = PopoverHelper.currentType
        let pickerOpen = popoverType == .beautify || popoverType == .beautifyGradient
        if pickerOpen, let picker = PopoverHelper.findContentView(BeautifyBackgroundPickerView.self) {
            if picker.handlePickerKey(event) {
                return true
            }
            // Keep leftover arrows from nudging the selection while the picker is open.
            return event.keyCode >= 123 && event.keyCode <= 126
        }

        guard beautifyEnabled, state == .selected, textEditView == nil else { return false }
        guard selectedAnnotations.isEmpty else { return false }
        guard !event.modifierFlags.contains(.shift) else { return false }
        guard !event.modifierFlags.contains(.command) else { return false }
        guard event.keyCode == 123 || event.keyCode == 124 else { return false }

        cycleBeautifyStyle(delta: event.keyCode == 123 ? -1 : 1)
        return true
    }

    func cycleBeautifyStyle(delta: Int) {
        let hasCustom = BeautifyBackgroundStore.hasCustomBackground()
        let count = beautifyStyles.count + (hasCustom ? 1 : 0)
        guard count > 0 else { return }

        let currentSlot = beautifyStyleIndex == -1
            ? beautifyStyles.count
            : max(0, min(beautifyStyleIndex, beautifyStyles.count - 1))
        var nextSlot = (currentSlot + delta) % count
        if nextSlot < 0 { nextSlot += count }
        let index = hasCustom && nextSlot == beautifyStyles.count ? -1 : nextSlot
        applyBeautifyStyleSelection(index)
    }

    func pickCustomBeautifyBackground(completion: (() -> Void)? = nil) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        let savedLevel = window.level
        window.level = .normal
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.window?.level = savedLevel
            guard let self, response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            self.applyCustomBeautifyBackground(image)
            completion?()
        }
    }

    func loadCustomBeautifyBackground() {
        guard let image = BeautifyBackgroundStore.loadImage() else { return }

        customBeautifyBackground = image
        prepareBeautifyBackgroundCache()
    }

    func removeCustomBeautifyBackgroundSelection() {
        let fallbackIndex = max(0, beautifyStyles.count - 1)
        BeautifyBackgroundStore.removeImage()
        customBeautifyBackground = nil
        beautifyStyleIndex = fallbackIndex
        UserDefaults.standard.set(fallbackIndex, forKey: "beautifyStyleIndex")
        refreshBeautifyRendering()
    }
}
