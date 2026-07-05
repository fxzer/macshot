import Cocoa

@MainActor
final class ScreenshotOutputCoordinator: NSObject, PinWindowControllerDelegate, StatusToastHost {

    struct Dependencies {
        let resolveTargetScreen: () -> NSScreen?
    }

    private let dependencies: Dependencies

    private var pinControllers: [PinWindowController] = []
    private var thumbnailControllers: [FloatingThumbnailController] = []
    // `internal` to satisfy `StatusToastHost.uploadToastController`; access stays
    // within the coordinator layer.
    var uploadToastController: UploadToastController?

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
        Array(Set(thumbnailControllers.compactMap { $0.windowNumberForCaptureExclusion })).sorted()
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
        var memory = MemoryDiagnostics.makeScope(
            "ScreenshotOutput.showFloatingThumbnail",
            images: [
                ("image", image),
                ("annotationRawImage", annotationData?.rawImage)
            ],
            metadata: "historyEntryID=\(historyEntryID ?? "nil") thumbnails=\(thumbnailControllers.count)"
        )
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

        // Memory optimization: keep only a downscaled display image in the floating panel.
        // The drag/export actions still resolve the full screenshot lazily from history.
        let scale = CGFloat(UserDefaults.standard.object(forKey: "thumbnailScale") as? Double ?? 1.0)
        let thumbnailSize = NSSize(width: round(240 * scale), height: round(160 * scale))
        let thumbnailImage = makeThumbnailDisplayImage(from: image, targetSize: thumbnailSize)
        let exportImageProvider: () -> NSImage?
        if let historyEntryID {
            exportImageProvider = { [weak self] in
                self?.loadImageFromHistory(entryID: historyEntryID)
            }
        } else {
            exportImageProvider = { image }
        }

        let controller = FloatingThumbnailController(
            image: thumbnailImage,
            exportImageProvider: exportImageProvider
        )
        controller.historyEntryID = historyEntryID
        controller.onDismiss = { [weak self] in
            let displayID = controller.anchorDisplayID
            self?.thumbnailControllers.removeAll { $0 === controller }
            self?.reflowThumbnails(onDisplayID: displayID)
        }
        // Memory optimization: closures now load from history instead of capturing the large image
        // This allows the original image to be released while the thumbnail is visible
        controller.onCopy = { [weak self] in
            self?.copyImageFromHistory(entryID: historyEntryID, fallbackImage: nil)
        }
        controller.onSave = { [weak self] in
            self?.saveImageFromHistory(entryID: historyEntryID, fallbackImage: nil)
        }
        controller.onPin = { [weak self] in
            self?.pinImageFromHistory(entryID: historyEntryID, fallbackImage: nil)
        }
        controller.onEdit = { [weak self] in
            if let self = self, let historyEntryID {
                self.openEditorFromHistory(entryID: historyEntryID, fallbackImage: nil)
            } else if let data = annotationData {
                DetachedEditorWindowController.open(
                    image: data.rawImage,
                    annotations: data.annotations,
                    historyEntryID: historyEntryID
                )
            }
        }
        controller.onUpload = { [weak self] in
            self?.uploadImageFromHistory(entryID: historyEntryID, fallbackImage: nil)
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
        memory.finish(
            "thumbnail shown",
            images: [("thumbnailImage", thumbnailImage)],
            metadata: "thumbnails=\(thumbnailControllers.count) historyBackedEdit=\(historyEntryID != nil)"
        )
    }

