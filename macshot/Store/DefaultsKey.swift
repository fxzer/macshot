import Foundation

/// Centralized UserDefaults key registry.
///
/// Replaces scattered raw string literals (`forKey: "captureDelaySeconds"`, etc.)
/// so a typo can no longer silently select the wrong key. New code should add the
/// key here and reference `DefaultsKey.xxx`; existing call sites are being migrated
/// incrementally — the absence of a key here does not mean the key is unused.
///
/// Note: `@AppStorage("...")` in SwiftUI views requires a string literal at the
/// call site (the wrapper's key parameter is not a normal function argument), so
/// those declarations keep their literals. Only programmatic
/// `UserDefaults.standard.*forKey:` calls reference these constants.
enum DefaultsKey {
    // Delay / capture flow
    static let captureDelaySeconds = "captureDelaySeconds"

    // Upload
    static let uploadProvider = "uploadProvider"

    // Webcam (recording)
    static let recordWebcam = "recordWebcam"
    static let webcamPosition = "webcamPosition"
    static let webcamSize = "webcamSize"
    static let webcamShape = "webcamShape"
    static let selectedCameraDeviceUID = "selectedCameraDeviceUID"

    // Selection memory
    static let lastSelectionRect = "lastSelectionRect"
    static let lastSelectionScreenFrame = "lastSelectionScreenFrame"
}
