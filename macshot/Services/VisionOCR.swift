import AppKit
import Vision

enum VisionOCR {

    static func makeTextRecognitionRequest(
        level: VNRequestTextRecognitionLevel = .accurate,
        completionHandler: @escaping (VNRequest, Error?) -> Void
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest(completionHandler: completionHandler)
        request.recognitionLevel = level
        // Language correction is meaningless at `.fast` and adds cost — disable it.
        request.usesLanguageCorrection = (level == .accurate)
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        return request
    }

    static func cropSelectionToCGImage(
        screenshot: NSImage,
        selectionRect: NSRect,
        captureDrawRect: NSRect
    ) -> CGImage? {
        guard
            !selectionRect.isEmpty,
            !captureDrawRect.isEmpty,
            let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let croppedSelection = selectionRect.intersection(captureDrawRect)
        guard !croppedSelection.isEmpty else { return nil }

        let normalizedX = (croppedSelection.minX - captureDrawRect.minX) / captureDrawRect.width
        let normalizedY = (croppedSelection.minY - captureDrawRect.minY) / captureDrawRect.height
        let normalizedWidth = croppedSelection.width / captureDrawRect.width
        let normalizedHeight = croppedSelection.height / captureDrawRect.height

        let cgWidth = CGFloat(cgImage.width)
        let cgHeight = CGFloat(cgImage.height)
        let rawMinX = max(0, normalizedX * cgWidth)
        let rawMinY = max(0, (1.0 - normalizedY - normalizedHeight) * cgHeight)
        let rawMaxX = min(cgWidth, rawMinX + normalizedWidth * cgWidth)
        let rawMaxY = min(cgHeight, rawMinY + normalizedHeight * cgHeight)
        let pixelRect = CGRect(
            x: floor(rawMinX),
            y: floor(rawMinY),
            width: max(0, ceil(rawMaxX) - floor(rawMinX)),
            height: max(0, ceil(rawMaxY) - floor(rawMinY))
        )

        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        return cgImage.cropping(to: pixelRect)
    }
}
