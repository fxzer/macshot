import SwiftUI

struct CaptureSettingsView: View {

    // Capture Options
    @AppStorage("rememberLastSelection") private var rememberLastSelection = false
    @AppStorage("rememberLastTool") private var rememberLastTool = true
    @AppStorage("snapGuidesEnabled") private var snapGuidesEnabled = true
    @AppStorage("selectionSizeSnapMode")
    private var selectionSizeSnapMode = SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue

    // Image Output
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("imageQuality") private var imageQuality = 0.85
    @AppStorage("downscaleRetina") private var downscaleRetina = false
    @AppStorage("embedColorProfile") private var embedColorProfile = true
    @AppStorage("historySize") private var historySize = 10

    // Color Sampler
    @AppStorage("colorSamplerFormat") private var colorSamplerFormat = 0
    @AppStorage("colorSamplerGamut") private var colorSamplerGamut = 2  // Default to sRGB

    // Scroll Capture
    @AppStorage("scrollAutoScrollEnabled") private var scrollAutoScroll = false
    @AppStorage("scrollAutoScrollSpeed") private var scrollSpeed: Int = 3
    @AppStorage("scrollMaxHeight") private var scrollMaxHeight: Int = 30000
    @AppStorage("scrollFrozenDetection") private var scrollFrozenDetection = true

    var body: some View {
        Form {
            // MARK: - Capture Settings
            Section {
                settingWithDescription(
                    title: L("Remember last selection area"),
                    description: L("Tip: Press ` during capture to toggle this")
                ) {
                    Toggle("", isOn: $rememberLastSelection).labelsHidden()
                }
                Toggle(L("Remember last selected tool"), isOn: $rememberLastTool)
                settingWithDescription(
                    title: L("Selection size snapping"),
                    description: L("Snap selection edges to 50/100px multiples when resizing")
                ) {
                    Picker("", selection: $selectionSizeSnapMode) {
                        Text(L("Off")).tag(SelectionSizeSnapMode.off.rawValue)
                        Text(L("Locked aspect ratio only")).tag(SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue)
                        Text(L("All selections")).tag(SelectionSizeSnapMode.allSelections.rawValue)
                    }.labelsHidden()
                }
                settingWithDescription(
                    title: L("Show snap alignment guides"),
                    description: L("Show guide lines when moving an annotation near other annotations")
                ) {
                    Toggle("", isOn: $snapGuidesEnabled).labelsHidden()
                }
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

            // MARK: - Scroll Capture
            Section {
                // Auto-scroll with description (shown when enabled)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Auto-scroll"), isOn: $scrollAutoScroll)
                    if scrollAutoScroll {
                        Text(L("Sends synthetic scroll events to automatically scroll the page"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

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

                // Smart exclude fixed headers with description (always shown)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Smart exclude fixed headers"), isOn: $scrollFrozenDetection)
                    Text(L("Automatically detect and exclude sticky/fixed elements at the top of the page to avoid duplication when stitching"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(L("Scroll Capture"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizePickerSelections)
    }

    private func normalizePickerSelections() {
        PostCaptureActionPreferences.migrateIfNeeded()
        imageFormat = normalized(imageFormat, allowed: ["png", "jpeg", "heic", "webp"], fallback: "png")
        historySize = normalized(historySize, allowed: [999, 10, 25, 50, 100], fallback: 10)
        scrollSpeed = normalized(scrollSpeed, allowed: [1, 2, 3, 4], fallback: 3)
        scrollMaxHeight = normalized(
            scrollMaxHeight,
            allowed: [0, 10000, 30000, 50000, 100000],
            fallback: 30000
        )
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
