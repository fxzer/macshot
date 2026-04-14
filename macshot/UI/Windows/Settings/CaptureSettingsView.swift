import SwiftUI

struct CaptureSettingsView: View {

    // Capture Options
    @AppStorage("playCopySound") private var playCopySound = true
    @AppStorage("rememberLastSelection") private var rememberLastSelection = false
    @AppStorage("rememberLastTool") private var rememberLastTool = true
    @AppStorage("snapGuidesEnabled") private var snapGuidesEnabled = true
    @AppStorage("selectionSizeSnapMode")
    private var selectionSizeSnapMode = SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue
    @AppStorage("captureCursor") private var captureCursor = false

    // Color Sampler
    @AppStorage("colorSamplerFormat") private var colorSamplerFormat = 0
    @AppStorage("colorSamplerGamut") private var colorSamplerGamut = 2  // Default to sRGB

    // Thumbnail
    @AppStorage("thumbnailAutoDismiss") private var thumbnailAutoDismiss: Int = 5
    @AppStorage("thumbnailStacking") private var thumbnailStacking = true
    @AppStorage("thumbnailScale") private var thumbnailScale = 1.0

    var body: some View {
        Form {
            // MARK: - Capture Options
            Section {
                Toggle(L("Play sound on capture"), isOn: $playCopySound)
                Toggle(L("Remember last selection area"), isOn: $rememberLastSelection)
                Toggle(L("Remember last selected tool"), isOn: $rememberLastTool)
                Picker(L("Selection size snapping"), selection: $selectionSizeSnapMode) {
                    Text(L("Off")).tag(SelectionSizeSnapMode.off.rawValue)
                    Text(L("Locked aspect ratio only")).tag(SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue)
                    Text(L("All selections")).tag(SelectionSizeSnapMode.allSelections.rawValue)
                }
                Toggle(L("Show snap alignment guides"), isOn: $snapGuidesEnabled)
                Toggle(L("Capture mouse cursor in screenshot"), isOn: $captureCursor)
            } header: {
                Text(L("Capture Options"))
            }

            // MARK: - Color Sampler
            Section {
                Picker(L("Color format"), selection: $colorSamplerFormat) {
                    Text("HEX").tag(0)
                    Text("RGB").tag(1)
                }
                Picker(L("Color space"), selection: $colorSamplerGamut) {
                    ForEach(ColorGamut.allCases, id: \.rawValue) { gamut in
                        Text(gamut.displayName).tag(gamut.rawValue)
                    }
                }
            } header: {
                Text(L("Color Sampler"))
            }

            // MARK: - Thumbnail
            Section {
                Picker(L("Auto-dismiss after"), selection: $thumbnailAutoDismiss) {
                    Text(L("Never")).tag(0)
                    Text("5 " + L("seconds")).tag(5)
                    Text("10 " + L("seconds")).tag(10)
                    Text("15 " + L("seconds")).tag(15)
                    Text("30 " + L("seconds")).tag(30)
                    Text("45 " + L("seconds")).tag(45)
                    Text("1 " + L("minute")).tag(60)
                    Text("2 " + L("minutes")).tag(120)
                    Text("5 " + L("minutes")).tag(300)
                    Text("10 " + L("minutes")).tag(600)
                }
                Picker(L("Multiple previews"), selection: $thumbnailStacking) {
                    Text(L("Stack (keep all)")).tag(true)
                    Text(L("Replace (show only latest)")).tag(false)
                }
                HStack {
                    Text(L("Preview size"))
                    Spacer()
                    Slider(value: $thumbnailScale, in: 0.5...2.0, step: 0.1)
                        .frame(width: 300)
                    Text(scalePercentString)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text(L("Thumbnail"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizePickerSelections)
    }

    private var scalePercentString: String {
        "\(Int(round(thumbnailScale * 100)))%"
    }

    private func normalizePickerSelections() {
        PostCaptureActionPreferences.migrateIfNeeded()
        thumbnailAutoDismiss = normalized(
            thumbnailAutoDismiss,
            allowed: [0, 5, 10, 15, 30, 45, 60, 120, 300, 600],
            fallback: 5
        )
    }

    private func normalized<T: Equatable>(_ value: T, allowed: [T], fallback: T) -> T {
        allowed.contains(value) ? value : fallback
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
