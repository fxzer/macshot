import SwiftUI

struct RecordingSettingsView: View {

    // Output
    @AppStorage("recordingFPS") private var recordingFPS = 30
    @State private var recSavePath: String = SaveDirectoryAccess.recordingDisplayPath

    // Behavior
    @AppStorage("recordingOnStop") private var recordingOnStop = "editor"
    @AppStorage("hideRecordingHUD") private var hideRecordingHUD = false

    // Webcam
    @AppStorage("webcamPosition") private var webcamPosition = "bottomRight"
    @AppStorage("webcamSize") private var webcamSize = "medium"
    @AppStorage("webcamShape") private var webcamShape = "circle"

    // Scroll Capture
    @AppStorage("scrollAutoScrollEnabled") private var scrollAutoScroll = false
    @AppStorage("scrollAutoScrollSpeed") private var scrollSpeed = 3
    @AppStorage("scrollMaxHeight") private var scrollMaxHeight = 30000
    @AppStorage("scrollFrozenDetection") private var scrollFrozenDetection = true

    var body: some View {
        Form {
            // MARK: - Output
            Section {
                Picker(L("Frame rate"), selection: $recordingFPS) {
                    Text(L("15 fps")).tag(15)
                    Text(L("24 fps")).tag(24)
                    Text(L("30 fps")).tag(30)
                    Text(L("60 fps")).tag(60)
                    Text(L("120 fps")).tag(120)
                }
                HStack {
                    Text(L("Save folder"))
                    Spacer()
                    Text(recSavePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L("Browse…")) {
                        browseRecSavePath()
                    }
                    Button(L("Clear")) {
                        SaveDirectoryAccess.clearRecordingDirectory()
                        recSavePath = SaveDirectoryAccess.recordingDisplayPath
                    }
                }
            } header: {
                Text(L("Output"))
            }

            // MARK: - Behavior
            Section {
                Picker(L("When done"), selection: $recordingOnStop) {
                    Text(L("Open editor")).tag("editor")
                    Text(L("Show in Finder")).tag("finder")
                    Text(L("Copy to clipboard")).tag("clipboard")
                }
                settingWithDescription(
                    title: L("Hide recording controls"),
                    description: L("Stop recording from the menu bar icon instead.")
                ) {
                    Toggle("", isOn: $hideRecordingHUD).labelsHidden()
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
                HStack {
                    Text("\(scrollMaxHeight) px")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Stepper(value: $scrollMaxHeight, in: 0...100000, step: 5000) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
                Toggle(L("Detect fixed/sticky headers"), isOn: $scrollFrozenDetection)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Scroll Capture"))
                    Text(L("Max height: 0 = unlimited"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func browseRecSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveDirectoryAccess.recordingDirectoryHint()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            SaveDirectoryAccess.saveRecordingDirectory(url: url)
            recSavePath = url.path
        }
    }

    @ViewBuilder
    private func settingWithDescription<Content: View>(title: String, description: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            content()
        }
    }
}
