//
//  OverlayView+Permissions.swift
//  macshot
//
//  Permission handling for camera, microphone, and input monitoring.
//

import AppKit
import AVFoundation

extension OverlayView {

    // MARK: - Permission State Properties

    var micLevelEngine: AVAudioEngine? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.micLevelEngine) as? AVAudioEngine }
        set { objc_setAssociatedObject(self, &AssociatedKeys.micLevelEngine, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var micLevelTimer: Timer? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.micLevelTimer) as? Timer }
        set { objc_setAssociatedObject(self, &AssociatedKeys.micLevelTimer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var webcamSetupPreview: WebcamOverlay? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.webcamSetupPreview) as? WebcamOverlay }
        set { objc_setAssociatedObject(self, &AssociatedKeys.webcamSetupPreview, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - Recording Permission Pre-checks

    func preCheckRecordingPermissions() {
        checkMicPermission { [weak self] in
            self?.checkCameraPermission()
        }
    }

    private func checkMicPermission(then next: @escaping () -> Void) {
        guard UserDefaults.standard.bool(forKey: "recordMicAudio") else { next(); return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            startMicLevelMonitor()
            next()
        } else if status == .notDetermined {
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        self?.startMicLevelMonitor()
                    } else {
                        UserDefaults.standard.set(false, forKey: "recordMicAudio")
                        self?.rebuildToolbarLayout()
                    }
                    next()
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: "recordMicAudio")
            rebuildToolbarLayout()
            showMicPermissionAlert()
            next()
        }
    }

    private func checkCameraPermission() {
        guard UserDefaults.standard.bool(forKey: "recordWebcam") else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            showWebcamSetupPreview()
        } else if status == .notDetermined {
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        self?.showWebcamSetupPreview()
                    } else {
                        UserDefaults.standard.set(false, forKey: "recordWebcam")
                        self?.rebuildToolbarLayout()
                    }
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: "recordWebcam")
            rebuildToolbarLayout()
        }
    }

    // MARK: - Webcam Toggle & Device Menu

    func toggleWebcamOverlay() {
        let current = UserDefaults.standard.bool(forKey: "recordWebcam")
        if current {
            UserDefaults.standard.set(false, forKey: "recordWebcam")
            dismissWebcamSetupPreview()
            rebuildToolbarLayout()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            UserDefaults.standard.set(true, forKey: "recordWebcam")
            rebuildToolbarLayout()
            showWebcamSetupPreview()
        case .notDetermined:
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        UserDefaults.standard.set(true, forKey: "recordWebcam")
                        self?.showWebcamSetupPreview()
                    }
                    self?.rebuildToolbarLayout()
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert()
        @unknown default:
            break
        }
    }

    private func showWebcamSetupPreview() {
        guard webcamSetupPreview == nil else { return }
        guard let screen = window?.screen ?? NSScreen.main else { return }

        let overlay = WebcamOverlay(screen: screen)
        let position = WebcamPosition(rawValue: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? .bottomRight
        let size = WebcamSize(rawValue: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? .medium
        let shape = WebcamShape(rawValue: UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") ?? .circle

        let screenOrigin = screen.frame.origin
        let screenRect = NSRect(
            x: selectionRect.origin.x + screenOrigin.x,
            y: selectionRect.origin.y + screenOrigin.y,
            width: selectionRect.width,
            height: selectionRect.height)

        overlay.configure(position: position, size: size, shape: shape, recordingRect: screenRect)
        overlay.startPreview(deviceUID: UserDefaults.standard.string(forKey: "selectedCameraDeviceUID"))
        overlay.setDraggable(true)
        overlay.orderFront(nil)
        webcamSetupPreview = overlay
    }

    func dismissWebcamSetupPreview() {
        webcamSetupPreview?.stopPreview()
        webcamSetupPreview?.close()
        webcamSetupPreview = nil
    }

    func detachWebcamSetupPreview() -> WebcamOverlay? {
        let overlay = webcamSetupPreview
        webcamSetupPreview = nil
        return overlay
    }

    func updateWebcamSetupPreview() {
        guard webcamSetupPreview != nil else { return }
        dismissWebcamSetupPreview()
        if UserDefaults.standard.bool(forKey: "recordWebcam") {
            showWebcamSetupPreview()
        }
    }

    func repositionWebcamSetupPreview() {
        guard let overlay = webcamSetupPreview,
              let screen = window?.screen ?? NSScreen.main else { return }
        let position = WebcamPosition(rawValue: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? .bottomRight
        let size = WebcamSize(rawValue: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? .medium
        let shape = WebcamShape(rawValue: UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") ?? .circle
        let screenOrigin = screen.frame.origin
        let screenRect = NSRect(
            x: selectionRect.origin.x + screenOrigin.x,
            y: selectionRect.origin.y + screenOrigin.y,
            width: selectionRect.width,
            height: selectionRect.height)
        overlay.configure(position: position, size: size, shape: shape, recordingRect: screenRect)
    }

    private func showCameraPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L("Camera Access Required")
        alert.informativeText = L("macshot needs camera permission for the webcam overlay. Open System Settings to grant access.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func showWebcamDeviceMenu(anchorView: NSView) {
        let menu = NSMenu()
        let savedUID = UserDefaults.standard.string(forKey: "selectedCameraDeviceUID")
        let webcamOn = UserDefaults.standard.bool(forKey: "recordWebcam")

        let noneItem = NSMenuItem(title: L("None"), action: #selector(webcamMenuNone), keyEquivalent: "")
        noneItem.target = self
        if !webcamOn { noneItem.state = .on }
        menu.addItem(noneItem)
        menu.addItem(NSMenuItem.separator())

        let devices = WebcamOverlay.availableCameras
        for device in devices {
            let item = NSMenuItem(title: device.localizedName, action: #selector(webcamMenuSelectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if webcamOn && (savedUID == device.uniqueID || (savedUID == nil && device == AVCaptureDevice.default(for: .video))) {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
    }

    @objc private func webcamMenuNone() {
        UserDefaults.standard.set(false, forKey: "recordWebcam")
        dismissWebcamSetupPreview()
        rebuildToolbarLayout()
    }

    @objc private func webcamMenuSelectDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: "selectedCameraDeviceUID")
        UserDefaults.standard.set(true, forKey: "recordWebcam")
        rebuildToolbarLayout()
        updateWebcamSetupPreview()
    }

    // MARK: - Mic Permission & Toggle

    func toggleMicAudio() {
        let current = UserDefaults.standard.bool(forKey: "recordMicAudio")
        if current {
            UserDefaults.standard.set(false, forKey: "recordMicAudio")
            stopMicLevelMonitor()
            rebuildToolbarLayout()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            UserDefaults.standard.set(true, forKey: "recordMicAudio")
            rebuildToolbarLayout()
            startMicLevelMonitor()
        case .notDetermined:
            let savedLevel = window?.level
            window?.level = .normal
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if let saved = savedLevel { self?.window?.level = saved }
                    if granted {
                        UserDefaults.standard.set(true, forKey: "recordMicAudio")
                        self?.startMicLevelMonitor()
                    }
                    self?.rebuildToolbarLayout()
                }
            }
        case .denied, .restricted:
            showMicPermissionAlert()
        @unknown default:
            break
        }
    }

    private func showMicPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = L("Microphone Access Required")
        alert.informativeText = L("macshot needs microphone permission to record voice audio. Open System Settings to grant access.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Mic Level Monitor

    func startMicLevelMonitor() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        stopMicLevelMonitor()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else { return }

        var peakLevel: Float = 0
        let lock = NSLock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            var peak: Float = 0
            for i in 0..<frames {
                let val = abs(channelData[0][i])
                if val > peak { peak = val }
            }
            lock.lock()
            peakLevel = peak
            lock.unlock()
        }

        do {
            try engine.start()
        } catch {
            return
        }
        micLevelEngine = engine

        var displayLevel: Float = 0
        micLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            lock.lock()
            let level = peakLevel
            peakLevel = 0
            lock.unlock()
            displayLevel = level > displayLevel ? level : displayLevel * 0.8 + level * 0.2
            self?.setMicButtonLevel(displayLevel)
        }
    }

    func stopMicLevelMonitor() {
        micLevelTimer?.invalidate()
        micLevelTimer = nil
        micLevelEngine?.inputNode.removeTap(onBus: 0)
        micLevelEngine?.stop()
        micLevelEngine = nil
        setMicButtonLevel(0)
    }

    private func setMicButtonLevel(_ level: Float) {
        let strips: [ToolbarStripView?] = [bottomStripView, rightStripView]
        for strip in strips {
            if let btn = strip?.buttonViews.first(where: {
                if case .micAudio = $0.action { return true }; return false
            }) {
                btn.micLevel = level
            }
        }
    }

    // MARK: - Keystroke Overlay / Input Monitoring

    func toggleKeystrokeOverlay() {
        let current = UserDefaults.standard.bool(forKey: "recordKeystroke")
        if current {
            UserDefaults.standard.set(false, forKey: "recordKeystroke")
            rebuildToolbarLayout()
            return
        }
        if KeystrokeOverlay.hasInputMonitoringPermission {
            UserDefaults.standard.set(true, forKey: "recordKeystroke")
            rebuildToolbarLayout()
        } else {
            overlayDelegate?.overlayViewDidRequestInputMonitoringPermission()
        }
    }

    // MARK: - Cleanup

    func resetPermissionState() {
        micLevelTimer?.invalidate()
        micLevelTimer = nil
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    static var micLevelEngine = "micLevelEngine"
    static var micLevelTimer = "micLevelTimer"
    static var webcamSetupPreview = "webcamSetupPreview"
}
