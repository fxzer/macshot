import SwiftUI

struct OutputSettingsView: View {

    // Save
    @State private var savePath: String = SaveDirectoryAccess.displayPath
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("imageQuality") private var imageQuality = 0.85
    @AppStorage("downscaleRetina") private var downscaleRetina = false
    @AppStorage("embedColorProfile") private var embedColorProfile = false

    // History
    @AppStorage("historySize") private var historySize = 10
    @AppStorage("historyUnlimited") private var historyUnlimited = false

    // Translation
    @AppStorage("translationProvider") private var translationProvider = "google"

    var body: some View {
        Form {
            // MARK: - Save
            Section {
                HStack {
                    Text(L("Save folder"))
                    Spacer()
                    Text(savePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L("Browse…")) {
                        browseSavePath()
                    }
                }
                Picker(L("Image format"), selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpeg")
                    Text("HEIC").tag("heic")
                    Text("WebP").tag("webp")
                }
                if imageFormat == "jpeg" || imageFormat == "heic" || imageFormat == "webp" {
                    HStack {
                        Text(L("Quality"))
                        Slider(value: $imageQuality, in: 0.1...1.0, step: 0.01)
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
            } header: {
                Text(L("Save"))
            }

            // MARK: - History
            Section {
                if !historyUnlimited {
                    HStack {
                        Text("\(historySize)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Stepper(value: $historySize, in: 0...50) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    .onChange(of: historySize) { _ in
                        ScreenshotHistory.shared.pruneToMax()
                    }
                }
                Toggle(L("Unlimited"), isOn: $historyUnlimited)
            } header: {
                Text(L("History"))
            } footer: {
                if !historyUnlimited {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("History size"))
                        Text(L("Set to 0 to disable history"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Translation
            if TranslationService.appleTranslationAvailable {
                Section {
                    Picker(L("Engine"), selection: $translationProvider) {
                        Text(L("Apple (on-device)")).tag("apple")
                        Text(L("Google Translate")).tag("google")
                    }
                    .onChange(of: translationProvider) { newValue in
                        TranslationService.provider = TranslationProvider(rawValue: newValue) ?? .google
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Apple (on-device)"))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text(L("Apple translation is faster and works offline."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(L("Google Translate"))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                        Text(L("Google Translate supports more languages."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    Button(L("Download language packs in System Settings…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization.Settings.extension?Translation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .foregroundColor(.accentColor)
                } header: {
                    Text(L("Translation"))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var qualityPercentString: String {
        "\(Int(round(imageQuality * 100)))%"
    }

    private func browseSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveDirectoryAccess.directoryHint()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            SaveDirectoryAccess.save(url: url)
            savePath = url.path
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
