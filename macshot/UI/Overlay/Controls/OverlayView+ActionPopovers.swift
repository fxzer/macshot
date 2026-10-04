import Cocoa

extension OverlayView {
    func showUploadConfirmPopover(anchorRect: NSRect, anchorView: NSView? = nil) {
        let toggle = makeOverlayCheckbox(
            L("Confirm before upload"),
            isOn: UserDefaults.standard.bool(forKey: "uploadConfirmEnabled")
        ) {
            UserDefaults.standard.set($0, forKey: "uploadConfirmEnabled")
        }
        toggle.sizeToFit()

        let size = NSSize(width: max(180, toggle.frame.width + 20), height: 32)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        toggle.frame.origin = NSPoint(x: 10, y: (size.height - toggle.frame.height) / 2)
        content.addSubview(toggle)

        presentOverlayPopover(
            content,
            size: size,
            type: .uploadConfirm,
            edge: anchorView == nil ? .maxX : .maxY,
            anchorView: anchorView,
            anchorRect: anchorRect,
            fallbackPoint: NSPoint(x: anchorRect.maxX + 4, y: anchorRect.midY)
        )
    }

    func showRedactTypePopover(anchorRect: NSRect, anchorView: NSView? = nil) {
        let types = AutoRedactor.redactTypeNames
        let picker = ListPickerView()
        picker.items = types.map {
            .init(title: $0.label, isSelected: UserDefaults.standard.object(forKey: $0.key) as? Bool ?? true)
        }
        picker.onSelect = { [weak self] index in
            let key = types[index].key
            let newValue = !(UserDefaults.standard.object(forKey: key) as? Bool ?? true)
            UserDefaults.standard.set(newValue, forKey: key)
            picker.updateItem(at: index, isSelected: newValue)
            self?.needsDisplay = true
        }

        presentOverlayPopover(
            picker,
            size: picker.preferredSize,
            type: .redactType,
            edge: anchorView == nil ? .maxX : .maxY,
            anchorView: anchorView,
            anchorRect: anchorRect,
            fallbackPoint: NSPoint(x: anchorRect.maxX + 4, y: anchorRect.midY)
        )
    }

    func showEmojiPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = EmojiPickerView()
        picker.onSelectEmoji = { [weak self] emoji in
            self?.currentStampImage = StampEmojis.renderEmoji(emoji)
            self?.currentStampEmoji = emoji
            self?.needsDisplay = true
        }

        presentOverlayPopover(
            picker,
            size: picker.preferredSize,
            type: .emoji,
            edge: .maxY,
            anchorView: anchorView,
            anchorRect: anchorRect,
            fallbackPoint: NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        )
    }

    func showEffectsPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = EffectsPickerView(config: effectsConfig)
        picker.onConfigChanged = { [weak self] in
            self?.applyEffects($0)
        }

        presentOverlayPopover(
            picker,
            size: picker.preferredSize,
            type: .effects,
            edge: .minX,
            anchorView: anchorView,
            anchorRect: anchorRect,
            fallbackPoint: NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        )
    }
}
