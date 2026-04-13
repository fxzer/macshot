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

    var body: some View {
        HStack(spacing: 4) {
            Text(isRecording ? L("Type shortcut…") : currentDisplay)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(isRecording ? .white : .secondary)
                .lineLimit(1)

            if !isRecording && currentDisplay != L("None") && isHovered {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 100, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .onTapGesture {
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

// MARK: - Global Hotkey Recording Model

class HotkeyRecordingModel: ObservableObject {
    @Published var recordingSlot: HotkeyManager.HotkeySlot?
    @Published var displayStrings: [HotkeyManager.HotkeySlot: String] = [:]

    private var localMonitor: Any?
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

            // Escape cancels
            if event.keyCode == 53 {
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
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
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

            // Escape cancels
            if event.keyCode == 53 {
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
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    private func assignShortcut(action: ToolShortcutManager.Action, key: String) {
        stopRecording()

        if let conflictAction = ToolShortcutManager.conflictingAction(for: key, excluding: action) {
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: key.uppercased(),
                existingAction: conflictAction.label,
                newAction: action.label
            )
            guard shouldReplace else { return }
            ToolShortcutManager.setKey("", for: conflictAction)
        }

        ToolShortcutManager.setKey(key, for: action)
        refreshAll()
    }
}

// MARK: - View

struct ShortcutsSettingsView: View {
    @StateObject private var hotkeyModel = HotkeyRecordingModel()
    @StateObject private var toolModel = ToolShortcutRecordingModel()
    @StateObject private var aspectRatioModel = AspectRatioShortcutRecordingModel()

    // Aspect ratio management states
    @State private var aspectRatios: [CustomAspectRatio] = []
    @State private var newWidth: Int?
    @State private var newHeight: Int?
    @State private var errorMessage: String?

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
                    Text(L("Press a single key to assign. These work when the overlay or editor is active."))
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
                            // 比例名称
                            Text(ratio.displayName)
                                .frame(width: 50, alignment: .leading)

                            // 比例数值
                            Text(String(format: "%.2f", ratio.ratio))
                                .font(.system(.caption))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)

                            // 反转提示（非正方形比例）
                            if ratio.width != ratio.height {
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

                            // 删除按钮
                            Button(action: { removeRatio(ratio) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help(L("Remove this ratio"))
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    // 添加新比例
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(L("Width"), value: $newWidth, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                            Text(":")
                                .foregroundColor(.secondary)
                            TextField(L("Height"), value: $newHeight, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)

                            Button(action: addNewRatio) {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
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
        .onReceive(NotificationCenter.default.publisher(for: .aspectRatiosDidChange)) { _ in
            aspectRatioModel.refreshAll()
            loadAspectRatios()
        }
    }

    // MARK: - Aspect Ratio Management

    private func loadAspectRatios() {
        aspectRatios = AspectRatioPreferences.allRatios
    }

    private var isNewRatioValid: Bool {
        guard let width = newWidth, let height = newHeight else { return false }
        guard width > 0, height > 0, width <= 100, height <= 100 else { return false }
        // Check if exact ratio already exists
        guard !aspectRatios.contains(where: { $0.width == width && $0.height == height }) else { return false }
        // Check if inverted ratio already exists
        let hasInverted = aspectRatios.contains(where: { $0.width == height && $0.height == width })
        return !hasInverted
    }

    private func addNewRatio() {
        guard let width = newWidth, let height = newHeight else { return }

        let (success, error) = AspectRatioPreferences.addRatio(width: width, height: height)
        guard success else {
            errorMessage = error ?? L("Failed to add ratio.")
            return
        }

        errorMessage = nil
        newWidth = nil
        newHeight = nil
        loadAspectRatios()
    }

    private func removeRatio(_ ratio: CustomAspectRatio) {
        AspectRatioPreferences.removeRatio(id: ratio.id)
        loadAspectRatios()
    }
}
