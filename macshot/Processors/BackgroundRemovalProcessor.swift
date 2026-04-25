import Cocoa
import Vision

enum BackgroundRemovalProcessor {
    final class CancellationToken {
        private let lock = NSLock()
        private var cancelled = false
        private var request: VNRequest?

        func cancel() {
            lock.lock()
            cancelled = true
            let request = request
            lock.unlock()
            request?.cancel()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        fileprivate func attach(_ request: VNRequest) {
            lock.lock()
            self.request = request
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel {
                request.cancel()
            }
        }
    }

    enum ProcessingError: LocalizedError {
        case invalidImage
        case noSubjectFound
        case filterUnavailable(String)
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Unable to read the selected image."
            case .noSubjectFound:
                return "No clear subject found."
            case .filterUnavailable(let name):
                return "Required image filter is unavailable: \(name)."
            case .renderFailed:
                return "Background removal failed."
            }
        }
    }

    private static let queue = DispatchQueue(
        label: "com.fxzer.macshot.background-removal",
        qos: .userInitiated
    )

    @available(macOS 14.0, *)
    @discardableResult
    static func removeBackground(
        from image: NSImage,
        completion: @escaping (CancellationToken, Result<NSImage, Error>) -> Void
    ) -> CancellationToken {
        let token = CancellationToken()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }
                completion(token, .failure(ProcessingError.invalidImage))
            }
            return token
        }

        queue.async {
            guard !token.isCancelled else { return }

            let request = VNGenerateForegroundInstanceMaskRequest()
            token.attach(request)
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
                guard !token.isCancelled else { return }
                guard
                    let result = request.results?.first,
                    !result.allInstances.isEmpty
                else {
                    throw ProcessingError.noSubjectFound
                }

                let maskPixelBuffer = try result.generateScaledMaskForImage(
                    forInstances: result.allInstances,
                    from: handler
                )
                guard !token.isCancelled else { return }

                let originalCIImage = CIImage(cgImage: cgImage)
                let softenedMask = try softenedMask(from: maskPixelBuffer)
                guard !token.isCancelled else { return }

                guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
                    throw ProcessingError.filterUnavailable("CIBlendWithMask")
                }
                blendFilter.setValue(originalCIImage, forKey: kCIInputImageKey)
                blendFilter.setValue(softenedMask, forKey: kCIInputMaskImageKey)
                blendFilter.setValue(
                    CIImage(color: .clear).cropped(to: originalCIImage.extent),
                    forKey: kCIInputBackgroundImageKey
                )

                guard
                    let outputCIImage = blendFilter.outputImage,
                    let finalCGImage = BeautifyRenderer.sharedCIContext.createCGImage(
                        outputCIImage,
                        from: originalCIImage.extent
                    )
                else {
                    throw ProcessingError.renderFailed
                }

                let finalImage = NSImage(cgImage: finalCGImage, size: image.size)
                DispatchQueue.main.async {
                    guard !token.isCancelled else { return }
                    completion(token, .success(finalImage))
                }
            } catch {
                DispatchQueue.main.async {
                    guard !token.isCancelled else { return }
                    completion(token, .failure(error))
                }
            }
        }

        return token
    }

    @available(macOS 14.0, *)
    private static func softenedMask(from pixelBuffer: CVPixelBuffer) throws -> CIImage {
        let maskImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            throw ProcessingError.filterUnavailable("CIGaussianBlur")
        }
        blurFilter.setValue(maskImage.clampedToExtent(), forKey: kCIInputImageKey)
        blurFilter.setValue(0.8, forKey: kCIInputRadiusKey)
        guard let softenedMask = blurFilter.outputImage?.cropped(to: maskImage.extent) else {
            throw ProcessingError.renderFailed
        }
        return softenedMask
    }
}
