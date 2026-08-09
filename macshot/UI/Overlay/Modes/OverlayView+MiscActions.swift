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
              let snapRect = hoveredWindowRect,
              !snapRect.isEmpty,
              snapRect.contains(point),
              ToolShortcutManager.lookupAction(forMouseButton: event.buttonNumber) == .pin
        else { return false }

        selectionRect = snapRect
        selectionIsWindowSnap = true
        snappedWindowID = hoveredWindowID
        state = .selected

        hideColorSamplerMagnifier()
        if currentTool == .colorSampler {
            showColorSamplerMagnifier()
        }

        showToolbars = false
        hoveredWindowRect = nil
        overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
        clearSelectionSizeSnapState()
        overlayDelegate?.overlayViewDidRequestPin()
        needsDisplay = true
        return true
    }
}
