import AppKit

extension OverlayView {
    override func otherMouseDown(with event: NSEvent) {
        if handleToolShortcutMouseButton(event) { return }
    }

    func applyColorToTextIfEditing() {
        if textEditor.isEditing {
            textEditor.applyColorToLiveText(color: annotationColor)
        }
    }

    func handleToolShortcutMouseButton(_ event: NSEvent) -> Bool {
        guard state == .selected,
              textEditView == nil,
              !isScrollCapturing,
              currentAnnotation == nil,
              !isDraggingAnnotation,
              !isDraggingSelection,
              !isResizingSelection,
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control),
              let action = ToolShortcutManager.lookupAction(forMouseButton: event.buttonNumber)
        else { return false }

        if case .detach = action {
            if shouldAllowDetach() {
                handleToolbarAction(.detach)
                return true
            }
            return false
        }

        handleToolbarAction(action)
        return true
    }

    func handleWindowSnapPinClick(at point: NSPoint, event: NSEvent) -> Bool {
        guard state == .idle,
              windowSnapEnabled,
              ToolShortcutManager.lookupAction(forMouseButton: event.buttonNumber) == .pin
        else { return false }

        // 右键贴图同样以点击瞬间的鼠标位置为准，不沿用异步悬停的结果。
        guard let target = confirmWindowSnapTarget(at: point), !target.rect.isEmpty else { return false }
        selectionRect = target.rect
        selectionIsWindowSnap = true
        snappedWindowID = target.windowID
        state = .selected

        hideColorSamplerMagnifier()
        if currentTool == .colorSampler {
            showColorSamplerMagnifier()
        }

        showToolbars = false
        clearWindowSnapHover()
        overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
        clearSelectionSizeSnapState()
        overlayDelegate?.overlayViewDidRequestPin()
        needsDisplay = true
        return true
    }
}
