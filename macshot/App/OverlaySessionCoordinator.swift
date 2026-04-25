import Cocoa

@MainActor
final class OverlaySessionCoordinator {

    struct Dependencies {
        let overlayControllers: () -> [OverlayWindowController]
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    private var overlayControllers: [OverlayWindowController] {
        dependencies.overlayControllers()
    }

    func beginSelection(from controller: OverlayWindowController) {
        for other in overlayControllers where other !== controller {
            other.clearSelection()
            other.setRemoteSelection(.zero)
        }
    }

    func changeSelection(from controller: OverlayWindowController, globalRect: NSRect) {
        for other in overlayControllers where other !== controller {
            let localRect = localRect(for: globalRect, on: other)
            let clipped = clippedRect(localRect, on: other)
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func remoteResizeSelection(from controller: OverlayWindowController, globalRect: NSRect) {
        guard let primary = primaryOverlay(excluding: controller) else { return }
        applyPrimarySelection(primary, globalRect: globalRect)

        for other in overlayControllers where other !== controller && other !== primary {
            let localRect = localRect(for: globalRect, on: other)
            let clipped = clippedRect(localRect, on: other)
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func finishRemoteResize(from controller: OverlayWindowController, globalRect: NSRect) {
        guard let primary = primaryOverlay(excluding: controller) else { return }
        applyPrimarySelection(primary, globalRect: globalRect)
        primary.makeKey()

        let primaryOrigin = primary.screen.frame.origin
        let primarySelection = primary.selectionRect
        let primaryGlobal = NSRect(
            x: primarySelection.origin.x + primaryOrigin.x,
            y: primarySelection.origin.y + primaryOrigin.y,
            width: primarySelection.width,
            height: primarySelection.height
        )

        for other in overlayControllers where other !== primary {
            let localRect = localRect(for: primaryGlobal, on: other)
            let clipped = clippedRect(localRect, on: other)
            other.setRemoteSelection(clipped.isEmpty ? .zero : clipped, fullRect: localRect)
        }
    }

    func crossScreenImage(for controller: OverlayWindowController) -> NSImage? {
        let others = overlayControllers.filter {
            $0 !== controller && $0.remoteSelectionRect.width >= 1 && $0.remoteSelectionRect.height >= 1
        }
        guard !others.isEmpty else { return nil }
        return stitchCrossScreenCapture(primary: controller, others: others)
    }

    func handleWindowSnapStateChange(from controller: OverlayWindowController) {
        redrawOtherOverlays(excluding: controller)
    }

    func handleAspectRatioLockChange(from controller: OverlayWindowController) {
        for other in overlayControllers where other !== controller {
            other.syncAspectRatioHintFrom(controller)
        }
    }

    func handleMouseLocationChange(from controller: OverlayWindowController) {
        redrawOtherOverlays(excluding: controller)
    }

    func broadcastHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {
        for controller in overlayControllers {
            controller.syncOverlayHint(
                message: message,
                opacity: opacity,
                colorString: colorString,
                attributedString: attributedString
            )
        }
    }

    func broadcastError(message: String) {
        for controller in overlayControllers {
            controller.syncOverlayError(message: message)
        }
    }

    private func redrawOtherOverlays(excluding controller: OverlayWindowController) {
        for other in overlayControllers where other !== controller {
            other.triggerRedraw()
        }
    }

    private func primaryOverlay(excluding controller: OverlayWindowController) -> OverlayWindowController? {
        overlayControllers.first { $0 !== controller && $0.selectionRect.width >= 1 }
    }

    private func applyPrimarySelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        let primaryOrigin = controller.screen.frame.origin
        let primaryLocal = NSRect(
            x: globalRect.origin.x - primaryOrigin.x,
            y: globalRect.origin.y - primaryOrigin.y,
            width: globalRect.width,
            height: globalRect.height
        )
        controller.applySelection(primaryLocal)
    }

    private func localRect(for globalRect: NSRect, on controller: OverlayWindowController) -> NSRect {
        let origin = controller.screen.frame.origin
        return NSRect(
            x: globalRect.origin.x - origin.x,
            y: globalRect.origin.y - origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    private func clippedRect(_ rect: NSRect, on controller: OverlayWindowController) -> NSRect {
        rect.intersection(NSRect(origin: .zero, size: controller.screen.frame.size))
    }

    private func stitchCrossScreenCapture(
        primary: OverlayWindowController,
        others: [OverlayWindowController]
    ) -> NSImage? {
        let primaryOrigin = primary.screen.frame.origin
        let primarySelection = primary.selectionRect
        let globalRect = NSRect(
            x: primarySelection.origin.x + primaryOrigin.x,
            y: primarySelection.origin.y + primaryOrigin.y,
            width: primarySelection.width,
            height: primarySelection.height
        )

        let scale: CGFloat
        if let screenshot = primary.screenshotImage,
           let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            scale = CGFloat(cgImage.width) / screenshot.size.width
        } else {
            scale = primary.screen.backingScaleFactor
        }

        let pixelWidth = Int(globalRect.width * scale)
        let pixelHeight = Int(globalRect.height * scale)

        let colorSpace: CGColorSpace
        if let screenshot = primary.screenshotImage,
           let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let sourceColorSpace = cgImage.colorSpace {
            colorSpace = sourceColorSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)

        for controller in [primary] + others {
            guard let screenshot = controller.screenshotImage else { continue }
            let screenFrame = controller.screen.frame
            let drawRect = NSRect(
                x: screenFrame.origin.x - globalRect.origin.x,
                y: screenFrame.origin.y - globalRect.origin.y,
                width: screenFrame.width,
                height: screenFrame.height
            )

            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: globalRect.width, height: globalRect.height))
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            screenshot.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: globalRect.size)
    }
}