    func refreshThumbnail(for entryID: String, image: NSImage) {
        for controller in thumbnailControllers where controller.historyEntryID == entryID {
            controller.updateImage(makeThumbnailDisplayImage(from: image, targetSize: controller.windowFrame.size))
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
        var memory = MemoryDiagnostics.makeScope(
            "ScreenshotOutput.performPostActions",
            images: [("image", image), ("annotationRawImage", annotationData?.rawImage)],
            metadata: "historyEntryID=\(historyEntryID ?? "nil") context=\(context)"
        )

        if actions.copyToClipboard {
            ImageEncoder.copyToClipboard(image)
            memory.step("copyToClipboard")
        }
        if actions.saveToFile && context != .manualSave {
            let showInFinder = UserDefaults.standard.bool(forKey: "screenshotShowInFinder")
            saveImageToDefaultDirectory(image, windowTitle: windowTitle, showInFinder: showInFinder)
            memory.step("saveToFile", metadata: "showInFinder=\(showInFinder)")
        }
        if actions.uploadAndCopyLink {
            uploadImage(image)
            memory.step("upload")
        }
        if actions.pinToScreen {
            showPin(image: image)
            memory.step("pin")
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
                    tool: .select,
                    historyEntryID: historyEntryID,
                    disableBeautify: true
                )
            }
            memory.step("openEditor")
        }
        if actions.showQuickAccessOverlay {
            showFloatingThumbnail(image: image, annotationData: annotationData, historyEntryID: historyEntryID)
            memory.step("showQuickAccessOverlay", metadata: "thumbnails=\(thumbnailControllers.count)")
        }

