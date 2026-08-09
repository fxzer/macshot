import Cocoa
import UniformTypeIdentifiers

@MainActor
final class AppRouteHandler: NSObject {

    struct ExternalActions {
        let captureArea: () -> Void
        let captureFullScreen: () -> Void
        let quickCapture: () -> Void
        let captureOCR: () -> Void
        let scrollCapture: () -> Void
        let showHistory: () -> Void
        let openSettings: () -> Void
    }

    private let actions: ExternalActions
    private let showError: (String) -> Void

    init(actions: ExternalActions, showError: @escaping (String) -> Void) {
        self.actions = actions
        self.showError = showError
    }

    @objc func openImageFromMenu() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic, .webP, .image]
        panel.message = "Choose an image to open in macshot editor"

        FilePanelPresenter.begin(panel) { [weak self] response in
            guard let self = self, response == .OK else { return }
            for url in panel.urls {
                self.openImageFile(url: url)
            }
        }
    }

    @objc func openImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard),
              image.isValid,
              image.size.width > 0,
              image.size.height > 0 else {
            let alert = NSAlert()
            alert.messageText = L("No Image on Clipboard")
            alert.informativeText = L("Copy an image to the clipboard first, then try again.")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
            return
        }

        DetachedEditorWindowController.open(image: image)
    }

    func handleOpen(urls: [URL]) {
        for url in urls {
            if url.scheme?.lowercased() == AppExternalAction.scheme {
                switch AppExternalAction.parse(url: url) {
                case .success(let action):
                    handleExternalAction(action)
                case .failure(let error):
                    showError(error.localizedDescription)
                }
                continue
            }

            guard ImageFileLoader.isSupportedImageURL(url) else { continue }
            openImageFile(url: url)
        }
    }

    private func openImageFile(url: URL) {
        let fileURL = url.standardizedFileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ImageFileLoader.loadImage(from: fileURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let image):
                    DetachedEditorWindowController.open(image: image)
                case .failure(let error):
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func handleExternalAction(_ action: AppExternalAction) {
        switch action {
        case .captureArea:
            actions.captureArea()
        case .captureFullScreen:
            actions.captureFullScreen()
        case .quickCapture:
            actions.quickCapture()
        case .captureOCR:
            actions.captureOCR()
        case .scrollCapture:
            actions.scrollCapture()
        case .history:
            actions.showHistory()
        case .settings:
            actions.openSettings()
        case .openImage(let fileURL):
            openImageFile(url: fileURL)
        }
    }
}
