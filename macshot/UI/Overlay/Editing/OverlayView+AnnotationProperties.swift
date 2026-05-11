import AppKit

extension OverlayView {
    func invalidateCommittedAnnotationRendering() {
        invalidateAnnotationCaches()
        cachedCompositedImage = nil
        needsDisplay = true
    }

    func syncToolOptionsForCurrentSelection() {
        if let ann = selectedAnnotation, toolOptionsRowView?.editingAnnotation === ann {
            toolOptionsRowView?.rebuild(forAnnotation: ann)
        } else if selectedAnnotations.isEmpty {
            toolOptionsRowView?.rebuild(for: currentTool)
        }
    }

    @objc func saveAsMenuAction() {
        overlayDelegate?.overlayViewDidRequestSave()
    }

    func pushPropertyChangeUndo(annotation: Annotation, snapshot: Annotation) {
        guard !annotation.hasEquivalentPropertyState(to: snapshot) else { return }
        undoStack.append(.propertyChange(annotation: annotation, snapshot: snapshot))
        redoStack.removeAll()
        cachedCompositedImage = nil
    }

    func nextNumberValueForNewAnnotation() -> Int {
        if let highestExistingNumber = annotations.lazy
            .filter({ $0.tool == .number && $0.numberFormat == self.currentNumberFormat })
            .compactMap(\.number)
            .max()
        {
            return highestExistingNumber + 1
        }
        return NumberToolConfiguration.clampedStartValue(numberStartAt)
    }

    /// Debounce helper for scroll-wheel property adjustments.
    /// Runs `commit` once scrolling stops, then rebuilds all annotation caches.
    func scheduleScrollPropertyCommit(_ commit: @escaping () -> Void) {
        pendingScrollPropertyCommit = commit
        scrollPropertyAdjustTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.pendingScrollPropertyCommit?()
            self.finishScrollPropertyAdjustmentState()
        }
    }

    func finalizeScrollPropertyAdjustmentIfNeeded() {
        guard isScrollAdjustingProperty else { return }
        scrollPropertyAdjustTimer?.invalidate()
        scrollPropertyAdjustTimer = nil
        pendingScrollPropertyCommit?()
        finishScrollPropertyAdjustmentState()
    }

    func finishScrollPropertyAdjustmentState() {
        pendingScrollPropertyCommit = nil
        isScrollAdjustingProperty = false
        invalidateAnnotationCaches()
        cachedCompositedImage = nil
        scrollPropertyAdjustTimer = nil
        needsDisplay = true
    }

    func applyColorToSelectedAnnotation() {
        guard !selectedAnnotations.isEmpty else { return }
        for ann in selectedAnnotations {
            ann.color = opacityAppliedColor(for: ann.tool)
            if ann.tool == .pixelate || ann.tool == .blur {
                if ann.censorMode != .solid {
                    ann.sourceImage = ann.sourceImage ?? screenshotImage
                    ann.sourceImageBounds = captureDrawRect
                }
                ann.bakedBlurNSImage = nil
                ann.bakePixelate()
            }
        }
        toolOptionsRowView?.updateSwatchColors()
        invalidateCommittedAnnotationRendering()
    }

    /// Apply current text formatting from textEditor to selected text annotations (when not actively editing).
    func applyTextFormattingToSelectedAnnotations() {
        guard textEditor.textView == nil else { return }  // skip if actively editing
        var changed = false
        for ann in selectedAnnotations where ann.tool == .text {
            ann.fontSize = textEditor.fontSize
            ann.isBold = textEditor.bold
            ann.isItalic = textEditor.italic
            ann.isUnderline = textEditor.underline
            ann.isStrikethrough = textEditor.strikethrough
            ann.fontFamilyName = textEditor.fontFamily == "System" ? nil : textEditor.fontFamily
            ann.textAlignment = textEditor.alignment
            ann.reRenderTextImage()
            changed = true
        }
        if changed {
            invalidateCommittedAnnotationRendering()
        }
    }

    /// Apply text background/outline toggle to selected text annotations.
    func applyTextBgOutlineToSelectedAnnotations() {
        guard textEditor.textView == nil else { return }
        var changed = false
        for ann in selectedAnnotations where ann.tool == .text {
            ann.textBgColor = textEditor.bgEnabled ? textEditor.bgColor : nil
            ann.textOutlineColor = textEditor.outlineEnabled ? textEditor.outlineColor : nil
            changed = true
        }
        if changed {
            invalidateCommittedAnnotationRendering()
        }
    }

    /// Returns currentColor with opacity applied for tools that respect it.
    /// Marker uses a fixed alpha in its draw method; loupe/measure/pixelate/blur are color-independent.
    func opacityAppliedColor(for tool: AnnotationTool) -> NSColor {
        switch tool {
        case .marker, .loupe, .measure, .pixelate, .blur, .translateOverlay:
            return currentColor
        default:
            return annotationColor
        }
    }
}
