import SwiftUI

struct CaptureSettingsView: View {

    // Quick Actions
    @AppStorage("quickCaptureMode") private var quickCaptureMode = 1
    @AppStorage("quickCaptureOpenEditor") private var quickCaptureOpenEditor = false
    @AppStorage("ocrAction") private var ocrAction = 0

    // Capture Options
    @AppStorage("playCopySound") private var playCopySound = true
    @AppStorage("rememberLastSelection") private var rememberLastSelection = false
    @AppStorage("rememberLastTool") private var rememberLastTool = true
    @AppStorage("snapGuidesEnabled") private var snapGuidesEnabled = true
    @AppStorage("captureCursor") private var captureCursor = false
    @AppStorage("useWindowTitleInFilename") private var useWindowTitleInFilename = false

    // Thumbnail
    @AppStorage("showFloatingThumbnail") private var showFloatingThumbnail = true
    @AppStorage("thumbnailAutoDismiss") private var thumbnailAutoDismiss = 5
    @AppStorage("thumbnailStacking") private var thumbnailStacking = true
    @AppStorage("thumbnailScale") private var thumbnailScale = 1.0

    var body: some View {
        Form {
            // MARK: - Quick Actions
            Section {
                Picker(L("Enter / Quick Capture"), selection: $quickCaptureMode) {
                    Text(L("Save to file")).tag(0)
                    Text(L("Copy to clipboard")).tag(1)
                    Text(L("Save + copy to clipboard")).tag(2)
                    Text(L("Do nothing")).tag(3)
                }
                Toggle(L("Also open in Editor"), isOn: $quickCaptureOpenEditor)
                Picker(L("OCR Capture"), selection: $ocrAction) {
                    Text(L("Show window + copy to clipboard")).tag(0)
                    Text(L("Show window only")).tag(1)
                    Text(L("Copy to clipboard only")).tag(2)
                }
            } header: {
                Text(L("Quick Actions"))
            }

            // MARK: - Capture Options
            Section {
                Toggle(L("Play sound on capture"), isOn: $playCopySound)
                Toggle(L("Remember last selection area"), isOn: $rememberLastSelection)
                Toggle(L("Remember last selected tool"), isOn: $rememberLastTool)
                Toggle(L("Show snap alignment guides"), isOn: $snapGuidesEnabled)
                Toggle(L("Capture mouse cursor in screenshot"), isOn: $captureCursor)
                settingWithDescription(
                    title: L("Use window title in saved filename"),
                    description: L("When snapping to a window, its title is used in the filename."),
                    content: {
                        Toggle("", isOn: $useWindowTitleInFilename).labelsHidden()
                    }
                )
            } header: {
                Text(L("Capture Options"))
            }

            // MARK: - Thumbnail
            Section {
                Toggle(L("Show floating thumbnail after capture"), isOn: $showFloatingThumbnail)
                Stepper(value: $thumbnailAutoDismiss, in: 0...60) {
                    HStack {
                        Text(L("Dismiss after"))
                        Spacer()
                        Text("\(thumbnailAutoDismiss) \(L("seconds"))")
                            .foregroundColor(.secondary)
                    }
                }
                Picker(L("Multiple previews"), selection: $thumbnailStacking) {
                    Text(L("Stack (keep all)")).tag(true)
                    Text(L("Replace (show only latest)")).tag(false)
                }
                HStack {
                    Text(L("Preview size"))
                    Spacer()
                    Slider(value: $thumbnailScale, in: 0.5...2.0, step: 0.1)
                        .frame(width: 160)
                    Text(scalePercentString)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text(L("Thumbnail"))
            } footer: {
                Text(L("Auto-dismiss: 0 = never"))
            }
        }
        .formStyle(.grouped)
    }

    private var scalePercentString: String {
        "\(Int(round(thumbnailScale * 100)))%"
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
