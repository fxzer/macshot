import Cocoa

enum SoundSettings {
    static let captureEnabled = "sound.captureEnabled"
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private let captureSound: NSSound?

    private init() {
        captureSound = NSSound(
            contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
            byReference: true
        ) ?? NSSound(named: "Tink")
    }

    func playCapture() {
        guard UserDefaults.standard.bool(forKey: SoundSettings.captureEnabled) else { return }
        captureSound?.stop()
        captureSound?.play()
    }

    /// Prime the audio system to avoid delay on first use.
    func primeAudio() {
        captureSound?.volume = 0
        captureSound?.play()
        captureSound?.stop()
        captureSound?.volume = 1
    }
}
