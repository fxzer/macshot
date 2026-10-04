import AppKit
import Vision

enum VisionOCR {

    /// Recognition languages in priority order: Chinese + English only — the
    /// only languages this app's users OCR. Vision's
    /// `automaticallyDetectsLanguage` scans every supported language model
    /// (33 on current macOS) — measured 66s on a 4800×2800 screenshot vs 0.5s
    /// with explicit languages, and per-line auto-detection also mispicks
    /// models ("更新日志" came back as "TEa"). Explicit is faster AND more
    /// accurate, so auto-detection stays off.
    private static let preferredRecognitionLanguages = ["zh-Hans", "en-US"]

    /// Vision timeout. Healthy recognition finishes in well under a second;
    /// this only exists so a pathological Vision stall can't leave the OCR
    /// window spinning forever.
    static let recognitionTimeout: TimeInterval = 20

    struct RecognitionTimeoutError: LocalizedError {
        let seconds: TimeInterval
        var errorDescription: String? {
            String(format: L("OCR timed out after %d s"), Int(seconds))
        }
    }

    /// `preferredRecognitionLanguages` filtered down to what this OS supports
    /// for the given level (older systems support fewer languages).
    static func recognitionLanguages(for level: VNRequestTextRecognitionLevel) -> [String] {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = level
        let supported = (try? probe.supportedRecognitionLanguages()) ?? []
        return preferredRecognitionLanguages.filter { supported.contains($0) }
    }

    static func makeTextRecognitionRequest(
        level: VNRequestTextRecognitionLevel = .accurate,
        completionHandler: @escaping (VNRequest, Error?) -> Void
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest(completionHandler: completionHandler)
        request.recognitionLevel = level
        // Language correction is meaningless at `.fast` and adds cost — disable it.
        request.usesLanguageCorrection = (level == .accurate)
        request.recognitionLanguages = recognitionLanguages(for: level)
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = false
        }
        return request
    }

    /// Runs text recognition on a background queue with a watchdog timeout.
    /// Unlike calling `perform` directly, the completion is guaranteed to fire
    /// exactly once on the main thread for every outcome — success, Vision
    /// error, `perform` throwing without invoking the request callback, or
    /// timeout — so callers can never be left in a loading state forever.
    static func recognizeText(
        in cgImage: CGImage,
        level: VNRequestTextRecognitionLevel = .accurate,
        timeout: TimeInterval = recognitionTimeout,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let lock = NSLock()
        var delivered = false
        func deliverOnce(_ result: Result<String, Error>) {
            lock.lock()
            let alreadyDelivered = delivered
            delivered = true
            lock.unlock()
            guard !alreadyDelivered else { return }
            DispatchQueue.main.async { completion(result) }
        }

        let request = makeTextRecognitionRequest(level: level) { request, error in
            if let error = error {
                deliverOnce(.failure(error))
                return
            }
            let lines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            deliverOnce(.success(lines.joined(separator: "\n")))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                lock.lock()
                let alreadyDelivered = delivered
                lock.unlock()
                guard !alreadyDelivered else { return }
                request.cancel()
                deliverOnce(.failure(RecognitionTimeoutError(seconds: timeout)))
            }
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                // perform() can throw without ever invoking the request callback.
                deliverOnce(.failure(error))
            }
        }
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
