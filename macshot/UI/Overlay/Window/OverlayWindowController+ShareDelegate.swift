import Cocoa

/// Retained delegate for NSSharingServicePicker — dismisses overlay only when user picks a service.
@MainActor
class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    let onPick: (NSSharingService) -> Void
    let onDismiss: () -> Void
    let onServiceWillShare: (() -> Void)?
    let onServiceDidShare: (() -> Void)?
    let onServiceDidFail: ((Error?) -> Void)?

    init(
        onPick: @escaping (NSSharingService) -> Void,
        onDismiss: @escaping () -> Void,
        onServiceWillShare: (() -> Void)? = nil,
        onServiceDidShare: (() -> Void)? = nil,
        onServiceDidFail: ((Error?) -> Void)? = nil
    ) {
        self.onPick = onPick
        self.onDismiss = onDismiss
        self.onServiceWillShare = onServiceWillShare
        self.onServiceDidShare = onServiceDidShare
        self.onServiceDidFail = onServiceDidFail
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        if let service = service {
            onPick(service)
        } else {
            onDismiss()
        }
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> NSSharingServiceDelegate? {
        return self
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        onServiceWillShare?()
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        onServiceDidShare?()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        onServiceDidFail?(error)
    }
}
