import SwiftUI

struct OutputSettingsView: View {

    // Save
    @State private var savePath: String = SaveDirectoryAccess.displayPath
    @State private var recordingSavePath: String = SaveDirectoryAccess.recordingDisplayPath
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("imageQuality") private var imageQuality = 0.85
    @AppStorage("downscaleRetina") private var downscaleRetina = false
    @AppStorage("embedColorProfile") private var embedColorProfile = false

    // Filename format
    @State private var screenshotFilenameFormat = FilenameFormat.screenshotFormat

    // History
    @AppStorage("historySize") private var historySize = 10

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

                FilenameFormatSettingsButton(
                    format: $screenshotFilenameFormat,
                    fileExtension: ImageEncoder.fileExtension,
                    title: L("Filename format")
                )
                .onChange(of: screenshotFilenameFormat) { newFormat in
                    FilenameFormat.screenshotFormat = newFormat
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
                Text(L("Save"))
            }

            // MARK: - Recording
            Section {
                HStack {
                    Text(L("Save folder"))
                    Spacer()
                    Text(recordingSavePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L("Browse…")) {
                        browseRecordingSavePath()
                    }
                    Button(L("Clear")) {
                        SaveDirectoryAccess.clearRecordingDirectory()
                        recordingSavePath = SaveDirectoryAccess.recordingDisplayPath
                    }
                }
            } header: {
                Text(L("Recording"))
            }

            // MARK: - Translation
            if TranslationService.appleTranslationAvailable {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(L("Engine"), selection: $translationProvider) {
                            Text(L("Apple (on-device)")).tag("apple")
                            Text(L("Google Translate")).tag("google")
                        }
                        .onChange(of: translationProvider) { newValue in
                            TranslationService.provider = TranslationProvider(rawValue: newValue) ?? .google
                        }

                        if translationProvider == "apple" {
                            Text(L("Apple translation is faster and works offline."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if translationProvider == "google" {
                            Text(L("Google Translate supports more languages."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text(L("Language packs"))
                        Spacer()
                        Button(L("Download")) {
                            // Open System Settings > General > Language & Region
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Localization") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } header: {
                    Text(L("Translation"))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizePickerSelections)
    }

    private var qualityPercentString: String {
        "\(Int(round(imageQuality * 100)))%"
    }

    private func normalizePickerSelections() {
        imageFormat = normalized(imageFormat, allowed: ["png", "jpeg", "heic", "webp"], fallback: "png")
        historySize = normalized(historySize, allowed: [999, 10, 25, 50, 100], fallback: 10)

        if TranslationService.appleTranslationAvailable {
            translationProvider = normalized(
                translationProvider,
                allowed: ["apple", "google"],
                fallback: "google"
            )
        } else {
            translationProvider = "google"
        }
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

    private func browseRecordingSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveDirectoryAccess.recordingDirectoryHint()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            SaveDirectoryAccess.saveRecordingDirectory(url: url)
            recordingSavePath = url.path
        }
    }

}
