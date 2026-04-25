//
//  OverlayView+Clipboard.swift
//  macshot
//
//  Annotation clipboard helpers.
//

import AppKit

extension OverlayView {

    // MARK: - Annotation Copy/Paste

    static let annotationPasteboardType = NSPasteboard.PasteboardType("com.fxzer.macshot.annotations")

    func copySelectedAnnotations() {
        let toCopy = selectedAnnotations.isEmpty ? [] : selectedAnnotations
        guard !toCopy.isEmpty else { return }
        guard let data = AnnotationSerializer.encode(toCopy) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: Self.annotationPasteboardType)
    }

    func pasteAnnotations() {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: Self.annotationPasteboardType),
            let pasted = AnnotationSerializer.decode(data)
        else { return }
        selectedAnnotations = []
        var newAnnotations: [Annotation] = []
        for ann in pasted {
            let copy = ann.clone()
            copy.move(dx: 15, dy: -15)
            annotations.append(copy)
            undoStack.append(.added(copy))
            newAnnotations.append(copy)
        }
        redoStack.removeAll()
        selectedAnnotations = newAnnotations
        cachedCompositedImage = nil
        needsDisplay = true
    }
}
