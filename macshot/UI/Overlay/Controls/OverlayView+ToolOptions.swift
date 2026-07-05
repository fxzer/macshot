//
//  OverlayView+ToolOptions.swift
//  macshot
//
//  Tool options API used by ToolOptionsRowView and color picker popovers.
//

import AppKit

extension OverlayView {

    // MARK: - Tool options API

    func activeStrokeWidthForTool(_ tool: AnnotationTool) -> CGFloat {
        storedStrokeWidth(for: tool)
    }

    func setActiveStrokeWidth(_ value: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .select:
            currentPencilStrokeWidth = value
            UserDefaults.standard.set(Double(value), forKey: "pencilStrokeWidth")
        case .pencil:
            currentPencilStrokeWidth = value
            UserDefaults.standard.set(Double(value), forKey: "pencilStrokeWidth")
        case .line:
            currentLineStrokeWidth = value
            UserDefaults.standard.set(Double(value), forKey: "lineStrokeWidth")
        case .arrow:
            currentArrowStrokeWidth = value
            UserDefaults.standard.set(Double(value), forKey: "arrowStrokeWidth")
        case .number:
            currentNumberSize = value
            UserDefaults.standard.set(Double(value), forKey: "numberStrokeWidth")
        case .marker:
            currentMarkerSize = value
            UserDefaults.standard.set(Double(value), forKey: "markerStrokeWidth")
        case .loupe:
            currentLoupeSize = value
            UserDefaults.standard.set(Double(value), forKey: "loupeSize")
        default:
            updateStoredStrokeWidth(value, for: tool)
            if let key = overlayPerToolStrokeWidthKeys[tool] {
                UserDefaults.standard.set(Double(value), forKey: key)
            } else {
                UserDefaults.standard.set(Double(value), forKey: "currentStrokeWidth")
            }
        }
        refreshToolCursorPreview()
    }

    func showColorPickerPopover(
        target: ColorPickerTarget,
        anchorView: NSView? = nil,
        anchorRect: NSRect = .zero
    ) {
        colorPickerTarget = target
        let picker = ColorPickerView()
        let initialColor: NSColor
        switch target {
        case .drawColor:
            initialColor = currentColor
        case .textBg:
            initialColor = textEditor.bgColor
        case .textOutline:
            initialColor = textEditor.outlineColor
        case .annotationOutline:
            if let data = UserDefaults.standard.data(forKey: "annotationOutlineColor"),
                let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
            {
                initialColor = c
            } else {
                initialColor = .white
            }
        }
        picker.setColor(initialColor, opacity: currentColorOpacity)
        picker.customColors = customColors
        picker.selectedColorSlot = selectedColorSlot

        picker.onColorChanged = { [weak self] color in
            guard let self = self else { return }
            self.applyPickedColor(color)
            picker.saveToSelectedSlot(color)
            self.toolOptionsRowView?.updateSwatchColors()
            self.needsDisplay = true
        }
        picker.onOpacityChanged = { [weak self] opacity in
            guard let self = self else { return }
            self.currentColorOpacity = opacity
            OverlayView.lastUsedOpacity = opacity
            UserDefaults.standard.set(Double(opacity), forKey: "lastUsedColorOpacity")
            self.applyColorToSelectedAnnotation()
            self.needsDisplay = true
        }
        picker.onCustomSlotSelected = { [weak self] idx in
            self?.selectedColorSlot = idx
        }
        picker.onCustomColorsChanged = { [weak self] colors in
            self?.customColors = colors
            self?.saveCustomColors()
        }

        let size = picker.preferredSize
        if let anchor = anchorView {
            PopoverHelper.show(
                picker, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY,
                type: .colorPicker)
        } else if anchorRect != .zero {
            PopoverHelper.showAtPoint(
                picker, size: size, at: NSPoint(x: anchorRect.midX, y: anchorRect.midY), in: self,
                preferredEdge: .minY, type: .colorPicker)
        } else {
            PopoverHelper.showAtPoint(
                picker, size: size, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self,
                preferredEdge: .minY, type: .colorPicker)
        }
    }

    private func applyPickedColor(_ color: NSColor) {
        switch colorPickerTarget {
        case .drawColor:
            currentColor = color
            applyColorToTextIfEditing()
            applyColorToSelectedAnnotation()
        case .textBg:
            textEditor.bgColor = color
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: color, requiringSecureCoding: false)
            {
                UserDefaults.standard.set(data, forKey: "textBgColor")
            }
            applyTextBgOutlineToSelectedAnnotations()
        case .textOutline:
            textEditor.outlineColor = color
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: color, requiringSecureCoding: false)
            {
                UserDefaults.standard.set(data, forKey: "textOutlineColor")
            }
            applyTextBgOutlineToSelectedAnnotations()
        case .annotationOutline:
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: color, requiringSecureCoding: false)
            {
                UserDefaults.standard.set(data, forKey: "annotationOutlineColor")
            }
            for ann in selectedAnnotations {
                ann.outlineColor = color
            }
            invalidateCommittedAnnotationRendering()
        }
        needsDisplay = true
    }
}
