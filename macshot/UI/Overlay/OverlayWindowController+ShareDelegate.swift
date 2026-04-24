import Cocoa

/// Retained delegate for NSSharingServicePicker — dismisses overlay only when user picks a service.
class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let onPick: () -> Void
    let onDismiss: () -> Void
    init(onPick: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onPick = onPick
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        if service != nil {
            onPick()
        } else {
            onDismiss()
        }
    }
}
