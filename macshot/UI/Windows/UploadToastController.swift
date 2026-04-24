import Cocoa

class UploadToastController {

    private var window: NSPanel?
    private var statusLabel: NSTextField?
    private var linkLabel: NSTextField?
    private var openButton: NSButton?
    private var iconView: NSImageView?
    private var spinner: NSProgressIndicator?
    private var dismissTask: DispatchWorkItem?
    private var currentOpenURL: URL?
    var onDismiss: (() -> Void)?

    private let toastWidth: CGFloat = 380
    private let cornerRadius: CGFloat = 14

    private func screenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    func show(status: String) {
        currentOpenURL = nil
        let screen = screenWithMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let toastHeight: CGFloat = 56
        let topPadding: CGFloat = 12

        // Top-center, just below the menu bar
        let x = screenFrame.midX - toastWidth / 2
        let startY = visibleFrame.maxY + 10
        let finalY = visibleFrame.maxY - toastHeight - topPadding

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: startY, width: toastWidth, height: toastHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentView = ToastBackgroundView(frame: NSRect(origin: .zero, size: NSSize(width: toastWidth, height: toastHeight)))
        contentView.cornerRadius = cornerRadius
        contentView.onClicked = { [weak self] in self?.animateOut() }
        panel.contentView = contentView

        // Success icon using SF Symbols
        let icon = NSImageView(frame: NSRect(x: 14, y: (toastHeight - 28) / 2, width: 28, height: 28))
        if let checkmarkIcon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success") {
            icon.image = checkmarkIcon
            icon.contentTintColor = .systemGreen
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(icon)
        self.iconView = icon

        // Spinner (overlays the icon area during upload)
        let spinnerView = NSProgressIndicator(frame: NSRect(x: 14, y: (toastHeight - 20) / 2, width: 20, height: 20))
        spinnerView.style = .spinning
        spinnerView.controlSize = .small
        spinnerView.startAnimation(nil)
        contentView.addSubview(spinnerView)
        self.spinner = spinnerView
        icon.isHidden = true

        // Status label
        let label = NSTextField(labelWithString: status)
        label.frame = NSRect(x: 50, y: (toastHeight - 18) / 2, width: toastWidth - 66, height: 18)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        contentView.addSubview(label)
        self.statusLabel = label

        self.window = panel
        panel.orderFrontRegardless()

        // Animate in from top
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: x, y: finalY, width: toastWidth, height: toastHeight),
                display: true
            )
        }
    }

    func updateProgress(_ fraction: Double) {
        statusLabel?.stringValue = String(format: L("Uploading... %d%%"), Int(fraction * 100))
    }

    func updateStatus(_ status: String) {
        statusLabel?.stringValue = status
    }

    func showSuccess(link: String, deleteURL: String) {
        _ = deleteURL
        ensureToastWindow()
        currentOpenURL = URL(string: link)
        guard let window = window, let contentView = window.contentView else { return }

        prepareForResultState(symbolName: "checkmark.circle.fill", tintColor: .systemGreen)

        let toastHeight: CGFloat = 56
        resizeToast(window: window, contentView: contentView, height: toastHeight)
        layoutTwoLineToast(
            in: contentView,
            title: L("URL copied to the clipboard"),
            detail: link,
            detailWidth: toastWidth - 140
        )

        let centerY = toastHeight / 2
        let btn = NSButton(frame: NSRect(x: toastWidth - 76, y: centerY - 14, width: 62, height: 28))
        btn.title = L("Open")
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.target = self
        btn.action = #selector(openTarget)
        contentView.addSubview(btn)
        self.openButton = btn

        scheduleDismiss(seconds: 8)
    }

    func showSaveSuccess(fileURL: URL) {
        ensureToastWindow()
        currentOpenURL = fileURL.deletingLastPathComponent()
        guard let window = window, let contentView = window.contentView else { return }

        prepareForResultState(symbolName: "checkmark.circle.fill", tintColor: .systemGreen)
        let toastHeight: CGFloat = 56
        resizeToast(window: window, contentView: contentView, height: toastHeight)
        layoutTwoLineToast(
            in: contentView,
            title: L("Save successful"),
            detail: fileURL.path,
            detailWidth: toastWidth - 140
        )

        let centerY = toastHeight / 2
        let btn = NSButton(frame: NSRect(x: toastWidth - 76, y: centerY - 14, width: 62, height: 28))
        btn.title = L("Open")
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.target = self
        btn.action = #selector(openTarget)
        contentView.addSubview(btn)
        self.openButton = btn

        scheduleDismiss(seconds: 6)
    }

    func showSaveError(message: String) {
        ensureToastWindow()
        currentOpenURL = nil
        guard let window = window, let contentView = window.contentView else { return }

        prepareForResultState(symbolName: "xmark.circle.fill", tintColor: .systemRed)
        let toastHeight: CGFloat = 56
        resizeToast(window: window, contentView: contentView, height: toastHeight)
        layoutTwoLineToast(
            in: contentView,
            title: L("Save failed"),
            detail: message,
            titleColor: .systemRed
        )
        scheduleDismiss(seconds: 6)
    }

    func showError(message: String) {
        spinner?.stopAnimation(nil)
        spinner?.removeFromSuperview()
        spinner = nil

        // 切换为失败图标
        if let icon = iconView {
            if let xmarkIcon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error") {
                icon.image = xmarkIcon
                icon.contentTintColor = .systemRed
            }
            icon.isHidden = false
        }

        guard let panel = window, let contentView = panel.contentView else { return }

        let fullMessage = String(format: L("Upload failed: %@"), message)
        let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let maxLabelW = toastWidth - 66  // 50 left pad + 16 right pad
        let textSize = (fullMessage as NSString).boundingRect(
            with: NSSize(width: maxLabelW, height: 200),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: labelFont]
        ).size

        let toastHeight = max(56, ceil(textSize.height) + 28)

        // Resize and reposition
        let screen = screenWithMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let topPadding: CGFloat = 12
        let x = screen.frame.midX - toastWidth / 2
        let y = visibleFrame.maxY - toastHeight - topPadding

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().setFrame(NSRect(x: x, y: y, width: toastWidth, height: toastHeight), display: true)
        }
        contentView.frame = NSRect(origin: .zero, size: NSSize(width: toastWidth, height: toastHeight))
        contentView.needsDisplay = true

        // Update label to wrap
        statusLabel?.stringValue = fullMessage
        statusLabel?.textColor = .systemRed
        statusLabel?.lineBreakMode = .byWordWrapping
        statusLabel?.maximumNumberOfLines = 0
        statusLabel?.frame = NSRect(x: 50, y: (toastHeight - ceil(textSize.height)) / 2, width: maxLabelW, height: ceil(textSize.height) + 2)

        // Reposition icon
        iconView?.frame = NSRect(x: 14, y: (toastHeight - 28) / 2, width: 28, height: 28)

        scheduleDismiss(seconds: 6)
    }

    private func ensureToastWindow() {
        if window == nil {
            show(status: "")
        }
    }

    private func prepareForResultState(symbolName: String, tintColor: NSColor) {
        spinner?.stopAnimation(nil)
        spinner?.removeFromSuperview()
        spinner = nil

        statusLabel?.removeFromSuperview()
        statusLabel = nil
        linkLabel?.removeFromSuperview()
        linkLabel = nil
        openButton?.removeFromSuperview()
        openButton = nil

        if let icon = iconView {
            icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            icon.contentTintColor = tintColor
            icon.isHidden = false
        }
    }

    private func resizeToast(window: NSPanel, contentView: NSView, height: CGFloat) {
        let screen = screenWithMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let x = screen.frame.midX - toastWidth / 2
        let y = visibleFrame.maxY - height - 12

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().setFrame(NSRect(x: x, y: y, width: toastWidth, height: height), display: true)
        }
        contentView.frame = NSRect(origin: .zero, size: NSSize(width: toastWidth, height: height))
        contentView.needsDisplay = true
    }

    private func layoutTwoLineToast(
        in contentView: NSView,
        title: String,
        detail: String,
        titleColor: NSColor = .labelColor,
        detailWidth: CGFloat = 314
    ) {
        let toastHeight = contentView.bounds.height
        let centerY = toastHeight / 2
        let titleHeight: CGFloat = 18
        let detailHeight: CGFloat = 16
        let spacing: CGFloat = 2
        let totalTextHeight = titleHeight + spacing + detailHeight
        let titleY = centerY + totalTextHeight / 2 - titleHeight
        let detailY = titleY - spacing - detailHeight

        iconView?.frame = NSRect(x: 14, y: centerY - 14, width: 28, height: 28)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 50, y: titleY, width: detailWidth, height: titleHeight)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = titleColor
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)
        statusLabel = titleLabel

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.frame = NSRect(x: 50, y: detailY, width: detailWidth, height: detailHeight)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.isSelectable = false
        contentView.addSubview(detailLabel)
        linkLabel = detailLabel
    }

    private func scheduleDismiss(seconds: Double) {
        dismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.animateOut()
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    @objc private func openTarget() {
        guard let url = currentOpenURL else { return }
        if url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        statusLabel = nil
        linkLabel = nil
        openButton = nil
        iconView = nil
        spinner = nil
        currentOpenURL = nil
        onDismiss?()
        onDismiss = nil
    }

    private func animateOut() {
        guard let window = window else { return }
        let frame = window.frame
        let screen = screenWithMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let offscreenY = screen.visibleFrame.maxY + 10

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(
                NSRect(x: frame.minX, y: offscreenY, width: frame.width, height: frame.height),
                display: true
            )
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }

    func updateLocalization() {
        (window?.contentView as? ToastBackgroundView)?.needsDisplay = true
    }
}

// MARK: - Background view (mimics macOS notification appearance)

private class ToastBackgroundView: NSView {

    var cornerRadius: CGFloat = 14
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Don't dismiss if clicking the "Open" button — let it handle itself
        let point = convert(event.locationInWindow, from: nil)
        for subview in subviews where subview is NSButton {
            if subview.frame.contains(point) {
                super.mouseDown(with: event)
                return
            }
        }
        onClicked?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        // Use the system visual effect material colors for a native feel
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            NSColor(white: 0.18, alpha: 0.92).setFill()
        } else {
            NSColor(white: 0.98, alpha: 0.95).setFill()
        }
        path.fill()

        // Subtle border
        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        border.lineWidth = 0.5
        border.stroke()
    }

    func updateLocalization() {
        needsDisplay = true
    }
}
