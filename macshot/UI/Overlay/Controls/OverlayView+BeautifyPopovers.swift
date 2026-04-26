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
