import Cocoa

@MainActor
final class RecordingToastController {

    private let url: URL
    private var window: NSPanel?
    private var toastView: RecordingToastView?
    private var dismissTask: DispatchWorkItem?

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onUpload: (() -> Void)?
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?

    init(url: URL) {
        self.url = url
    }

    func show() {
        let size = NSSize(width: 360, height: 96)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let frame = NSRect(
            x: visibleFrame.maxX - size.width - padding,
            y: visibleFrame.minY + padding,
            width: size.width,
            height: size.height
        )

        let panel = NSPanel(
            contentRect: frame,
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

        let view = RecordingToastView(frame: NSRect(origin: .zero, size: size), url: url)
        view.onClose = { [weak self] in self?.dismiss() }
        view.onCopy = { [weak self] in self?.onCopy?(); self?.dismiss() }
        view.onSave = { [weak self] in self?.onSave?(); self?.dismiss() }
        view.onUpload = { [weak self] in self?.onUpload?(); self?.dismiss() }
        view.onOpen = { [weak self] in self?.onOpen?(); self?.dismiss() }

        panel.contentView = view
        panel.orderFrontRegardless()

        window = panel
        toastView = view
        scheduleDismiss(after: 12)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        toastView = nil
        onDismiss?()
        onDismiss = nil
    }

    func updateLocalization() {
        toastView?.updateLocalization()
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }
}

private final class RecordingToastView: NSView {

    private let url: URL
    private var titleLabel: NSTextField?
    private var subtitleLabel: NSTextField?
    private var copyButton: NSButton?
    private var saveButton: NSButton?
    private var uploadButton: NSButton?
    private var openButton: NSButton?
    private var closeButton: NSButton?

    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onUpload: (() -> Void)?
    var onOpen: (() -> Void)?

    init(frame: NSRect, url: URL) {
        self.url = url
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = NSColor.systemRed
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let closeButton = NSButton(title: "", target: self, action: #selector(closePressed))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        self.closeButton = closeButton

        let titleLabel = NSTextField(labelWithString: L("Recording"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        self.titleLabel = titleLabel

        let subtitleLabel = NSTextField(labelWithString: url.lastPathComponent)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)
        self.subtitleLabel = subtitleLabel

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonsStack)

        let copyButton = makeButton(title: L("Copy"), action: #selector(copyPressed))
        let saveButton = makeButton(title: L("Save"), action: #selector(savePressed))
        let uploadButton = makeButton(title: L("Upload"), action: #selector(uploadPressed))
        let openButton = makeButton(title: L("Open"), action: #selector(openPressed))

        [copyButton, saveButton, uploadButton, openButton].forEach(buttonsStack.addArrangedSubview)
        self.copyButton = copyButton
        self.saveButton = saveButton
        self.uploadButton = uploadButton
        self.openButton = openButton

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            buttonsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            buttonsStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            buttonsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    func updateLocalization() {
        titleLabel?.stringValue = L("Recording")
        copyButton?.title = L("Copy")
        saveButton?.title = L("Save")
        uploadButton?.title = L("Upload")
        openButton?.title = L("Open")
    }

    @objc private func closePressed() {
        onClose?()
    }

    @objc private func copyPressed() {
        onCopy?()
    }

    @objc private func savePressed() {
        onSave?()
    }

    @objc private func uploadPressed() {
        onUpload?()
    }

    @objc private func openPressed() {
        onOpen?()
    }
}
