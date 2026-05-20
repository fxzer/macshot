import SwiftUI
import Combine
import Carbon

private enum ShortcutConflictAlert {
    static func confirmReplacement(title: String, shortcut: String, existingAction: String, newAction: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String.localizedStringWithFormat(
            L("Shortcut conflict message"),
            shortcut,
            existingAction,
            newAction
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Replace"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Inline Key Recorder Field

struct KeyRecorderField: View {
    let currentDisplay: String
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onClear: () -> Void
    let onReset: () -> Void

    @State private var isHovered = false
    @State private var suppressNextStartRecording = false
    private let accessoryWidth: CGFloat = 14
    private let fieldWidth: CGFloat = 112

    var body: some View {
        ZStack {
            Text(isRecording ? L("Type shortcut…") : currentDisplay)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(isRecording ? .white : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 4) {
                Color.clear
                    .frame(width: accessoryWidth, height: 1)

                Spacer(minLength: 0)

                Group {
                    if !isRecording && currentDisplay != L("None") && isHovered {
                        Button {
                            suppressNextStartRecording = true
                            onClear()
                            DispatchQueue.main.async {
                                suppressNextStartRecording = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: accessoryWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: fieldWidth, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            guard !suppressNextStartRecording else { return }
            onStartRecording()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(L("Reset to default")) {
                onReset()
            }
            Button(L("Clear")) {
                onClear()
            }
        }
    }
}

private enum RatioInputFocusField: Hashable {
    case width
    case height
}

private struct RatioInputTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var focusedField: RatioInputFocusField?
    let field: RatioInputFocusField
    var onTab: (() -> Void)?
    var onBacktab: (() -> Void)?
    var onSubmit: (() -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = placeholder
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.controlSize = .small
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        guard focusedField == field,
              let window = nsView.window else { return }

        let isFirstResponder = window.firstResponder === nsView || window.firstResponder === nsView.currentEditor()
        guard !isFirstResponder else { return }

        DispatchQueue.main.async {
            guard focusedField == field else { return }
            window.makeFirstResponder(nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RatioInputTextField

        init(parent: RatioInputTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focusedField = parent.field
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            if parent.text != textField.stringValue {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                guard let onTab = parent.onTab else { return false }
                onTab()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                guard let onBacktab = parent.onBacktab else { return false }
                onBacktab()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                return parent.onSubmit?() ?? false
            default:
                return false
            }
        }
    }
}

// MARK: - Global Hotkey Recording Model

class HotkeyRecordingModel: ObservableObject {
    @Published var recordingSlot: HotkeyManager.HotkeySlot?
    @Published var displayStrings: [HotkeyManager.HotkeySlot: String] = [:]

    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var mouseDownPosition: NSPoint?
    var onHotkeyChanged: (() -> Void)?

    init() {
        refreshAll()
    }

    func refreshAll() {
        for slot in HotkeyManager.HotkeySlot.allCases {
            displayStrings[slot] = HotkeyManager.displayString(for: slot)
        }
    }

    func startRecording(slot: HotkeyManager.HotkeySlot) {
        stopRecording()
        recordingSlot = slot

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Escape cancels (bare Esc only — ⌘+Esc etc. can be assigned as global shortcuts)
            if event.isBareEscapeForShortcutRecording {
                self.stopRecording()
                return nil
            }

            // Delete/Backspace clears
            if event.keyCode == 51 || event.keyCode == 117 {
                self.clearShortcut(slot: slot)
                return nil
            }

            let modifiers = event.modifierFlags
            var carbonMods: UInt32 = 0
            if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
            let keyCode = UInt32(event.keyCode)
            if carbonMods == 0 && !HotkeyManager.isFunctionKey(keyCode) { return nil }
            self.assignShortcut(slot: slot, keyCode: keyCode, modifiers: carbonMods)
            return nil
        }

        // Track mouse down position to detect drags vs clicks
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .leftMouseDown {
                // Record mouse down position
                self.mouseDownPosition = event.locationInWindow
                return event
            }

            if event.type == .leftMouseUp {
                // Check if this was a click (not a drag) and if click is outside recording fields
                guard let downPos = self.mouseDownPosition,
                      let window = event.window,
                      let contentView = window.contentView else {
                    self.mouseDownPosition = nil
                    return event
                }

                let upPos = event.locationInWindow
                let distance = sqrt(pow(downPos.x - upPos.x, 2) + pow(downPos.y - upPos.y, 2))

                // Only treat as click if mouse didn't move much (not a drag)
                if distance < 5 {
                    if let hitView = contentView.hitTest(upPos) {
                        // Walk up the view hierarchy to check if this click is on a button
                        var view: NSView? = hitView
                        var isInteractiveControl = false

                        while view != nil && view != contentView {
                            let viewName = String(describing: type(of: view))

                            // Check for various SwiftUI/AppKit control types
                            if viewName.contains("Button") ||
                               viewName.contains("NSButton") ||
                               viewName.contains("PopUpButton") ||
                               viewName.contains("Slider") ||
                               viewName.contains("TextField") ||
                               viewName.contains("Segment") ||
                               viewName.contains("Control") {
                                isInteractiveControl = true
                                break
                            }

                            view = view?.superview
                        }

                        // Only cancel if clicking on non-interactive areas
                        if !isInteractiveControl {
                            self.stopRecording()
                        }
                    }
                }

                self.mouseDownPosition = nil
                return event
            }

            return event
        }
    }

    func clearShortcut(slot: HotkeyManager.HotkeySlot) {
        stopRecording()
        HotkeyManager.disableHotkey(for: slot)
        displayStrings[slot] = L("None")
        onHotkeyChanged?()
    }

    func resetShortcut(slot: HotkeyManager.HotkeySlot) {
        stopRecording()
        assignShortcut(slot: slot, keyCode: slot.defaultKeyCode, modifiers: slot.defaultModifiers)
    }

    func stopRecording() {
        recordingSlot = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
    }

    private func assignShortcut(slot: HotkeyManager.HotkeySlot, keyCode: UInt32, modifiers: UInt32) {
        stopRecording()

        if let conflictSlot = HotkeyManager.conflictingSlot(for: keyCode, modifiers: modifiers, excluding: slot) {
            let shortcut = HotkeyManager.modifierString(from: modifiers) + HotkeyManager.keyString(from: keyCode)
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: shortcut,
                existingAction: conflictSlot.label,
                newAction: slot.label
            )
            guard shouldReplace else { return }
            HotkeyManager.disableHotkey(for: conflictSlot)
        }

        HotkeyManager.saveHotkey(for: slot, keyCode: keyCode, modifiers: modifiers)
        refreshAll()
        onHotkeyChanged?()
    }
}

// MARK: - Tool Shortcut Recording Model

class ToolShortcutRecordingModel: ObservableObject {
    @Published var recordingAction: ToolShortcutManager.Action?
    @Published var displayStrings: [ToolShortcutManager.Action: String] = [:]

    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var mouseDownPosition: NSPoint?

    init() {
        refreshAll()
    }

    func refreshAll() {
        for action in ToolShortcutManager.Action.allCases {
            displayStrings[action] = ToolShortcutManager.displayString(for: action)
        }
    }

    func startRecording(action: ToolShortcutManager.Action) {
        stopRecording()
        recordingAction = action

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Escape cancels (bare Esc only)
            if event.isBareEscapeForShortcutRecording {
                self.stopRecording()
                return nil
            }

            // Delete/Backspace clears
            if event.keyCode == 51 || event.keyCode == 117 {
                self.clearShortcut(action: action)
                return nil
            }

            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control),
                  let char = event.charactersIgnoringModifiers?.lowercased(),
                  char.count == 1 else { return nil }

            self.assignShortcut(action: action, key: char)
            return nil
        }

        // Track mouse down position to detect drags vs clicks
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .leftMouseDown, .rightMouseUp, .rightMouseDown, .otherMouseUp, .otherMouseDown]
        ) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .leftMouseDown {
                // Record mouse down position
                self.mouseDownPosition = event.locationInWindow
                return event
            }

            if event.type == .rightMouseDown || event.type == .otherMouseDown {
                self.mouseDownPosition = event.locationInWindow
                return nil
            }

            if event.type == .rightMouseUp || event.type == .otherMouseUp {
                defer { self.mouseDownPosition = nil }
                guard let shortcut = ToolShortcutManager.shortcutValue(forMouseButton: event.buttonNumber) else {
                    return nil
                }
                if self.isClickRelease(event) {
                    self.assignShortcut(action: action, key: shortcut)
                    return nil
                }
                return nil
            }

            if event.type == .leftMouseUp {
                // Check if this was a click (not a drag) and if click is outside recording fields
                guard let downPos = self.mouseDownPosition,
                      let window = event.window,
                      let contentView = window.contentView else {
                    self.mouseDownPosition = nil
                    return event
                }

                let upPos = event.locationInWindow
                let distance = sqrt(pow(downPos.x - upPos.x, 2) + pow(downPos.y - upPos.y, 2))

                // Only treat as click if mouse didn't move much (not a drag)
                if distance < 5 {
                    if let hitView = contentView.hitTest(upPos) {
                        // Walk up the view hierarchy to check if this click is on a button
                        var view: NSView? = hitView
                        var isInteractiveControl = false

                        while view != nil && view != contentView {
                            let viewName = String(describing: type(of: view))

                            // Check for various SwiftUI/AppKit control types
                            if viewName.contains("Button") ||
                               viewName.contains("NSButton") ||
                               viewName.contains("PopUpButton") ||
                               viewName.contains("Slider") ||
                               viewName.contains("TextField") ||
                               viewName.contains("Segment") ||
                               viewName.contains("Control") {
                                isInteractiveControl = true
                                break
                            }

                            view = view?.superview
                        }

                        // Only cancel if clicking on non-interactive areas
                        if !isInteractiveControl {
                            self.stopRecording()
                        }
                    }
                }

                self.mouseDownPosition = nil
                return event
            }

            return event
        }
    }

    func clearShortcut(action: ToolShortcutManager.Action) {
        stopRecording()
        ToolShortcutManager.setKey("", for: action)
        displayStrings[action] = L("None")
    }

    func resetShortcut(action: ToolShortcutManager.Action) {
        stopRecording()
        assignShortcut(action: action, key: action.defaultKey)
    }

    func stopRecording() {
        recordingAction = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
    }

    private func assignShortcut(action: ToolShortcutManager.Action, key: String) {
        stopRecording()

        if let conflictAction = ToolShortcutManager.conflictingAction(for: key, excluding: action) {
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: ToolShortcutManager.displayString(forKey: key),
                existingAction: conflictAction.label,
                newAction: action.label
            )
            guard shouldReplace else { return }
            ToolShortcutManager.setKey("", for: conflictAction)
        }

        if ToolShortcutManager.isKeyboardShortcut(key),
           let conflictRatio = AspectRatioShortcutManager.conflictingRatio(for: key, excluding: nil) {
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: ToolShortcutManager.displayString(forKey: key),
                existingAction: conflictRatio.displayName,
                newAction: action.label
            )
            guard shouldReplace else { return }
            AspectRatioShortcutManager.setKey("", for: conflictRatio.id)
        }

