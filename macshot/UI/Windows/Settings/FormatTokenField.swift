import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 外部紧凑入口：左侧标题，右侧路径摘要和设置按钮。
struct SaveLocationSettingsRow: View {
    let screenshotPath: String
    let recordingPath: String
    let onBrowseScreenshot: () -> Void
    let onBrowseRecording: () -> Void
    let onClearRecording: () -> Void

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Save folder"))
            Spacer()
            Text(compactSummaryText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(L("Settings…")) {
                showPopover.toggle()
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                SaveLocationPopoverView(
                    screenshotPath: screenshotPath,
                    recordingPath: recordingPath,
                    onBrowseScreenshot: onBrowseScreenshot,
                    onBrowseRecording: onBrowseRecording,
                    onClearRecording: onClearRecording
                )
                .frame(width: 460)
                .padding(16)
            }
        }
    }

    private var compactSummaryText: String {
        let screenshotName = displayName(for: screenshotPath)
        let recordingName = recordingPath == L("Same as screenshots")
            ? recordingPath
            : displayName(for: recordingPath)
        return "\(L("Screenshot")): \(screenshotName)  |  \(L("Recording")): \(recordingName)"
    }

    private func displayName(for path: String) -> String {
        if path == L("Same as screenshots") {
            return path
        }

        let expanded = (path as NSString).expandingTildeInPath
        let lastComponent = URL(fileURLWithPath: expanded).lastPathComponent
        return lastComponent.isEmpty ? path : lastComponent
    }
}

/// 外部紧凑入口：左侧标题，右侧预览和设置按钮。
struct FilenameFormatSettingsRow: View {
    @Binding var format: TokenFilenameFormat
    @Binding var previewKind: FilenameOutputKind
    let screenshotExtension: String

    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Filename"))
            Spacer()
            Text(compactPreviewText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(L("Settings…")) {
                showPopover.toggle()
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                FormatTokenField(
                    format: $format,
                    previewKind: $previewKind,
                    screenshotExtension: screenshotExtension
                )
                .frame(width: 430)
                .padding(16)
            }
        }
    }

    /// 外层一行只展示文件名规则生成后的主体名称。
    private var compactPreviewText: String {
        FilenameTemplateEngine.makeBaseName(
            format: format,
            kind: previewKind
        )
    }
}

/// Popover 里的完整编辑器：
/// - 顶部是真实的 NSTokenField
/// - 中间是预览类型切换和实时预览
/// - 底部是变量池
struct FormatTokenField: View {
    @Binding var format: TokenFilenameFormat
    @Binding var previewKind: FilenameOutputKind
    let screenshotExtension: String

    @State private var insertionController = TokenFieldInsertionController()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Filename"))
                .font(.headline)

            MacTokenField(
                format: $format,
                insertionController: insertionController
            )
            .frame(height: 52)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
            .onDrop(of: [.plainText], isTargeted: $isDropTargeted, perform: handleDrop(providers:))

            VStack(alignment: .leading, spacing: 8) {
                Picker(L("Preview"), selection: $previewKind) {
                    ForEach(previewKinds, id: \.self) { kind in
                        Text(kind.localizedLabel).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Text(format.preview(kind: previewKind, fileExtension: fileExtension(for: previewKind)))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Insert variable"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(FormatToken.allVariables, id: \.self) { token in
                        TokenInsertButtonView(token: token) {
                            insert(token: token)
                        }
                    }
                }
            }

        }
    }

    private var previewKinds: [FilenameOutputKind] {
        [.screenshot, .recording]
    }

    private func fileExtension(for kind: FilenameOutputKind) -> String {
        switch kind {
        case .screenshot:
            return screenshotExtension
        case .recording:
            return "mp4"
        case .gif:
            return "gif"
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let code = object as? NSString,
                  let token = FormatToken.fromVariableCode(code as String) else { return }
            DispatchQueue.main.async {
                insert(token: token)
            }
        }
        return true
    }

    private func insert(token: FormatToken) {
        if insertionController.insert(token: token) {
            return
        }

        format.tokens.append(token)
    }
}

private struct SaveLocationPopoverView: View {
    let screenshotPath: String
    let recordingPath: String
    let onBrowseScreenshot: () -> Void
    let onBrowseRecording: () -> Void
    let onClearRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Save folder"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                locationRow(
                    title: L("Screenshot"),
                    path: screenshotPath,
                    actionTitle: L("Browse…"),
                    action: onBrowseScreenshot
                )

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    locationRow(
                        title: L("Recording"),
                        path: recordingPath,
                        actionTitle: L("Browse…"),
                        action: onBrowseRecording
                    )

                    HStack(spacing: 8) {
                        Spacer()
                        Button(L("Clear")) {
                            onClearRecording()
                        }
                        .disabled(recordingPath == L("Same as screenshots"))
                    }

                    Text(L("GIF uses the recording folder."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func locationRow(title: String, path: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(alignment: .center, spacing: 10) {
                Text(path)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)

                Button(actionTitle, action: action)
            }
        }
    }
}

private final class TokenFieldInsertionController {
    var insertHandler: ((FormatToken) -> Void)?

    func insert(token: FormatToken) -> Bool {
        guard let insertHandler else { return false }
        insertHandler(token)
        return true
    }
}

