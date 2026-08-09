import SwiftUI

struct BehaviorSettingsView: View {

    // Screenshot actions
    @AppStorage(PostCaptureActionPreferences.Keys.screenshotShowQuickAccessOverlay)
    private var screenshotShowQuickAccessOverlay = true
    @AppStorage(PostCaptureActionPreferences.Keys.screenshotCopyToClipboard)
    private var screenshotCopyToClipboard = true
    @AppStorage(PostCaptureActionPreferences.Keys.screenshotSaveToFile)
    private var screenshotSaveToFile = false
    @AppStorage(PostCaptureActionPreferences.Keys.screenshotUploadAndCopyLink)
    private var screenshotUploadAndCopyLink = false
    @AppStorage(PostCaptureActionPreferences.Keys.screenshotOpenEditor)
    private var screenshotOpenEditor = false
    @AppStorage(PostCaptureActionPreferences.Keys.screenshotPinToScreen)
    private var screenshotPinToScreen = false

    // Sound feedback
    @AppStorage(SoundSettings.captureEnabled) private var captureSoundEnabled = true

    // OCR
    @AppStorage("ocrShowWindow") private var ocrShowWindow = true
    @AppStorage("ocrCopyToClipboard") private var ocrCopyToClipboard = true

    // Translation
    @AppStorage("translationProvider") private var translationProvider = "google"

    // Show in Finder
    @AppStorage("screenshotShowInFinder") private var screenshotShowInFinder = false

    var body: some View {
        Form {
            Section {
                actionRow(
                    binding: $captureSoundEnabled,
                    title: L("Play sound")
                )
                actionRow(
                    binding: $screenshotSaveToFile,
                    title: L("Save to file")
                )
                actionRow(
                    binding: $screenshotCopyToClipboard,
                    title: L("Copy file to clipboard")
                )
                actionRow(
                    binding: $screenshotShowInFinder,
                    title: L("Show in Finder")
                )
                actionRow(
                    binding: $screenshotShowQuickAccessOverlay,
                    title: L("Show quick access overlay")
                )
                actionRow(
                    binding: $screenshotUploadAndCopyLink,
                    title: L("Upload and copy link")
                )
                actionRow(
                    binding: $screenshotPinToScreen,
                    title: L("Pin to screen")
                )
                actionRow(
                    binding: $screenshotOpenEditor,
                    title: L("Open screenshot editor")
                )
            } header: {
                Text(L("After Capture"))
            }

            Section {
                HStack(alignment: .center) {
                    Text(L("OCR"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Button("") {
                                ocrShowWindow.toggle()
                            }
                            .buttonStyle(.checkbox(checked: ocrShowWindow))

                            Text(L("Show window"))
                        }

                        HStack(spacing: 6) {
                            Button("") {
                                ocrCopyToClipboard.toggle()
                            }
                            .buttonStyle(.checkbox(checked: ocrCopyToClipboard))

                            Text(L("Copy to clipboard"))
                        }
                    }
                }
            }

            // MARK: - Translation
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L("Engine"), selection: $translationProvider) {
                        Text(L("Google Translate")).tag("google")
                        Text(L("Youdao (有道)")).tag("youdao")
                    }
                    .onChange(of: translationProvider) { newValue in
                        TranslationService.provider = TranslationProvider(rawValue: newValue) ?? .youdao
                    }

                    if translationProvider == "google" {
                        Text(L("Google Translate supports more languages."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if translationProvider == "youdao" {
                        Text(L("Youdao provides excellent Chinese-English translation."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(L("Translation"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizeSettings)
    }

    private func normalizeSettings() {
        PostCaptureActionPreferences.migrateIfNeeded()

        translationProvider = normalized(
            translationProvider,
            allowed: ["google", "youdao"],
            fallback: "youdao"
        )
    }

    private func normalized<T: Equatable>(_ value: T, allowed: [T], fallback: T) -> T {
        allowed.contains(value) ? value : fallback
    }

    @ViewBuilder
    private func actionRow(binding: Binding<Bool>, title: String) -> some View {
        Toggle(title, isOn: binding)
            .padding(.vertical, 2)
    }
}

struct CheckboxButtonStyle: ButtonStyle {
    let checked: Bool

    func makeBody(configuration: Configuration) -> some View {
        Image(systemName: checked ? "checkmark.square.fill" : "square")
            .foregroundColor(checked ? .accentColor : .secondary)
            .imageScale(.large)
    }
}

extension ButtonStyle where Self == CheckboxButtonStyle {
    static func checkbox(checked: Bool) -> CheckboxButtonStyle {
        CheckboxButtonStyle(checked: checked)
    }
}
