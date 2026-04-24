import Cocoa
import Vision

enum BackgroundRemovalProcessor {
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
    static func removeBackground(
        from image: NSImage,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DispatchQueue.main.async {
                completion(.failure(ProcessingError.invalidImage))
            }
            return
        }

        queue.async {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
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

                let originalCIImage = CIImage(cgImage: cgImage)
                let softenedMask = try softenedMask(from: maskPixelBuffer)

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
                    completion(.success(finalImage))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
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