private struct MacTokenField: NSViewRepresentable {
    @Binding var format: TokenFilenameFormat
    let insertionController: TokenFieldInsertionController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTokenField {
        let tokenField = NSTokenField(frame: .zero)
        tokenField.delegate = context.coordinator
        tokenField.font = .systemFont(ofSize: 14)
        tokenField.controlSize = .large
        tokenField.tokenizingCharacterSet = CharacterSet()
        tokenField.focusRingType = .none
        tokenField.isBordered = false
        tokenField.drawsBackground = false
        tokenField.completionDelay = 0
        tokenField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.tokenField = tokenField
        context.coordinator.apply(format: format, to: tokenField, preserveSelection: false)
        return tokenField
    }

    func updateNSView(_ nsView: NSTokenField, context: Context) {
        context.coordinator.parent = self
        insertionController.insertHandler = { [weak coordinator = context.coordinator, weak nsView] token in
            guard let coordinator, let nsView else { return }
            coordinator.insert(token: token, into: nsView)
        }
        context.coordinator.apply(format: format, to: nsView, preserveSelection: true)
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: MacTokenField
        weak var tokenField: NSTokenField?
        var lastAppliedSerialized = ""
        private var pendingSelectedRange: NSRange?
        private var lastKnownSelectedRange = NSRange(location: 0, length: 0)
        private var selectionObserver: NSObjectProtocol?

        init(parent: MacTokenField) {
            self.parent = parent
        }

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            installSelectionObserverIfNeeded()
        }

        func controlTextDidChange(_ notification: Notification) {
            if let editor = tokenField?.currentEditor() as? NSTextView {
                lastKnownSelectedRange = editor.selectedRange()
            }
            syncFromControl()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if let editor = tokenField?.currentEditor() as? NSTextView {
                lastKnownSelectedRange = editor.selectedRange()
            }
            syncFromControl()
        }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            if let variable = representedObject as? VariableTokenObject {
                return variable.token.variableCode
            }
            if let text = representedObject as? String {
                return text
            }
            if let text = representedObject as? NSString {
                return text as String
            }
            return nil
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
            if let variable = representedObject as? VariableTokenObject {
                return variable.token.variableCode
            }
            if let text = representedObject as? String {
                return text
            }
            if let text = representedObject as? NSString {
                return text as String
            }
            return nil
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
            if let variable = FormatToken.fromVariableCode(editingString) {
                return VariableTokenObject(token: variable)
            }
            return editingString
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            if representedObject is VariableTokenObject {
                return .rounded
            }
            return .none
        }

        func apply(format: TokenFilenameFormat, to tokenField: NSTokenField, preserveSelection: Bool) {
            let serialized = format.serializedString
            guard lastAppliedSerialized != serialized || tokenField.objectValue == nil else { return }

            if preserveSelection, let editor = tokenField.currentEditor() as? NSTextView {
                pendingSelectedRange = editor.selectedRange()
            }

            lastAppliedSerialized = serialized
            tokenField.objectValue = format.tokens.map { token -> Any in
                switch token {
                case .text(let text):
                    return text
                default:
                    return VariableTokenObject(token: token)
                }
            }

            if let selectedRange = pendingSelectedRange {
                DispatchQueue.main.async { [weak tokenField] in
                    guard let editor = tokenField?.currentEditor() as? NSTextView else { return }
                    let clampedLocation = min(selectedRange.location, (tokenField?.stringValue as NSString?)?.length ?? 0)
                    editor.setSelectedRange(NSRange(location: clampedLocation, length: 0))
                }
            }
        }

        func insert(token: FormatToken, into tokenField: NSTokenField) {
            guard let code = token.variableCode else { return }

            let currentString = tokenField.stringValue
            let nsString = currentString as NSString
            let selectedRange = currentSelectedRange(in: tokenField)
            let newString = nsString.replacingCharacters(in: selectedRange, with: code)
            let newRange = NSRange(location: selectedRange.location + code.count, length: 0)

            pendingSelectedRange = newRange
            let parsed = TokenFilenameFormat.fromSerializedString(newString)
            parent.format = parsed
            apply(format: parsed, to: tokenField, preserveSelection: false)

            DispatchQueue.main.async { [weak tokenField] in
                guard let tokenField else { return }
                tokenField.window?.makeFirstResponder(tokenField)
                if let editor = tokenField.currentEditor() as? NSTextView {
                    editor.setSelectedRange(newRange)
                }
            }
        }

        private func currentSelectedRange(in tokenField: NSTokenField) -> NSRange {
            if let editor = tokenField.currentEditor() as? NSTextView {
                return editor.selectedRange()
            }

            if lastKnownSelectedRange.location > 0 || lastKnownSelectedRange.length > 0 {
                return lastKnownSelectedRange
            }

            let stringLength = (tokenField.stringValue as NSString).length
            return NSRange(location: stringLength, length: 0)
        }

        private func syncFromControl() {
            guard let tokenField else { return }
            let parsed = TokenFilenameFormat.fromSerializedString(tokenField.stringValue)
            lastAppliedSerialized = parsed.serializedString
            if parent.format != parsed {
                parent.format = parsed
            }
        }

        private func installSelectionObserverIfNeeded() {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }

            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let editor = notification.object as? NSTextView,
                      editor == self.tokenField?.currentEditor() as? NSTextView else { return }
                self.lastKnownSelectedRange = editor.selectedRange()
            }
        }
    }
}

private final class VariableTokenObject: NSObject {
    let token: FormatToken

    init(token: FormatToken) {
        self.token = token
    }
}

private struct TokenInsertButtonView: View {
    let token: FormatToken
    let onInsert: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(token.label)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 4)
            Text(token.variableCode ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onInsert)
        .onHover { isHovered = $0 }
        .onDrag {
            NSItemProvider(object: NSString(string: token.variableCode ?? ""))
        }
    }
}
