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
                Toggle(L("Save at standard resolution (1x)"), isOn: $downscaleRetina)
                Toggle(L("Embed sRGB color profile"), isOn: $embedColorProfile)
            } header: {
                Text(L("Save"))
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    if downscaleRetina {
                        Text(L("Halves dimensions on Retina displays, ~4x smaller files"))
                    }
                    if embedColorProfile {
                        Text(L("Ensures consistent colors across different displays"))
                    }
                }
            }

            // MARK: - History
            Section {
                if !historyUnlimited {
                    Stepper(value: $historySize, in: 0...50) {
                        HStack {
                            Text(L("History size"))
                            Spacer()
                            Text("\(historySize)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
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
                    Text(L("Set to 0 to disable history"))
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
                    Button(L("Download language packs in System Settings…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization.Settings.extension?Translation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .foregroundColor(.accentColor)
                } header: {
                    Text(L("Translation"))
                } footer: {
                    Text(L("Apple translation is faster and works offline. Google Translate supports more languages."))
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
}
