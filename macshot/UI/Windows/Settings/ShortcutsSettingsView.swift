import SwiftUI
import Combine
import Carbon

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
            HotkeyManager.saveHotkey(for: slot, keyCode: keyCode, modifiers: carbonMods)
            self.displayStrings[slot] = HotkeyManager.displayString(for: slot)
            self.stopRecording()
            self.onHotkeyChanged?()
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
        HotkeyManager.saveHotkey(for: slot, keyCode: slot.defaultKeyCode, modifiers: slot.defaultModifiers)
        displayStrings[slot] = HotkeyManager.displayString(for: slot)
        onHotkeyChanged?()
    }

    func stopRecording() {
        recordingSlot = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
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

            ToolShortcutManager.setKey(char, for: action)
            self.displayStrings[action] = ToolShortcutManager.displayString(for: action)
            self.stopRecording()
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
        ToolShortcutManager.setKey(action.defaultKey, for: action)
        displayStrings[action] = ToolShortcutManager.displayString(for: action)
    }

    func stopRecording() {
        recordingAction = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}

// MARK: - View

struct ShortcutsSettingsView: View {
    @StateObject private var hotkeyModel = HotkeyRecordingModel()
    @StateObject private var toolModel = ToolShortcutRecordingModel()
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
                Text(L("Keyboard Shortcuts"))
            } footer: {
                Text(L("Click to record shortcut. Esc to cancel, ⌫ to clear. Right-click to reset."))
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
                Text(L("Overlay / Editor Shortcuts"))
            } footer: {
                Text(L("Press a single key to assign. These work when the overlay or editor is active."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hotkeyModel.onHotkeyChanged = onHotkeyChanged
        }
    }
}
