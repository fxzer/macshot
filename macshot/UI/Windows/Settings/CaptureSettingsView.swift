import SwiftUI

struct CaptureSettingsView: View {

    // Capture Options
    @AppStorage("rememberLastSelection") private var rememberLastSelection = false
    @AppStorage("rememberLastTool") private var rememberLastTool = true
    @AppStorage("snapGuidesEnabled") private var snapGuidesEnabled = true
    @AppStorage("selectionSizeSnapMode")
    private var selectionSizeSnapMode = SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue
    @AppStorage("captureCursor") private var captureCursor = false

    // Image Output
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("imageQuality") private var imageQuality = 0.85
    @AppStorage("downscaleRetina") private var downscaleRetina = false
    @AppStorage("embedColorProfile") private var embedColorProfile = true
    @AppStorage("historySize") private var historySize = 10

    // Color Sampler
    @AppStorage("colorSamplerFormat") private var colorSamplerFormat = 0
    @AppStorage("colorSamplerGamut") private var colorSamplerGamut = 2  // Default to sRGB

    var body: some View {
        Form {
            // MARK: - Capture Settings
            Section {
                settingWithDescription(
                    title: L("Remember last selection area"),
                    description: L("Tip: Press ` to temporarily remember area")
                ) {
                    Toggle("", isOn: $rememberLastSelection).labelsHidden()
                }
                Toggle(L("Remember last selected tool"), isOn: $rememberLastTool)
                Picker(L("Selection size snapping"), selection: $selectionSizeSnapMode) {
                    Text(L("Off")).tag(SelectionSizeSnapMode.off.rawValue)
                    Text(L("Locked aspect ratio only")).tag(SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue)
                    Text(L("All selections")).tag(SelectionSizeSnapMode.allSelections.rawValue)
                }
                Toggle(L("Show snap alignment guides"), isOn: $snapGuidesEnabled)
                Toggle(L("Capture mouse cursor in screenshot"), isOn: $captureCursor)
            } header: {
                Text(L("Capture Settings"))
            }

            // MARK: - Image Output
            Section {
                Picker(L("Image format"), selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("HEIC").tag("heic")
                    Text("WebP").tag("webp")
                }
                if imageFormat == "jpeg" || imageFormat == "heic" || imageFormat == "webp" {
                    HStack {
                        Text(L("Quality"))
                        Slider(value: $imageQuality, in: 0.1...1.0)
                        Text(qualityPercentString)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                settingWithDescription(
                    title: L("Save at standard resolution (1x)"),
                    description: L("Halves dimensions on Retina displays, ~4x smaller files")
                ) {
                    Toggle("", isOn: $downscaleRetina).labelsHidden()
                }
                settingWithDescription(
                    title: L("Embed sRGB color profile"),
                    description: L("Ensures consistent colors across different displays")
                ) {
                    Toggle("", isOn: $embedColorProfile).labelsHidden()
                }
                Picker(L("History size"), selection: $historySize) {
                    Text(L("Unlimited")).tag(999)
                    Text("10").tag(10)
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .onChange(of: historySize) { _ in
                    ScreenshotHistory.shared.pruneToMax()
                }
            } header: {
                Text(L("Image Output"))
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
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizePickerSelections)
    }

    private func normalizePickerSelections() {
        PostCaptureActionPreferences.migrateIfNeeded()
        imageFormat = normalized(imageFormat, allowed: ["png", "jpeg", "heic", "webp"], fallback: "png")
        historySize = normalized(historySize, allowed: [999, 10, 25, 50, 100], fallback: 10)
    }

    private func normalized<T: Equatable>(_ value: T, allowed: [T], fallback: T) -> T {
        allowed.contains(value) ? value : fallback
    }

    private var qualityPercentString: String {
        "\(Int(round(imageQuality * 100)))%"
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