        ToolShortcutManager.setKey(key, for: action)
        refreshAll()
    }

    private func isClickRelease(_ event: NSEvent) -> Bool {
        guard let downPos = mouseDownPosition else { return false }
        let upPos = event.locationInWindow
        let distance = sqrt(pow(downPos.x - upPos.x, 2) + pow(downPos.y - upPos.y, 2))
        return distance < 5
    }
}

// MARK: - View

struct ShortcutsSettingsView: View {
    @StateObject private var hotkeyModel = HotkeyRecordingModel()
    @StateObject private var toolModel = ToolShortcutRecordingModel()
    @StateObject private var aspectRatioModel = AspectRatioShortcutRecordingModel()

    // Aspect ratio management states
    @State private var aspectRatios: [CustomAspectRatio] = []
    @State private var newWidthText = ""
    @State private var newHeightText = ""
    @State private var focusedRatioField: RatioInputFocusField?
    @State private var errorMessage: String?
    private let ratioInputControlHeight: CGFloat = 24
    private let ratioInputFieldWidth: CGFloat = 96

    var onHotkeyChanged: (() -> Void)?

    var body: some View {
        Form {
            // MARK: - Global Keyboard Shortcuts
            Section {
                ForEach(HotkeyManager.HotkeySlot.allCases, id: \.rawValue) { slot in
                    HStack {
                        Text(slot.label)
                        Spacer()
                        KeyRecorderField(
                            currentDisplay: hotkeyModel.displayStrings[slot] ?? L("None"),
                            isRecording: hotkeyModel.recordingSlot == slot,
                            onStartRecording: {
                                toolModel.stopRecording()
                                aspectRatioModel.stopRecording()
                                hotkeyModel.startRecording(slot: slot)
                            },
                            onClear: {
                                hotkeyModel.clearShortcut(slot: slot)
                            },
                            onReset: {
                                hotkeyModel.resetShortcut(slot: slot)
                            }
                        )
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Global Keyboard Shortcuts"))
                    Text(L("Click to record shortcut. Esc to cancel, ⌫ to clear. Right-click to reset."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Overlay / Editor Tool Shortcuts
            Section {
                ForEach(ToolShortcutManager.Action.allCases, id: \.rawValue) { action in
                    HStack {
                        Text(action.label)
                        Spacer()
                        KeyRecorderField(
                            currentDisplay: toolModel.displayStrings[action] ?? L("None"),
                            isRecording: toolModel.recordingAction == action,
                            onStartRecording: {
                                hotkeyModel.stopRecording()
                                aspectRatioModel.stopRecording()
                                toolModel.startRecording(action: action)
                            },
                            onClear: {
                                toolModel.clearShortcut(action: action)
                            },
                            onReset: {
                                toolModel.resetShortcut(action: action)
                            }
                        )
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("In-App Shortcuts"))
                    Text(L("Press a single key, right-click, or middle-click to assign. These work when the overlay or editor is active."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Aspect Ratio Shortcuts
            Section {
                if aspectRatios.isEmpty {
                    Text(L("No aspect ratios configured."))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(aspectRatios, id: \.id) { ratio in
                        HStack {
                            // 删除按钮
                            Button(action: { removeRatio(ratio) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .disabled(aspectRatios.count <= 1)
                            .help(L("Remove this ratio"))

                            // 比例名称
                            Text(ratio.displayName)
                                .frame(width: 96, alignment: .leading)

                            // 比例数值
                            Text(String(format: "%.2f", ratio.ratio))
                                .font(.system(.caption))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)

                            // 反转提示（非正方形比例）
                            if !ratio.isSquare {
                                let inverted = ratio.inverted
                                Text(String(format: L("R → %@"), inverted.displayName))
                                    .font(.system(.caption2))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 快捷键录制器
                            KeyRecorderField(
                                currentDisplay: aspectRatioModel.displayStrings[ratio.id] ?? L("None"),
                                isRecording: aspectRatioModel.recordingRatioID == ratio.id,
                                onStartRecording: {
                                    hotkeyModel.stopRecording()
                                    toolModel.stopRecording()
                                    aspectRatioModel.startRecording(ratioID: ratio.id)
                                },
                                onClear: {
                                    aspectRatioModel.clearShortcut(ratioID: ratio.id)
                                },
                                onReset: {
                                    aspectRatioModel.resetShortcut(ratioID: ratio.id)
                                }
                            )
                            .frame(maxWidth: 120)
                        }
                        .padding(.vertical, 2)
                    }

                    // 小标题分隔
                    Text(L("Add New Ratio"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(height: 16, alignment: .leading)

                    // 添加新比例
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            RatioInputTextField(
                                placeholder: L("Width"),
                                text: $newWidthText,
                                focusedField: $focusedRatioField,
                                field: .width,
                                onTab: { focusedRatioField = .height },
                                onSubmit: submitNewRatioFromKeyboard
                            )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .frame(width: ratioInputFieldWidth)
                                .frame(height: ratioInputControlHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            focusedRatioField == .width
                                                ? Color.accentColor
                                                : Color(nsColor: .separatorColor).opacity(0.55),
                                            lineWidth: focusedRatioField == .width ? 1.5 : 1
                                        )
                                )
                                .onChange(of: newWidthText) { _ in
                                    errorMessage = nil
                                }
                            Text(":")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 10, height: ratioInputControlHeight, alignment: .center)
                                .offset(y: -0.5)
                            RatioInputTextField(
                                placeholder: L("Height"),
                                text: $newHeightText,
                                focusedField: $focusedRatioField,
                                field: .height,
                                onBacktab: { focusedRatioField = .width },
                                onSubmit: submitNewRatioFromKeyboard
                            )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .frame(width: ratioInputFieldWidth)
                                .frame(height: ratioInputControlHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            focusedRatioField == .height
                                                ? Color.accentColor
                                                : Color(nsColor: .separatorColor).opacity(0.55),
                                            lineWidth: focusedRatioField == .height ? 1.5 : 1
                                        )
                                )
                                .onChange(of: newHeightText) { _ in
                                    errorMessage = nil
                                }

                            Button(action: { _ = addNewRatio() }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(
                                        isNewRatioValid
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                                    .frame(width: ratioInputControlHeight, height: ratioInputControlHeight)
                            }
                            .buttonStyle(.plain)
                            .frame(width: ratioInputControlHeight, height: ratioInputControlHeight)
                            .disabled(!isNewRatioValid)
                            .help(L("Add new aspect ratio"))

                            Spacer()

                            Button(L("Reset to Defaults")) {
                                AspectRatioPreferences.resetToDefaults()
                                loadAspectRatios()
                                errorMessage = nil
                            }
                            .buttonStyle(.link)
                            .controlSize(.small)
                            .foregroundStyle(Color.settingsSystemAccent)
                        }

                        // 错误提示
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Spacer()
                                Button(action: { errorMessage = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(L("Dismiss"))
                            }
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Aspect Ratio Shortcuts"))
                    Text(L("Press a single key to assign. These work when selecting a screenshot area."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hotkeyModel.onHotkeyChanged = onHotkeyChanged
            aspectRatioModel.refreshAll()
            loadAspectRatios()
        }
        .onDisappear {
            hotkeyModel.stopRecording()
            toolModel.stopRecording()
            aspectRatioModel.stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aspectRatiosDidChange)) { _ in
            aspectRatioModel.refreshAll()
            loadAspectRatios()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aspectRatioShortcutsDidChange)) { _ in
            aspectRatioModel.refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolShortcutsDidChange)) { _ in
            toolModel.refreshAll()
        }
    }

    // MARK: - Aspect Ratio Management

    private func loadAspectRatios() {
        aspectRatios = AspectRatioPreferences.allRatios
    }

    private var isNewRatioValid: Bool {
        guard let width = parsedRatioComponent(from: newWidthText),
              let height = parsedRatioComponent(from: newHeightText) else { return false }
        return AspectRatioPreferences.validationError(width: width, height: height) == nil
    }

    @discardableResult
    private func addNewRatio() -> Bool {
        guard let width = parsedRatioComponent(from: newWidthText),
              let height = parsedRatioComponent(from: newHeightText) else {
            errorMessage = L("Invalid ratio. Width and height must be between 0.01 and 100, with up to 2 decimal places.")
            return false
        }

        let (success, error) = AspectRatioPreferences.addRatio(width: width, height: height)
        guard success else {
            errorMessage = error ?? L("Failed to add ratio.")
            return false
        }

        errorMessage = nil
        newWidthText = ""
        newHeightText = ""
        focusedRatioField = .width
        loadAspectRatios()
        return true
    }

    private func removeRatio(_ ratio: CustomAspectRatio) {
        let (success, error) = AspectRatioPreferences.removeRatio(id: ratio.id)
        guard success else {
            errorMessage = error
            return
        }

        errorMessage = nil
        loadAspectRatios()
    }

    private func parsedRatioComponent(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        guard parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }

        if parts.count == 2 {
            guard parts[1].count <= CustomAspectRatio.maxFractionDigits else { return nil }
            if normalized.hasSuffix(".") {
                normalized.removeLast()
            }
        }

        guard normalized != ".", !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func submitNewRatioFromKeyboard() -> Bool {
        guard hasAnyRatioInput else { return false }
        _ = addNewRatio()
        return true
    }

    private var hasAnyRatioInput: Bool {
        !newWidthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !newHeightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Shortcut recording

extension NSEvent {
    /// Escape without Command/Shift/Option/Control — used to cancel shortcut recording so ⌘+Esc can be recorded as a global hotkey.
    var isBareEscapeForShortcutRecording: Bool {
        guard keyCode == 53 else { return false }
        let mask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return modifierFlags.intersection(.deviceIndependentFlagsMask).intersection(mask).isEmpty
    }
}
