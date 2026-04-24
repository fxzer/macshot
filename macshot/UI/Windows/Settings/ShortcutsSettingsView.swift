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
                            onClear()
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
                shortcut: key.uppercased(),
                existingAction: conflictAction.label,
                newAction: action.label
            )
            guard shouldReplace else { return }
            ToolShortcutManager.setKey("", for: conflictAction)
        }

        if let conflictRatio = AspectRatioShortcutManager.conflictingRatio(for: key, excluding: nil) {
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: key.uppercased(),
                existingAction: conflictRatio.displayName,
                newAction: action.label
            )
            guard shouldReplace else { return }
            AspectRatioShortcutManager.setKey("", for: conflictRatio.id)
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
    private let ratioInputControlHeight: CGFloat = 24

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
                            TextField(L("Width"), value: $newWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 74)
                                .frame(height: ratioInputControlHeight)
                            Text(":")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 10, height: ratioInputControlHeight, alignment: .center)
                                .offset(y: -0.5)
                            TextField(L("Height"), value: $newHeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 74)
                                .frame(height: ratioInputControlHeight)

                            Button(action: addNewRatio) {
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
        guard let width = newWidth, let height = newHeight else { return false }
        return AspectRatioPreferences.validationError(width: width, height: height) == nil
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
        let (success, error) = AspectRatioPreferences.removeRatio(id: ratio.id)
        guard success else {
            errorMessage = error
            return
        }

        errorMessage = nil
        loadAspectRatios()
    }
}
