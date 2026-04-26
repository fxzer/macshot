//
//  OverlayView+UndoRedo.swift
//  macshot
//
//  Undo/redo system for annotations and image transformations.
//

import AppKit

extension OverlayView {

    // MARK: - Public API

    func undo() {
        guard let entry = undoStack.last else { return }
        undoStack.removeLast()
        switch entry {
        case .added(let ann):
            // Undo an addition — handle batch (groupID) or single
            if let groupID = ann.groupID {
                var batch: [UndoEntry] = [.added(ann)]
                while let prev = undoStack.last, prev.annotation.groupID == groupID {
                    undoStack.removeLast()
                    batch.append(prev)
                }
                for e in batch { annotations.removeAll { $0 === e.annotation } }
                if ann.tool == .number { numberCounter = max(0, numberCounter - batch.count) }
                if ann.tool == .translateOverlay { translateEnabled = false; rebuildToolbarLayout() }
                redoStack.append(contentsOf: batch)
                clearHoverIfNeeded(batch.map { $0.annotation })
            } else {
                annotations.removeAll { $0 === ann }
                if ann.tool == .number { numberCounter = max(0, numberCounter - 1) }
                if ann.tool == .translateOverlay { translateEnabled = false; rebuildToolbarLayout() }
                redoStack.append(.added(ann))
                clearHoverIfNeeded([ann])
            }
        case .deleted(let ann, let idx):
            // Undo a deletion — re-insert at original position
            let safeIdx = min(idx, annotations.count)
            annotations.insert(ann, at: safeIdx)
            if ann.tool == .number { numberCounter += 1 }
            redoStack.append(.deleted(ann, idx))
        case .propertyChange(let ann, let snapshot):
            // Undo property change — swap current state with snapshot
            let currentSnapshot = ann.propertyChangeSnapshot()
            ann.copyProperties(from: snapshot)
            if ann.tool == .loupe, ann.bakedBlurNSImage == nil {
                ann.bakeLoupe()
            }
            if (ann.tool == .pixelate || ann.tool == .blur), ann.bakedBlurNSImage == nil {
                // snapshot.sourceImage may be nil (cleared to save memory); fall back to
                // the annotation's own sourceImage or the current screenshot.
                if ann.sourceImage == nil {
                    ann.sourceImage = screenshotImage
                    ann.sourceImageBounds = captureDrawRect
                }
                ann.bakePixelate()
            }
            redoStack.append(.propertyChange(annotation: ann, snapshot: currentSnapshot))
            cachedCompositedImage = nil
        case .imageTransform(let previousImage, _):
            // Undo crop/flip — swap the current image with the saved one
            let currentImage = screenshotImage?.copy() as? NSImage ?? previousImage
            redoStack.append(.imageTransform(previousImage: currentImage, annotationOffsets: []))
            screenshotImage = previousImage
            // Update selectionRect to match restored image size
            if isEditorMode {
                selectionRect = NSRect(origin: .zero, size: previousImage.size)
                if isInsideScrollView { frame.size = previousImage.size }
            }
            cachedCompositedImage = nil
            resetZoom()
        }
        invalidateAnnotationCaches()
        cachedCompositedImage = nil
        syncToolOptionsForCurrentSelection()
        needsDisplay = true
    }

    func redo() {
        guard let entry = redoStack.last else { return }
        redoStack.removeLast()
        switch entry {
        case .added(let ann):
            if let groupID = ann.groupID {
                var batch: [UndoEntry] = [.added(ann)]
                while let next = redoStack.last, next.annotation.groupID == groupID {
                    redoStack.removeLast()
                    batch.append(next)
                }
                for e in batch { annotations.append(e.annotation) }
                if ann.tool == .number { numberCounter += batch.count }
                undoStack.append(contentsOf: batch)
            } else {
                annotations.append(ann)
                if ann.tool == .number { numberCounter += 1 }
                undoStack.append(.added(ann))
            }
        case .deleted(let ann, let idx):
            // Redo a deletion — remove again
            annotations.removeAll { $0 === ann }
            if ann.tool == .number { numberCounter = max(0, numberCounter - 1) }
            undoStack.append(.deleted(ann, idx))
        case .propertyChange(let ann, let snapshot):
            // Redo property change — swap again
            let currentSnapshot = ann.propertyChangeSnapshot()
            ann.copyProperties(from: snapshot)
            if ann.tool == .loupe, ann.bakedBlurNSImage == nil {
                ann.bakeLoupe()
            }
            if (ann.tool == .pixelate || ann.tool == .blur), ann.bakedBlurNSImage == nil {
                // Same fallback as undo path above.
                if ann.sourceImage == nil {
                    ann.sourceImage = screenshotImage
                    ann.sourceImageBounds = captureDrawRect
                }
                ann.bakePixelate()
            }
            undoStack.append(.propertyChange(annotation: ann, snapshot: currentSnapshot))
            cachedCompositedImage = nil
        case .imageTransform(let redoImage, _):
            // Redo crop/flip — swap back
            let currentImage = screenshotImage?.copy() as? NSImage ?? redoImage
            undoStack.append(.imageTransform(previousImage: currentImage, annotationOffsets: []))
            screenshotImage = redoImage
            if isEditorMode {
                selectionRect = NSRect(origin: .zero, size: redoImage.size)
                if isInsideScrollView { frame.size = redoImage.size }
            }
            cachedCompositedImage = nil
            if !isInsideScrollView { resetZoom() }
        }
        invalidateAnnotationCaches()
        cachedCompositedImage = nil
        syncToolOptionsForCurrentSelection()
        needsDisplay = true
    }

    // MARK: - Private Helpers

    private func clearHoverIfNeeded(_ removed: [Annotation]) {
        var changed = false
        if let h = hoveredAnnotation, removed.contains(where: { $0 === h }) {
            hoveredAnnotationClearTimer?.invalidate()
            hoveredAnnotationClearTimer = nil
            hoveredAnnotation = nil
            changed = true
        }
        let beforeCount = selectedAnnotations.count
        selectedAnnotations.removeAll { ann in removed.contains(where: { $0 === ann }) }
        if selectedAnnotations.count != beforeCount {
            changed = true
        }
    }
}
