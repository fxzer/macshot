//
//  OverlayView+SelectionMemory.swift
//  macshot
//
//  Remember-last-selection helpers for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Remember Last Selection

    /// Toggle the persistent "remember last selection area" preference.
    func toggleRememberLastSelection() {
        let defaults = UserDefaults.standard
        let newState = !defaults.bool(forKey: "rememberLastSelection")
        defaults.set(newState, forKey: "rememberLastSelection")

        defaults.removeObject(forKey: "tempRememberSelection")
        defaults.removeObject(forKey: "tempRememberSelectionRect")
        defaults.removeObject(forKey: "tempRememberSelectionScreenFrame")

        if newState {
            if state == .selected && selectionRect.width > 1 && selectionRect.height > 1 {
                showOverlayHint(L("Current selection remembered"))
            } else {
                showStateHint(
                    message: L("Remember last selection area") + " ",
                    statusText: L("Status enabled"),
                    state: .enabled
                )
            }
        } else {
            if state == .selected {
                clearSelection()
            }
            showStateHint(
                message: L("Remember last selection area") + " ",
                statusText: L("Status disabled"),
                state: .disabled
            )
        }
        needsDisplay = true
    }
}
