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

    // Recording actions
    @AppStorage(PostCaptureActionPreferences.Keys.recordingShowQuickAccessOverlay)
    private var recordingShowQuickAccessOverlay = false
    @AppStorage(PostCaptureActionPreferences.Keys.recordingCopyToClipboard)
    private var recordingCopyToClipboard = false
    @AppStorage(PostCaptureActionPreferences.Keys.recordingSaveToFile)
    private var recordingSaveToFile = false
    @AppStorage(PostCaptureActionPreferences.Keys.recordingUploadAndCopyLink)
    private var recordingUploadAndCopyLink = false
    @AppStorage(PostCaptureActionPreferences.Keys.recordingOpenVideoEditor)
    private var recordingOpenVideoEditor = true

    // Sound feedback
    @AppStorage("playCopySound") private var playCopySound = true
    @AppStorage("playRecordingSound") private var playRecordingSound = false

    // OCR
    @AppStorage("ocrShowWindow") private var ocrShowWindow = true
    @AppStorage("ocrCopyToClipboard") private var ocrCopyToClipboard = true

    // Translation
    @AppStorage("translationProvider") private var translationProvider = "google"

    // Show in Finder
    @AppStorage("screenshotShowInFinder") private var screenshotShowInFinder = false
    @AppStorage("recordingShowInFinder") private var recordingShowInFinder = false

    var body: some View {
        Form {
            Section {
                actionMatrixHeader()

                actionMatrixRow(
                    screenshotBinding: $screenshotShowQuickAccessOverlay,
                    recordingBinding: $recordingShowQuickAccessOverlay,
                    title: L("Show quick access overlay")
                )
                actionMatrixRow(
                    screenshotBinding: $screenshotCopyToClipboard,
                    recordingBinding: $recordingCopyToClipboard,
                    title: L("Copy file to clipboard")
                )
                actionMatrixRow(
                    screenshotBinding: $screenshotSaveToFile,
                    recordingBinding: $recordingSaveToFile,
                    title: L("Save to file")
                )
                actionMatrixRow(
                    screenshotBinding: $screenshotShowInFinder,
                    recordingBinding: $recordingShowInFinder,
                    title: L("Show in Finder")
                )
                actionMatrixRow(
                    screenshotBinding: $screenshotUploadAndCopyLink,
                    recordingBinding: $recordingUploadAndCopyLink,
                    title: L("Upload and copy link")
                )
                actionMatrixRow(
                    screenshotBinding: $screenshotOpenEditor,
                    recordingBinding: nil,
                    title: L("Open screenshot editor")
                )
                actionMatrixRow(
                    screenshotBinding: $screenshotPinToScreen,
                    recordingBinding: nil,
                    title: L("Pin to screen")
                )
                actionMatrixRow(
                    screenshotBinding: $playCopySound,
                    recordingBinding: $playRecordingSound,
                    title: L("Play sound")
                )
                actionMatrixRow(
                    screenshotBinding: nil,
                    recordingBinding: $recordingOpenVideoEditor,
                    title: L("Open video editor")
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
        .onAppear(perform: normalizeSettings)
    }

    private func normalizeSettings() {
        PostCaptureActionPreferences.migrateIfNeeded()

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
    private func actionMatrixHeader() -> some View {
        HStack(spacing: 12) {
            Text(L("Screenshot"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .center)

            Text(L("Recording"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .center)

            Text(L("Action"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.leading, 30)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func actionMatrixRow(
        screenshotBinding: Binding<Bool>?,
        recordingBinding: Binding<Bool>?,
        title: String
    ) -> some View {
        HStack(spacing: 12) {
            actionToggleCell(binding: screenshotBinding)
                .frame(width: 100)

            actionToggleCell(binding: recordingBinding)
                .frame(width: 100)

            Text(title)
                .padding(.leading, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actionToggleCell(binding: Binding<Bool>?) -> some View {
        if let binding {
            Toggle("", isOn: binding)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text("—")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
