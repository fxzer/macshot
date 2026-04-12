import SwiftUI

enum RecordingControlsMode: String {
    case floatingHUD = "floatingHUD"
    case menuBar = "menuBar"

    static func resolved(raw: String?) -> RecordingControlsMode? {
        guard let raw else { return nil }
        return RecordingControlsMode(rawValue: raw)
    }

    static var current: RecordingControlsMode {
        if let stored = resolved(raw: UserDefaults.standard.string(forKey: "recordingControlsMode")) {
            return stored
        }
        return UserDefaults.standard.bool(forKey: "hideRecordingHUD") ? .menuBar : .floatingHUD
    }
}

struct RecordingSettingsView: View {

    // Quality
    @AppStorage("recordingFPS") private var recordingFPS = 30

    // Behavior
    @AppStorage("recordingOnStop") private var recordingOnStop = "editor"
    @AppStorage("recordingControlsMode") private var recordingControlsModeRaw = ""

    // Webcam
    @AppStorage("webcamPosition") private var webcamPosition = "bottomRight"
    @AppStorage("webcamSize") private var webcamSize = "medium"
    @AppStorage("webcamShape") private var webcamShape = "circle"

    // Scroll Capture
    @AppStorage("scrollAutoScrollEnabled") private var scrollAutoScroll = false
    @AppStorage("scrollAutoScrollSpeed") private var scrollSpeed: Int = 3
    @AppStorage("scrollMaxHeight") private var scrollMaxHeight: Int = 30000
    @AppStorage("scrollFrozenDetection") private var scrollFrozenDetection = true

    var body: some View {
        Form {
            // MARK: - Quality
            Section {
                Picker(L("Frame rate"), selection: $recordingFPS) {
                    Text(L("15 fps")).tag(15)
                    Text(L("24 fps")).tag(24)
                    Text(L("30 fps")).tag(30)
                    Text(L("60 fps")).tag(60)
                    Text(L("120 fps")).tag(120)
                }
            } header: {
                Text(L("Quality"))
            }

            // MARK: - Behavior
            Section {
                Picker(L("When done"), selection: $recordingOnStop) {
                    Text(L("Open editor")).tag("editor")
                    Text(L("Show in Finder")).tag("finder")
                    Text(L("Copy to clipboard")).tag("clipboard")
                }
                Picker(L("Recording controls"), selection: $recordingControlsModeRaw) {
                    Text(L("Floating HUD")).tag(RecordingControlsMode.floatingHUD.rawValue)
                    Text(L("Menu Bar")).tag(RecordingControlsMode.menuBar.rawValue)
                }
                .onChange(of: recordingControlsModeRaw) { newValue in
                    syncLegacyControlsMode(rawValue: newValue)
                }
            } header: {
                Text(L("Behavior"))
            }

            // MARK: - Webcam
            Section {
                Picker(L("Position"), selection: $webcamPosition) {
                    Text(L("Bottom Right")).tag("bottomRight")
                    Text(L("Bottom Left")).tag("bottomLeft")
                    Text(L("Top Right")).tag("topRight")
                    Text(L("Top Left")).tag("topLeft")
                }
                Picker(L("Size"), selection: $webcamSize) {
                    Text(L("Small")).tag("small")
                    Text(L("Medium")).tag("medium")
                    Text(L("Large")).tag("large")
                }
                Picker(L("Shape"), selection: $webcamShape) {
                    Text(L("Circle")).tag("circle")
                    Text(L("Rounded Rectangle")).tag("roundedRect")
                }
            } header: {
                Text(L("Webcam"))
            }

            // MARK: - Scroll Capture
            Section {
                Toggle(L("Auto-scroll (sends synthetic scroll events)"), isOn: $scrollAutoScroll)
                if scrollAutoScroll {
                    Picker(L("Scroll speed"), selection: $scrollSpeed) {
                        Text(L("Slow")).tag(1)
                        Text(L("Medium")).tag(2)
                        Text(L("Fast")).tag(3)
                        Text(L("Very fast")).tag(4)
                    }
                }
                Picker(L("Max height"), selection: $scrollMaxHeight) {
                    Text(L("Unlimited")).tag(0)
                    Text("10,000 px").tag(10000)
                    Text("30,000 px").tag(30000)
                    Text("50,000 px").tag(50000)
                    Text("100,000 px").tag(100000)
                }
                Toggle(L("Detect fixed/sticky headers"), isOn: $scrollFrozenDetection)
            } header: {
                Text(L("Scroll Capture"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizePickerSelections)
    }

    private func normalizePickerSelections() {
        recordingFPS = normalized(recordingFPS, allowed: [15, 24, 30, 60, 120], fallback: 30)
        recordingOnStop = normalized(
            recordingOnStop,
            allowed: ["editor", "finder", "clipboard"],
            fallback: "editor"
        )
        webcamPosition = normalized(
            webcamPosition,
            allowed: ["bottomRight", "bottomLeft", "topRight", "topLeft"],
            fallback: "bottomRight"
        )
        webcamSize = normalized(webcamSize, allowed: ["small", "medium", "large"], fallback: "medium")
        webcamShape = normalized(webcamShape, allowed: ["circle", "roundedRect"], fallback: "circle")
        scrollSpeed = normalized(scrollSpeed, allowed: [1, 2, 3, 4], fallback: 3)
        scrollMaxHeight = normalized(
            scrollMaxHeight,
            allowed: [0, 10000, 30000, 50000, 100000],
            fallback: 30000
        )

        let normalizedControlsMode = RecordingControlsMode.resolved(raw: recordingControlsModeRaw) ?? .current
        recordingControlsModeRaw = normalizedControlsMode.rawValue
        syncLegacyControlsMode(rawValue: normalizedControlsMode.rawValue)
    }

    private func normalized<T: Equatable>(_ value: T, allowed: [T], fallback: T) -> T {
        allowed.contains(value) ? value : fallback
    }

    private func syncLegacyControlsMode(rawValue: String) {
        let resolved = RecordingControlsMode.resolved(raw: rawValue) ?? .current
        UserDefaults.standard.set(resolved == .menuBar, forKey: "hideRecordingHUD")
    }
}
