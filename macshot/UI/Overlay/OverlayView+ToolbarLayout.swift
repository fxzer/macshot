//
//  OverlayView+ToolbarLayout.swift
//  macshot
//
//  Toolbar construction and positioning for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Toolbar Layout

    /// Rebuild toolbar button content. Call when tool, color, or state changes — NOT on every draw.
    func rebuildToolbarLayout() {
        let t0 = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        NSLog("[PERF] rebuildToolbarLayout BEGIN")
        #endif
        hoveredTooltip = nil
        hoveredTooltipButtonView = nil

        let movableAnnotations = annotations.contains { $0.isMovable }
        bottomButtons = ToolbarLayout.bottomButtons(
            selectedTool: currentTool, selectedColor: currentColor,
            beautifyEnabled: beautifyEnabled, beautifyStyleIndex: beautifyStyleIndex,
            hasAnnotations: movableAnnotations, isRecording: isRecording,
            effectsActive: effectsActive,
            isEditorMode: isEditorMode
        )
        rightButtons = ToolbarLayout.rightButtons(
            selectedTool: currentTool,
            beautifyEnabled: beautifyEnabled, beautifyStyleIndex: beautifyStyleIndex,
            hasAnnotations: movableAnnotations, effectsActive: effectsActive,
            translateEnabled: translateEnabled,
            isRecording: isRecording,
            isEditorMode: isEditorMode)

        let parent = chromeParentView ?? self
        if bottomStripView == nil {
            let strip = ToolbarStripView(orientation: .horizontal)
            strip.horizontalSeparatorAfterIndices = [3, 7]
            parent.addSubview(strip)
            bottomStripView = strip
        }
        if rightStripView == nil {
            let strip = ToolbarStripView(orientation: .vertical)
            parent.addSubview(strip)
            rightStripView = strip
        }

        bottomStripView?.horizontalSeparatorAfterIndices = [3, 7, 11, 13]
        if bottomStripView?.buttonViews.count == bottomButtons.count
            && bottomStripView?.buttonViews.count ?? 0 > 0
        {
            bottomStripView?.updateState(from: bottomButtons)
        } else {
            bottomStripView?.setButtons(bottomButtons)
            bottomStripView?.onClick = { [weak self] action in self?.handleToolbarAction(action) }
            bottomStripView?.onRightClick = { [weak self] action, view in
                self?.handleToolbarButtonRightClick(action, anchorView: view)
            }
            bottomStripView?.onHover = { [weak self] action, hovered in
                self?.handleToolbarButtonHover(action, hovered: hovered, strip: self?.bottomStripView)
            }
        }
        if rightStripView?.buttonViews.count == rightButtons.count
            && rightStripView?.buttonViews.count ?? 0 > 0
        {
            rightStripView?.updateState(from: rightButtons)
        } else {
            rightStripView?.setButtons(rightButtons)
            rightStripView?.onClick = { [weak self] action in self?.handleToolbarAction(action) }
            rightStripView?.onRightClick = { [weak self] action, view in
                self?.handleToolbarButtonRightClick(action, anchorView: view)
            }
            rightStripView?.onHover = { [weak self] action, hovered in
                self?.handleToolbarButtonHover(action, hovered: hovered, strip: self?.rightStripView)
            }
        }
        for bv in rightStripView?.buttonViews ?? [] {
            if case .moveSelection = bv.action, bv.onMouseDown == nil {
                bv.onMouseDown = { [weak self] _ in self?.handleToolbarAction(.moveSelection) }
            }
        }

        for strip in [topStripView, rightStripView] {
            for bv in strip?.buttonViews ?? [] {
                if case .moveSelection = bv.action, bv.onMouseDown == nil {
                    bv.onMouseDown = { [weak self] _ in self?.handleToolbarAction(.moveSelection) }
                }
            }
        }

        if toolHasOptionsRow {
            if toolOptionsRowView == nil {
                let row = ToolOptionsRowView()
                row.overlayView = self
                parent.addSubview(row)
                toolOptionsRowView = row
            }
            if let ann = selectedAnnotation, toolOptionsRowView?.editingAnnotation === ann {
                toolOptionsRowView?.updateSwatchColors()
            } else {
                toolOptionsRowView?.rebuild(for: currentTool)
            }
        }

        repositionToolbars()
        updateUndoRedoButtonStates()
        #if DEBUG
        NSLog(
            "[PERF] rebuildToolbarLayout DONE elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms"
        )
        #endif
    }

    /// Update undo/redo button enabled states based on stack availability.
    func updateUndoRedoButtonStates() {
        let canUndo = !undoStack.isEmpty
        let canRedo = !redoStack.isEmpty

        for strip in [bottomStripView, rightStripView].compactMap({ $0 }) {
            for bv in strip.buttonViews {
                switch bv.action {
                case .undo:
                    bv.isEnabled = canUndo
                case .redo:
                    bv.isEnabled = canRedo
                default:
                    break
                }
            }
        }
    }

    /// Coalesced async toolbar rebuild — avoids blocking event handling (e.g. mouseUp after marquee).
    func scheduleDeferredToolbarRebuild() {
        guard showToolbars else { return }
        guard !pendingToolbarRebuild else { return }
        pendingToolbarRebuild = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pendingToolbarRebuild = false
            guard self.showToolbars, self.window != nil else { return }
            self.rebuildToolbarLayout()
        }
    }

    /// Reposition toolbar strips based on current selection/bounds. Cheap — safe to call from draw().
    func repositionToolbars() {
        guard let bottomStrip = bottomStripView, let rightStrip = rightStripView else { return }

        bottomStrip.passesThrough = isEditorMode
        rightStrip.passesThrough = isEditorMode

        let visible = showToolbars && state == .selected && !isScrollCapturing
        let bottomHasButtons = bottomStrip.buttonViews.count > 0
        bottomStrip.isHidden = !visible || !bottomHasButtons
        let rightHasButtons = rightStrip.buttonViews.count > 0
        rightStrip.isHidden = !visible || !rightHasButtons
        toolOptionsRowView?.isHidden = !visible || !toolHasOptionsRow || !bottomHasButtons
        guard visible else { return }

        let config = beautifyConfig
        let bPad = config.padding
        let titleBarH: CGFloat = config.mode == .window ? 28 : 0
        let expandedAnchor = NSRect(
            x: selectionRect.minX - bPad, y: selectionRect.minY - bPad,
            width: selectionRect.width + bPad * 2,
            height: selectionRect.height + titleBarH + bPad * 2)
        let anchorRect: NSRect
        if beautifyToolbarAnimProgress < 1.0 {
            let t = beautifyToolbarAnimProgress
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            let fromRect = beautifyToolbarAnimTarget ? selectionRect : expandedAnchor
            let toRect = beautifyToolbarAnimTarget ? expandedAnchor : selectionRect
            anchorRect = NSRect(
                x: fromRect.minX + (toRect.minX - fromRect.minX) * eased,
                y: fromRect.minY + (toRect.minY - fromRect.minY) * eased,
                width: fromRect.width + (toRect.width - fromRect.width) * eased,
                height: fromRect.height + (toRect.height - fromRect.height) * eased
            )
        } else if beautifyEnabled && !isScrollCapturing && !isRecording {
            anchorRect = expandedAnchor
        } else {
            anchorRect = selectionRect
        }

        let rightSize = rightStrip.frame.size
        let bottomSize = bottomStrip.frame.size

        if isEditorMode {
            let cb = chromeParentView?.bounds ?? bounds
            bottomStrip.frame.origin = NSPoint(x: cb.midX - bottomSize.width / 2, y: 8)
            bottomStrip.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]

            if let topStrip = topStripView {
                let topBarBottom = topStrip.frame.minY
                rightStrip.frame.origin = NSPoint(
                    x: cb.maxX - rightSize.width - 8,
                    y: topBarBottom - 24 - rightSize.height)
            } else {
                rightStrip.frame.origin = NSPoint(
                    x: cb.maxX - rightSize.width - 8,
                    y: cb.maxY - EditorTopBarView.height - 20 - 8 - rightSize.height)
            }
            rightStrip.autoresizingMask = [.minXMargin, .minYMargin]
        } else {
            let optRowH: CGFloat = 38

            let rightMargin: CGFloat = 50
            let rightFitsRight = anchorRect.maxX < bounds.maxX - rightMargin
            let rightFitsLeft = anchorRect.minX > bounds.minX + rightMargin
            let selectionTooNarrow = !rightFitsRight && !rightFitsLeft
                && anchorRect.width < bounds.width * 0.5

            var rx: CGFloat
            var ry: CGFloat

            if selectionTooNarrow {
                rx = anchorRect.maxX - rightSize.width
                rx = max(bounds.minX + 4, min(rx, bounds.maxX - rightSize.width - 4))
                ry = anchorRect.minY - rightSize.height - 6
                ry = max(bounds.minY + 4, min(ry, bounds.maxY - rightSize.height - 4))
            } else {
                if rightFitsRight {
                    rx = anchorRect.maxX + 6
                } else if rightFitsLeft {
                    rx = anchorRect.minX - rightSize.width - 6
                } else {
                    rx = selectionRect.maxX - rightSize.width - 6
                }
                rx = max(bounds.minX + 4, min(rx, bounds.maxX - rightSize.width - 4))

                ry = anchorRect.maxY - rightSize.height
                ry = max(bounds.minY + 4, min(ry, bounds.maxY - rightSize.height - 4))
            }

            let belowY = anchorRect.minY - bottomSize.height - 6
            let belowFits = (belowY - optRowH) >= bounds.minY + 4
            let aboveY = anchorRect.maxY + optRowH + 6
            let aboveFits = (aboveY + bottomSize.height) <= bounds.maxY - 4

            let centeredBx = anchorRect.midX - bottomSize.width / 2
            let clampedCenteredBx =
                max(bounds.minX + 4, min(centeredBx, bounds.maxX - bottomSize.width - 4))
            func wouldOverlapRight(candidateY: CGFloat) -> Bool {
                let bMinY = candidateY - optRowH
                let bMaxY = candidateY + bottomSize.height
                guard bMaxY > ry && bMinY < ry + rightSize.height else { return false }
                let bMaxX = clampedCenteredBx + bottomSize.width
                let bMinX = clampedCenteredBx
                return bMaxX > rx && bMinX < rx + rightSize.width
            }

            var by: CGFloat
            if belowFits && !wouldOverlapRight(candidateY: belowY) {
                by = belowY
            } else if aboveFits && !wouldOverlapRight(candidateY: aboveY) {
                by = aboveY
            } else if belowFits {
                by = belowY
            } else if aboveFits {
                by = aboveY
            } else {
                by = selectionRect.minY + optRowH + 6
                by = max(
                    bounds.minY + optRowH + 4,
                    min(by, bounds.maxY - bottomSize.height - 4))
            }

            var bx = clampedCenteredBx
            let bottomMinY = by - optRowH
            let bottomMaxY = by + bottomSize.height
            let overlapsVertically = bottomMaxY > ry && bottomMinY < ry + rightSize.height

            if overlapsVertically {
                if bx + bottomSize.width <= rx - 4 || bx >= rx + rightSize.width + 4 {
                    // No overlap.
                } else {
                    let pushRight = bx + bottomSize.width + 4
                    let pushLeft = bx - rightSize.width - 4

                    if pushRight + rightSize.width <= bounds.maxX - 4 {
                        rx = pushRight
                    } else if pushLeft >= bounds.minX + 4 {
                        rx = pushLeft
                    } else {
                        let rightPushDown = by - optRowH - rightSize.height - 4
                        if rightPushDown >= bounds.minY + 4 {
                            ry = rightPushDown
                        } else {
                            let rightPushUp = by + bottomSize.height + 4
                            if rightPushUp + rightSize.height <= bounds.maxY - 4 {
                                ry = rightPushUp
                            }
                        }
                    }
                }
            }
            bx = max(bounds.minX + 4, min(bx, bounds.maxX - bottomSize.width - 4))

            bottomStrip.frame.origin = NSPoint(x: bx, y: by)
            rightStrip.frame.origin = NSPoint(x: rx, y: ry)
        }

        bottomBarRect = bottomStrip.frame
        rightBarRect = rightStrip.frame

        if let row = toolOptionsRowView, !row.isHidden {
            let rowW = max(bottomBarRect.width, row.contentWidth)
            row.frame.size.width = rowW
            if isEditorMode {
                let alignmentRect = bottomBarRect
                let rowX = max(4, alignmentRect.midX - rowW / 2)
                row.frame.origin = NSPoint(x: rowX, y: bottomBarRect.maxY + 2)
                row.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            } else {
                var rowX = bottomBarRect.midX - rowW / 2
                rowX = max(4, min(rowX, bounds.maxX - rowW - 4))
                let rowY = bottomBarRect.minY - row.frame.height - 2
                row.frame.origin = NSPoint(x: rowX, y: rowY)
            }
        }
    }
}
