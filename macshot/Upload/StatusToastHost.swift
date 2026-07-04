import Foundation

/// Provides the shared `makeStatusToast()` helper for coordinators that own an
/// `UploadToastController`.
///
/// Both `RecordingFlowCoordinator` and `ScreenshotOutputCoordinator` previously
/// declared byte-identical `makeStatusToast()` methods (and inline toast-setup
/// blocks that lacked the `weak toast` identity check). Conforming to this
/// protocol dedupes the helper and enforces the safer identity-check pattern.
@MainActor
protocol StatusToastHost: AnyObject {
    var uploadToastController: UploadToastController? { get set }
}

@MainActor
extension StatusToastHost {
    /// Dismiss any existing toast, create a fresh one, wire its `onDismiss` to nil
    /// out the stored reference only if it still points at the same instance (the
    /// identity check prevents a late `onDismiss` from a superseded toast nil-ing
    /// out the current controller).
    func makeStatusToast() -> UploadToastController {
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
}
