import CoreGraphics

enum PinWindowSizing {
    static let oneToOneScale: CGFloat = 1.0
    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 5.0

    static func fittedScale(imageSize: CGSize, visibleFrame: CGRect) -> CGFloat {
        guard imageSize.width > 0,
              imageSize.height > 0,
              visibleFrame.width > 0,
              visibleFrame.height > 0 else {
            return oneToOneScale
        }

        let maxWidth = visibleFrame.width * 0.8
        let maxHeight = visibleFrame.height * 0.8
        return min(oneToOneScale, min(maxWidth / imageSize.width, maxHeight / imageSize.height))
    }

    static func windowSize(imageSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: round(imageSize.width * scale), height: round(imageSize.height * scale))
    }

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(maxScale, max(minScale, scale))
    }
}
