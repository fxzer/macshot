import SwiftUI
import Combine
import Carbon

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
        displayStrings[slot] = L("Waiting...")

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
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
        if let slot = recordingSlot {
            displayStrings[slot] = HotkeyManager.displayString(for: slot)
        }
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
        displayStrings[action] = "…"

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 { // Escape — cancel
                self.stopRecording()
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
        if let action = recordingAction {
            displayStrings[action] = ToolShortcutManager.displayString(for: action)
        }
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
                        Text(hotkeyModel.displayStrings[slot] ?? L("None"))
                            .foregroundColor(hotkeyModel.recordingSlot == slot ? .orange : .secondary)
                            .frame(minWidth: 80)
                            .monospacedDigit()
                        Button(hotkeyModel.recordingSlot == slot ? L("Press keys...") : L("Set")) {
                            if hotkeyModel.recordingSlot == slot {
                                hotkeyModel.stopRecording()
                            } else {
                                toolModel.stopRecording()
                                hotkeyModel.startRecording(slot: slot)
                            }
                        }
                        .frame(width: 90)
                        Button {
                            hotkeyModel.clearShortcut(slot: slot)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("None"))
                        Button {
                            hotkeyModel.resetShortcut(slot: slot)
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("Reset to default"))
                    }
                }
            } header: {
                Text(L("Keyboard Shortcuts"))
            } footer: {
                Text(L("Click \"Set\" and press a key combination with at least one modifier (⌘, ⌥, ⌃, ⇧) to set a shortcut."))
            }

            // MARK: - Overlay / Editor Tool Shortcuts
            Section {
                ForEach(ToolShortcutManager.Action.allCases, id: \.rawValue) { action in
                    HStack {
                        Text(action.label)
                        Spacer()
                        Text(toolModel.displayStrings[action] ?? L("None"))
                            .foregroundColor(toolModel.recordingAction == action ? .orange : .secondary)
                            .frame(minWidth: 50)
                        Button(toolModel.recordingAction == action ? L("Press...") : L("Set")) {
                            if toolModel.recordingAction == action {
                                toolModel.stopRecording()
                            } else {
                                hotkeyModel.stopRecording()
                                toolModel.startRecording(action: action)
                            }
                        }
                        .frame(width: 70)
                        Button {
                            toolModel.clearShortcut(action: action)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("None"))
                        Button {
                            toolModel.resetShortcut(action: action)
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("Reset to default"))
                    }
                }
            } header: {
                Text(L("Overlay / Editor Shortcuts"))
            } footer: {
                Text(L("Press a single key to assign it as the shortcut for that tool. These work when the overlay or editor is active."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hotkeyModel.onHotkeyChanged = onHotkeyChanged
        }
    }
}