        SoundManager.shared.playCapture()
        memory.finish(
            "post actions complete",
            metadata: "copy=\(actions.copyToClipboard) save=\(actions.saveToFile) upload=\(actions.uploadAndCopyLink) pin=\(actions.pinToScreen) editor=\(actions.openEditor) thumbnail=\(actions.showQuickAccessOverlay)"
        )
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
        MemoryDiagnostics.snapshot(
            "ScreenshotOutput.showPin",
            images: [("image", image)],
            metadata: "pinsBefore=\(pinControllers.count)"
        )
        let pin = PinWindowController(image: image, at: origin)
        pin.delegate = self
        pin.show()
        pinControllers.append(pin)
        MemoryDiagnostics.snapshot("ScreenshotOutput.showPin.after", metadata: "pins=\(pinControllers.count)")
    }

    func pinWindowDidClose(_ controller: PinWindowController) {
        pinControllers.removeAll { $0 === controller }
    }

    private func screenDisplayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func saveAllThumbnailsToFolder() {
        let images = thumbnailControllers.compactMap { $0.loadExportImage() }
        guard !images.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder to save \(images.count) screenshot\(images.count == 1 ? "" : "s")"
        FilePanelPresenter.begin(panel) { [weak self] response in
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

    private func showUploadProgress(image: NSImage) {
        let toast = makeStatusToast()
        toast.show(status: L("Uploading..."))

        let provider = UploadProvider.current

        if let readinessError = provider.readinessErrorText {
            toast.showError(message: readinessError)
            return
        }

        let providerKey = provider.rawValue

        switch provider {
        case .gdrive:
            let progressHandler: (Double) -> Void = { fraction in
                toast.updateProgress(fraction)
            }
            GoogleDriveUploader.shared.uploadImage(image, progress: progressHandler) { result in
                switch result {
                case .success(let link):
                    PasteboardWriter.writeString(link)
                    UploadHistoryStore.append(link: link, provider: providerKey, thumbnail: image)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        case .s3:
            S3Uploader.shared.uploadImage(image, progress: nil) { result in
                switch result {
                case .success(let link):
                    PasteboardWriter.writeString(link)
                    UploadHistoryStore.append(link: link, provider: providerKey, thumbnail: image)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        case .cfimgbed:
            let progressHandler: (Double) -> Void = { fraction in
                toast.updateProgress(fraction)
            }
            CloudflareImgBedUploader.shared.uploadImage(image, progress: progressHandler) { result in
                switch result {
                case .success(let link):
                    PasteboardWriter.writeString(link)
                    UploadHistoryStore.append(link: link, provider: providerKey, thumbnail: image)
                    toast.showSuccess(link: link, deleteURL: "")
                case .failure(let error):
                    toast.showError(message: error.localizedDescription)
                }
            }
        case .imgbb:
            ImageUploader.upload(image: image) { result in
                switch result {
                case .success(let uploadResult):
                    PasteboardWriter.writeString(uploadResult.link)
                    UploadHistoryStore.append(
                        link: uploadResult.link,
                        deleteURL: uploadResult.deleteURL,
                        provider: providerKey,
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

    private func makeThumbnailDisplayImage(from image: NSImage, targetSize: NSSize) -> NSImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0,
              targetSize.width > 0, targetSize.height > 0 else {
            return image
        }

        let scale = min(
            max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height),
            1.0
        )
        let renderSize = NSSize(
            width: max(1, round(sourceSize.width * scale)),
            height: max(1, round(sourceSize.height * scale))
        )

        return NSImage(size: renderSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return true }
            context.imageInterpolation = .high
            image.draw(
                in: NSRect(origin: .zero, size: renderSize),
                from: NSRect(origin: .zero, size: sourceSize),
                operation: .copy,
                fraction: 1.0
            )
            return true
        }
    }

    private func loadImageFromHistory(entryID: String?) -> NSImage? {
        guard let entryID,
              let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }) else {
            return nil
        }
        return ScreenshotHistory.shared.loadImage(for: entry)
    }

    /// Copy image to clipboard from history entry, with fallback to provided image
    private func copyImageFromHistory(entryID: String?, fallbackImage: NSImage?) {
        if let image = loadImageFromHistory(entryID: entryID) {
            ImageEncoder.copyToClipboard(image)
        } else if let fallback = fallbackImage {
            ImageEncoder.copyToClipboard(fallback)
        }
    }

    /// Save image from history entry, with fallback to provided image
    private func saveImageFromHistory(entryID: String?, fallbackImage: NSImage?) {
        if let image = loadImageFromHistory(entryID: entryID) {
            saveImageToPreferredDirectory(image)
        } else if let fallback = fallbackImage {
            saveImageToPreferredDirectory(fallback)
        }
    }

    /// Pin image from history entry, with fallback to provided image
    private func pinImageFromHistory(entryID: String?, fallbackImage: NSImage?) {
        if let image = loadImageFromHistory(entryID: entryID) {
            showPin(image: image)
        } else if let fallback = fallbackImage {
            showPin(image: fallback)
        }
    }

    /// Upload image from history entry, with fallback to provided image
    private func uploadImageFromHistory(entryID: String?, fallbackImage: NSImage?) {
        if let image = loadImageFromHistory(entryID: entryID) {
            uploadImage(image)
        } else if let fallback = fallbackImage {
            uploadImage(fallback)
        }
    }

    /// Open editor from history entry, with fallback to provided image
    private func openEditorFromHistory(entryID: String?, fallbackImage: NSImage?) {
        MemoryDiagnostics.snapshot(
            "ScreenshotOutput.openEditorFromHistory.begin",
            images: [("fallbackImage", fallbackImage)],
            metadata: "entryID=\(entryID ?? "nil")"
        )
        if let entryID = entryID,
           let entry = ScreenshotHistory.shared.entries.first(where: { $0.id == entryID }),
           let rawImage = ScreenshotHistory.shared.loadRawImage(for: entry),
           let annotations = ScreenshotHistory.shared.loadAnnotations(for: entry) {
            DetachedEditorWindowController.open(
                image: rawImage,
                annotations: annotations,
                historyEntryID: entryID
            )
            MemoryDiagnostics.snapshot(
                "ScreenshotOutput.openEditorFromHistory.loadedEditable",
                images: [("rawImage", rawImage)],
                metadata: "entryID=\(entryID) annotations=\(annotations.count)"
            )
        } else if let historyImage = loadImageFromHistory(entryID: entryID) {
            DetachedEditorWindowController.open(
                image: historyImage,
                historyEntryID: entryID,
                disableBeautify: true
            )
            MemoryDiagnostics.snapshot(
                "ScreenshotOutput.openEditorFromHistory.loadedComposited",
                images: [("historyImage", historyImage)],
                metadata: "entryID=\(entryID ?? "nil")"
            )
        } else if let fallback = fallbackImage {
            DetachedEditorWindowController.open(
                image: fallback,
                historyEntryID: entryID,
                disableBeautify: true
            )
            MemoryDiagnostics.snapshot(
                "ScreenshotOutput.openEditorFromHistory.fallback",
                images: [("fallbackImage", fallback)],
                metadata: "entryID=\(entryID ?? "nil")"
            )
        }
    }
}
