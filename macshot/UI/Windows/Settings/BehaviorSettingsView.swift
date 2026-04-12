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

    // OCR
    @AppStorage("ocrAction") private var ocrAction: Int = 0

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
                    screenshotBinding: nil,
                    recordingBinding: $recordingOpenVideoEditor,
                    title: L("Open video editor")
                )
            } header: {
                Text(L("After Capture"))
            }

            Section {
                Picker(L("OCR Capture"), selection: $ocrAction) {
                    Text(L("Show window + copy to clipboard")).tag(0)
                    Text(L("Show window only")).tag(1)
                    Text(L("Copy to clipboard only")).tag(2)
                }
            } header: {
                Text(L("OCR"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizeSettings)
    }

    private func normalizeSettings() {
        PostCaptureActionPreferences.migrateIfNeeded()
        ocrAction = normalized(ocrAction, allowed: [0, 1, 2], fallback: 0)
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
                .frame(width: 88, alignment: .center)

            Text(L("Recording"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 88, alignment: .center)

            Text(L("Action"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

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
                .frame(width: 88)

            actionToggleCell(binding: recordingBinding)
                .frame(width: 88)

            Text(title)
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
