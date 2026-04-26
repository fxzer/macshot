import Cocoa

@MainActor
final class ScreenshotOutputCoordinator: NSObject, PinWindowControllerDelegate {

    struct Dependencies {
        let resolveTargetScreen: () -> NSScreen?
    }

    private let dependencies: Dependencies

    private var pinControllers: [PinWindowController] = []
    private var thumbnailControllers: [FloatingThumbnailController] = []
    private var uploadToastController: UploadToastController?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        super.init()
    }

    private var resolveTargetScreen: NSScreen? {
        dependencies.resolveTargetScreen()
    }

    var hasVisibleFloatingPanels: Bool {
        !thumbnailControllers.isEmpty || !pinControllers.isEmpty
    }

    var excludedWindowNumbers: [CGWindowID] {
        Array(Set(thumbnailControllers.compactMap { $0.windowNumber })).sorted()
    }

    func hideThumbnails() {
        for controller in thumbnailControllers {
            controller.hideWindow()
        }
    }

    func showThumbnails() {
        for controller in thumbnailControllers {
            controller.showWindow()
        }
    }

    func updateLocalization() {
        for thumbnail in thumbnailControllers {
            thumbnail.updateLocalization()
        }
        for pin in pinControllers {
            pin.updateLocalization()
        }
        uploadToastController?.updateLocalization()
    }

    func showStatusError(message: String) {
        makeStatusToast().showError(message: message)
    }

    func showFloatingThumbnail(
        image: NSImage,
        annotationData: CaptureAnnotationData? = nil,
        historyEntryID: String? = nil
    ) {
        let enabled = UserDefaults.standard.object(forKey: "showFloatingThumbnail") as? Bool ?? true
        guard enabled else { return }

        let stacking = UserDefaults.standard.object(forKey: "thumbnailStacking") as? Bool ?? true
        if !stacking {
            thumbnailControllers.forEach { $0.dismiss() }
            thumbnailControllers.removeAll()
        }

        let screen = resolveTargetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let displayID = screenDisplayID(for: screen)
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let gap: CGFloat = 8

        let screenControllers = thumbnailControllers.filter { $0.anchorDisplayID == displayID }
        var yOrigin = screenFrame.minY + padding
        if let topController = screenControllers.last {
            yOrigin = topController.windowFrame.maxY + gap
        }

        // Memory optimization: create a pre-rendered thumbnail for display instead of holding the full image
        // The thumbnail is ~240x160 pixels vs the full selection image which can be 8MB+
        let scale = CGFloat(UserDefaults.standard.object(forKey: "thumbnailScale") as? Double ?? 1.0)
        let thumbnailSize = NSSize(width: round(240 * scale), height: round(160 * scale))
        let thumbnailImage = NSImage(size: thumbnailSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return true }
            // High-quality interpolation for thumbnail
            context.imageInterpolation = .high
            image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                     from: NSRect(origin: .zero, size: image.size),
                     operation: .copy,
                     fraction: 1.0)
            return true
        }

        let controller = FloatingThumbnailController(image: thumbnailImage)
        controller.historyEntryID = historyEntryID
        controller.onDismiss = { [weak self] in
            let displayID = controller.anchorDisplayID
            self?.thumbnailControllers.removeAll { $0 === controller }
            self?.reflowThumbnails(onDisplayID: displayID)
        }
        // Keep full image reference for immediate actions (copy, save, pin)
        // These actions need the full resolution image, not the thumbnail
        controller.onCopy = { [weak self] in
            self?.copyImageFromHistory(entryID: historyEntryID, fallbackImage: image)
        }
        controller.onSave = { [weak self] in
            self?.saveImageFromHistory(entryID: historyEntryID, fallbackImage: image)
        }
        controller.onPin = { [weak self] in
            self?.pinImageFromHistory(entryID: historyEntryID, fallbackImage: image)
        }
        // Edit loads the full raw image from history for annotation editing
        controller.onEdit = { [weak self] in
            if let data = annotationData {
                DetachedEditorWindowController.open(
                    image: data.rawImage,
                    annotations: data.annotations,
                    historyEntryID: historyEntryID
                )
            } else if let self = self {
                // Fallback: load from history
                self.openEditorFromHistory(entryID: historyEntryID, fallbackImage: image)
            }
        }
        controller.onUpload = { [weak self] in
            self?.uploadImageFromHistory(entryID: historyEntryID, fallbackImage: image)
        }
        controller.onCloseAll = { [weak self] in
            let all = self?.thumbnailControllers ?? []
            self?.thumbnailControllers.removeAll()
            for controller in all {
                controller.dismiss()
            }
        }
        controller.onSaveAll = { [weak self] in
            self?.saveAllThumbnailsToFolder()
        }
        thumbnailControllers.append(controller)
        controller.show(on: screen, atY: yOrigin)
    }

    func refreshThumbnail(for entryID: String, image: NSImage) {
        for controller in thumbnailControllers where controller.historyEntryID == entryID {
            controller.updateImage(image)
        }
    }

    func performScreenshotPostActions(
        image: NSImage,
        annotationData: CaptureAnnotationData?,
        historyEntryID: String?,
        windowTitle: String?,
        context: CaptureCompletionContext
    ) {
        let actions = PostCaptureActionPreferences.screenshotActions

        if actions.copyToClipboard {
            ImageEncoder.copyToClipboard(image)
        }
        if actions.saveToFile && context != .manualSave {
            let showInFinder = UserDefaults.standard.bool(forKey: "screenshotShowInFinder")
            saveImageToDefaultDirectory(image, windowTitle: windowTitle, showInFinder: showInFinder)
        }
        if actions.uploadAndCopyLink {
            uploadImage(image)
        }
        if actions.pinToScreen {
            showPin(image: image)
        }
        if actions.openEditor {
            if let data = annotationData {
                DetachedEditorWindowController.open(
                    image: data.rawImage,
                    annotations: data.annotations,
                    historyEntryID: historyEntryID
                )
            } else {
                DetachedEditorWindowController.open(
                    image: image,
                    historyEntryID: historyEntryID,
                    disableBeautify: true
                )
            }
        }
        if actions.showQuickAccessOverlay {
            showFloatingThumbnail(image: image, annotationData: annotationData, historyEntryID: historyEntryID)
        }

        SoundManager.shared.playCapture()
    }

    func saveImageToPreferredDirectory(
        _ image: NSImage,
        kind: FilenameOutputKind = .screenshot,
        showInFinder: Bool = false,
        showFailureToast: Bool = true,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        ImageSaveService.saveToDefaultDirectoryAsync(image, kind: kind) { [weak self] result in
            self?.showSaveResultToast(result, showFailureToast: showFailureToast)
            if case .success(let fileURL) = result, showInFinder {
                _ = FinderRevealService.reveal(fileURL)
            }
            completion?(result)
        }
    }

    func showSaveResultToast(_ result: Result<URL, Error>, showFailureToast: Bool = true) {
        let toast = makeStatusToast()
        switch result {
        case .success(let fileURL):
            toast.showSaveSuccess(fileURL: fileURL)
        case .failure(let error):
            guard showFailureToast else { return }
            let message = error.localizedDescription.isEmpty ? L("Save failed") : error.localizedDescription
            toast.showSaveError(message: message)
        }
    }

    func uploadImage(_ image: NSImage) {
        showUploadProgress(image: image)
    }

    func showPin(image: NSImage, at origin: NSPoint? = nil) {
        let pin = PinWindowController(image: image, at: origin)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
    }

    func pinWindowDidClose(_ controller: PinWindowController) {
        pinControllers.removeAll { $0 === controller }
    }

    private func screenDisplayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func saveAllThumbnailsToFolder() {
        let images = thumbnailControllers.map(\.image)
        guard !images.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder to save \(images.count) screenshot\(images.count == 1 ? "" : "s")"
        panel.level = .floating

        panel.begin { [weak self] response in
            guard response == .OK, let dirURL = panel.url else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                var firstError: Error?
                for image in images {
                    let baseName = FilenameTemplateEngine.makeBaseName(kind: .screenshot, date: Date())
                    let fileURL = FilenameTemplateEngine.uniqueDestinationURL(
                        in: dirURL,
                        baseName: baseName,
                        fileExtension: ImageEncoder.fileExtension
                    )
                    switch ImageSaveService.save(image, to: fileURL) {
                    case .success:
                        break
                    case .failure(let error):
                        firstError = firstError ?? error
                    }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error = firstError {
                        self.makeStatusToast().showSaveError(
                            message: error.localizedDescription.isEmpty ? L("Save failed") : error.localizedDescription
                        )
                    } else {
                        let all = self.thumbnailControllers
                        self.thumbnailControllers.removeAll()
                        for controller in all {
                            controller.dismiss()
                        }
                    }
                }
            }
        }
    }

    private func reflowThumbnails(onDisplayID targetDisplayID: CGDirectDisplayID? = nil) {
        let padding: CGFloat = 16
        let gap: CGFloat = 8

        let displayIDs: [CGDirectDisplayID?]
        if let targetDisplayID {
            displayIDs = [targetDisplayID]
        } else {
            var orderedDisplayIDs: [CGDirectDisplayID?] = []
            for controller in thumbnailControllers where !orderedDisplayIDs.contains(controller.anchorDisplayID) {
                orderedDisplayIDs.append(controller.anchorDisplayID)
            }
            displayIDs = orderedDisplayIDs
        }

        for displayID in displayIDs {
            let screen = NSScreen.screens.first { screenDisplayID(for: $0) == displayID }
                ?? NSScreen.main
                ?? NSScreen.screens[0]
            var y = screen.visibleFrame.minY + padding
            for controller in thumbnailControllers where controller.anchorDisplayID == displayID {
                let height = controller.windowFrame.height
                controller.moveTo(y: y)
                y += height + gap
            }
        }
    }

    private func saveImageToDefaultDirectory(_ image: NSImage, windowTitle: String?, showInFinder: Bool = false) {
        _ = windowTitle
        saveImageToPreferredDirectory(image, showInFinder: showInFinder)
    }

    private func makeStatusToast() -> UploadToastController {
        uploadToastController?.dismiss()
        let toast = UploadToastController()
        uploadToastController = toast
        toast.onDismiss = { [weak self, weak toast] in
            guard let self else { return }
            if self.uploadToastController === toast {
                self.uploadToastController = nil
            }
        }
        return toast
    }

    private func showUploadProgress(image: NSImage) {
        uploadToastController?.dismiss()
        let toast = UploadToastController()
        uploadToastController = toast
        toast.onDismiss = { [weak self] in
            self?.uploadToastController = nil
        }
        toast.show(status: L("Uploading..."))

        let provider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"

        if provider == "gdrive" && !GoogleDriveUploader.shared.isSignedIn {
            toast.showError(message: L("Sign in to Google Drive in Settings"))
            return
        }

        if provider == "s3" && !S3Uploader.shared.isConfigured {
            toast.showError(message: L("Configure S3 in Settings"))
            return
        }

        if provider == "gdrive" {
            let progressHandler: (Double) -> Void = { fraction in
                toast.updateProgress(fraction)
            }
            GoogleDriveUploader.shared.uploadImage(image, progress: progressHandler) { result in
                switch result {
                case .success(let link):
                    PasteboardWriter.writeString(link)
                    UploadHistoryStore.append(link: link, provider: provider, thumbnail: image)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else if provider == "s3" {
            S3Uploader.shared.uploadImage(image, progress: nil) { result in
                switch result {
                case .success(let link):
                    PasteboardWriter.writeString(link)
                    UploadHistoryStore.append(link: link, provider: provider, thumbnail: image)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        } else {
            ImageUploader.upload(image: image) { result in
                switch result {
                case .success(let uploadResult):
                    PasteboardWriter.writeString(uploadResult.link)
                    UploadHistoryStore.append(
                        link: uploadResult.link,
                        deleteURL: uploadResult.deleteURL,
                        provider: provider,
                        thumbnail: image
                    )
                    toast.showSuccess(link: uploadResult.link, deleteURL: uploadResult.deleteURL)
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - History Image Loading Helpers

    /// Copy image to clipboard from history entry, with fallback to provided image
    private func copyImageFromHistory(entryID: String?, fallbackImage: NSImage) {
        if let entryID = entryID,
           let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }),
           let image = ScreenshotHistory.shared.loadImage(for: entry) {
            ImageEncoder.copyToClipboard(image)
        } else {
            ImageEncoder.copyToClipboard(fallbackImage)
        }
    }

    /// Save image from history entry, with fallback to provided image
    private func saveImageFromHistory(entryID: String?, fallbackImage: NSImage) {
        if let entryID = entryID,
           let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }),
           let image = ScreenshotHistory.shared.loadImage(for: entry) {
            saveImageToPreferredDirectory(image)
        } else {
            saveImageToPreferredDirectory(fallbackImage)
        }
    }

    /// Pin image from history entry, with fallback to provided image
    private func pinImageFromHistory(entryID: String?, fallbackImage: NSImage) {
        if let entryID = entryID,
           let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }),
           let image = ScreenshotHistory.shared.loadImage(for: entry) {
            showPin(image: image)
        } else {
            showPin(image: fallbackImage)
        }
    }

    /// Upload image from history entry, with fallback to provided image
    private func uploadImageFromHistory(entryID: String?, fallbackImage: NSImage) {
        if let entryID = entryID,
           let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }),
           let image = ScreenshotHistory.shared.loadImage(for: entry) {
            uploadImage(image)
        } else {
            uploadImage(fallbackImage)
        }
    }

    /// Open editor from history entry, with fallback to provided image
    private func openEditorFromHistory(entryID: String?, fallbackImage: NSImage) {
        if let entryID = entryID,
           let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }),
           let rawImage = ScreenshotHistory.shared.loadRawImage(for: entry),
           let annotations = ScreenshotHistory.shared.loadAnnotations(for: entry) {
            DetachedEditorWindowController.open(
                image: rawImage,
                annotations: annotations,
                historyEntryID: entryID
            )
        } else {
            DetachedEditorWindowController.open(
                image: fallbackImage,
                historyEntryID: entryID,
                disableBeautify: true
            )
        }
    }
}
