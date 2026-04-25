//
//  OverlayView+AspectRatio.swift
//  macshot
//
//  Aspect-ratio helpers and screen-state helpers for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Aspect Ratio Lock Helpers

    func aspectRatioShortcutItems(includeInvert: Bool) -> [(key: String, label: String)] {
        var items: [(key: String, label: String)] = []

        if includeInvert {
            items.append((AspectRatioShortcutManager.invertKeyValue.uppercased(), L("Invert")))
        }

        items.append((AspectRatioShortcutManager.cancelKeyValue.uppercased(), L("Free")))

        for ratio in AspectRatioPreferences.allRatios {
            let key = AspectRatioShortcutManager.key(for: ratio.id).uppercased()
            guard !key.isEmpty else { continue }
            items.append((key, ratio.displayName))
        }

        return items
    }

    func toggleAspectRatioLock(_ lock: AspectRatioLock) {
        if aspectRatioLock == lock || aspectRatioLock.sharesShortcutGroup(with: lock) {
            aspectRatioLock = .none
            showStateHint(
                message: L("Aspect ratio lock") + " ",
                statusText: L("Status disabled"),
                state: .disabled
            )
        } else {
            aspectRatioLock = lock
            showStateHint(
                message: L("Aspect ratio lock") + " (" + lock.displayName + ") ",
                statusText: L("Status enabled"),
                state: .enabled
            )
        }
        needsDisplay = true
    }

    func getAspectRatioHintState(completion: (CGFloat, Bool, AspectRatioLock) -> Void) {
        completion(0.0, false, aspectRatioLock)
    }

    func syncAspectRatioHint(opacity: CGFloat, isCancelling: Bool, lock: AspectRatioLock) {
        aspectRatioLock = lock
        needsDisplay = true
    }

    /// Check if the mouse pointer is currently on this overlay's screen
    func isMouseOnCurrentScreen() -> Bool {
        guard let window = self.window else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = window.screen?.frame ?? .zero
        return screenFrame.contains(mouseLocation)
    }
}
