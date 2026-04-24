import Cocoa

extension OverlayView {
    func showRecordingSettingsPopover(anchorView: NSView?) {
        let form = OverlayPopoverFormView(width: 240)
        let fpsOptions = [15, 30, 60, 120]
        form.addRow(
            L("FPS:"),
            control: makeOverlayPopup(
                fpsOptions.map(String.init),
                selected: fpsOptions.firstIndex { effectiveRecordingFPS <= $0 } ?? fpsOptions.count - 1
            ) { [weak self] index in
                self?.sessionRecordingFPS = fpsOptions[index]
            }
        )

        let delayOptions = [0, 3, 5, 10, 30]
        let delayTitles = delayOptions.map { $0 == 0 ? L("None") : String(format: L("%d seconds"), $0) }
        form.addRow(
            L("Delay:"),
            control: makeOverlayPopup(
                delayTitles,
                selected: delayOptions.firstIndex(of: effectiveRecordingDelay) ?? 0
            ) { [weak self] index in
                self?.sessionRecordingDelay = delayOptions[index]
            }
        )

        form.addRow(
            L("Controls:"),
            control: makeOverlayPopup(
                [L("Floating HUD"), L("Menu Bar")],
                selected: effectiveRecordingControlsMode == .menuBar ? 1 : 0
            ) { [weak self] index in
                self?.sessionRecordingControlsMode = [
                    RecordingControlsMode.floatingHUD.rawValue,
                    RecordingControlsMode.menuBar.rawValue,
                ][index]
            }
        )

        if UserDefaults.standard.bool(forKey: "recordWebcam") {
            form.addSeparator()

            let positions = ["bottomLeft", "bottomRight", "topLeft", "topRight"]
            let positionIndex = positions.firstIndex(of: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? 1
            form.addRow(
                L("Cam pos:"),
                control: makeOverlaySegmented(["↙", "↘", "↖", "↗"], selected: positionIndex) { [weak self] index in
                    UserDefaults.standard.set(positions[index], forKey: "webcamPosition")
                    self?.updateWebcamSetupPreview()
                }
            )

            let sizes = ["small", "medium", "large"]
            let sizeIndex = sizes.firstIndex(of: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? 1
            form.addRow(
                L("Cam size:"),
                control: makeOverlaySegmented(["S", "M", "L"], selected: sizeIndex) { [weak self] index in
                    UserDefaults.standard.set(sizes[index], forKey: "webcamSize")
                    self?.updateWebcamSetupPreview()
                }
            )

            let shapes = ["circle", "roundedRect"]
            let shapeIndex = (UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") == "roundedRect" ? 1 : 0
            form.addRow(
                L("Cam shape:"),
                control: makeOverlaySegmented(["●", "▢"], selected: shapeIndex) { [weak self] index in
                    UserDefaults.standard.set(shapes[index], forKey: "webcamShape")
                    self?.updateWebcamSetupPreview()
                }
            )
        }

        form.finish()

        presentOverlayPopover(
            form,
            size: form.preferredSize,
            type: .recordingSettings,
            edge: .maxY,
            anchorView: anchorView,
            fallbackPoint: NSPoint(x: bounds.midX, y: bounds.midY)
        )
    }
}
