import Cocoa

extension OverlayView {

    /// 当前是否处于“按住辅助键即识别同色矩形区域”的悬停状态。
    var canHoverRegionSnap: Bool {
        isRegionSnapActive && !suppressBackdropUntilCapture
    }

    /// 懒加载并缓存 1x 降采样位图，供区域识别后台线程只读查询。
    func ensureRegionSnapBitmap() -> RegionSnapDetector.Bitmap? {
        if let existing = captureSessionState.regionSnapBitmap,
           existing.viewSize == bounds.size
        {
            return existing
        }
        guard let cgImage = displayCGImage
            ?? originalCGImage
            ?? colorSamplingCGImage
            ?? screenshotImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let bitmap = RegionSnapDetector.makeBitmap(from: cgImage, viewSize: bounds.size)
        captureSessionState.regionSnapBitmap = bitmap
        return bitmap
    }

    /// 同步修饰键（Option）状态：按住立即切入区域识别，松开恢复常规窗口吸附。
    func syncRegionSnapModifierState(with flags: NSEvent.ModifierFlags) {
        guard !isEditorMode, !isScrollCapturing else {
            if isRegionSnapKeyHeld {
                isRegionSnapKeyHeld = false
                clearRegionSnapHover()
            }
            return
        }

        let optionHeld = flags.contains(.option)
        guard optionHeld != isRegionSnapKeyHeld else { return }
        isRegionSnapKeyHeld = optionHeld

        if optionHeld {
            clearWindowSnapHover()
            // 区域识别期间隐藏取色放大镜，避免亮白方块遮挡卡片边缘与尺寸胶囊。
            hideColorSamplerMagnifier()
            if state == .idle && !windowSnapCooldown {
                refreshRegionSnapHoverAtMouseLocation()
            }
        } else {
            clearRegionSnapHover()
            if state == .idle && screenshotImage != nil {
                showColorSamplerMagnifier()
                updateMagnifierIfNeeded()
            }
            if state == .idle && !windowSnapCooldown {
                refreshWindowSnapHoverAtMouseLocation()
            }
        }

        overlayDelegate?.overlayViewDidChangeWindowSnapState()
        needsDisplay = true
    }

    /// 鼠标移动或按下辅助键时的异步区域识别（后台执行扫描线填充，避免阻塞主线程）。
    func queryRegionSnap(at viewPoint: NSPoint) {
        guard canHoverRegionSnap,
              let viewWindow = window,
              let bitmap = ensureRegionSnapBitmap()
        else { return }

        let overlayWindowNumber = viewWindow.windowNumber
        let overlayWindowOrigin = viewWindow.frame.origin
        let overlayBounds = bounds

        captureSessionState.regionSnapHover.track(
            viewPoint,
            query: { point, completion in
                let screenPoint = NSPoint(
                    x: overlayWindowOrigin.x + point.x,
                    y: overlayWindowOrigin.y + point.y
                )
                DispatchQueue.global(qos: .userInteractive).async {
                    let clipRect = WindowSnapDetector.target(
                        atScreenPoint: screenPoint,
                        overlayWindowNumber: overlayWindowNumber,
                        overlayWindowOrigin: overlayWindowOrigin,
                        overlayBounds: overlayBounds
                    )?.rect
                    let target = RegionSnapDetector.target(
                        in: bitmap,
                        atViewPoint: point,
                        clipRect: clipRect
                    )
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { completion(target) }
                    }
                }
            },
            handler: { [weak self] _ in
                guard let self else { return }
                self.needsDisplay = true
            }
        )
    }

    /// 同步识别点击松开瞬间的局部区域，避免高速移动鼠标时选中上一帧缓存区域。
    func confirmRegionSnapTarget(at viewPoint: NSPoint) -> RegionSnapDetector.Target? {
        guard !isEditorMode,
              !isScrollCapturing,
              !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1),
              let viewWindow = window,
              let screenPoint = screenPointForWindowSnap(viewPoint),
              let bitmap = ensureRegionSnapBitmap()
        else { return nil }

        clearRegionSnapHover()
        let clipRect = WindowSnapDetector.target(
            atScreenPoint: screenPoint,
            overlayWindowNumber: viewWindow.windowNumber,
            overlayWindowOrigin: viewWindow.frame.origin,
            overlayBounds: bounds
        )?.rect
        return RegionSnapDetector.target(in: bitmap, atViewPoint: viewPoint, clipRect: clipRect)
    }

    /// 清空区域悬停高亮，并丢弃尚未返回的在途查询。
    func clearRegionSnapHover() {
        if captureSessionState.regionSnapHover.invalidate() {
            needsDisplay = true
        }
    }

    /// 释放区域识别缓存位图。
    func invalidateRegionSnapCache() {
        captureSessionState.regionSnapBitmap = nil
    }

    /// 按下 Option 时立即识别当前鼠标所在区域的矩形。
    func refreshRegionSnapHoverAtMouseLocation() {
        guard !windowSnapCooldown, !suppressBackdropUntilCapture,
              let window, window.frame.contains(NSEvent.mouseLocation)
        else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = convert(windowPoint, from: nil)
        queryRegionSnap(at: viewPoint)
    }

    /// 绘制区域识别高亮框（沿用系统/用户主题色 `ToolbarLayout.accentColor` + 柔和对比底边 + 尺寸胶囊）。
    func drawRegionSnapHighlight() {
        guard canHoverRegionSnap, let rect = hoveredRegionRect, !rect.isEmpty else {
            return
        }

        let strokeRect = rect.insetBy(dx: -0.5, dy: -0.5)
        let outerShadow = NSBezierPath(roundedRect: strokeRect, xRadius: 4, yRadius: 4)
        outerShadow.lineWidth = 3.5
        NSColor.black.withAlphaComponent(0.35).setStroke()
        outerShadow.stroke()

        let border = NSBezierPath(roundedRect: strokeRect, xRadius: 4, yRadius: 4)
        border.lineWidth = 2.0
        ToolbarLayout.accentColor.withAlphaComponent(0.95).setStroke()
        border.stroke()

        drawRegionSnapSizeBadge(for: rect)
    }

    private func drawRegionSnapSizeBadge(for rect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2.0
        let pixelW = max(1, Int(round(rect.width * scale)))
        let pixelH = max(1, Int(round(rect.height * scale)))
        let text = "\(pixelW) \u{00D7} \(pixelH)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.sharedSizeLabelFont,
            .foregroundColor: ToolbarLayout.iconColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 7
        let padY: CGFloat = 3
        let badgeW = textSize.width + padX * 2
        let badgeH = textSize.height + padY * 2

        var badgeX = rect.minX
        var badgeY = rect.maxY + 6
        if badgeY + badgeH > bounds.maxY - 4 {
            badgeY = max(bounds.minY + 4, rect.minY - badgeH - 6)
        }
        badgeX = max(bounds.minX + 4, min(badgeX, bounds.maxX - badgeW - 4))

        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        ToolbarLayout.bgColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()

        (text as NSString).draw(
            at: NSPoint(x: badgeRect.minX + padX, y: badgeRect.minY + padY),
            withAttributes: attrs
        )
    }
}
