import SwiftUI
import ServiceManagement

struct InterfaceSettingsView: View {

    // Language
    @State private var selectedLanguageIndex: Int

    // Appearance
    @State private var accentColor: Color
    @State private var iconColor: Color
    @State private var bgColor: Color

    // Window
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(AppVisibilityPreferences.showDockIconKey)
    private var showDockIcon = AppVisibilityPreferences.defaultShowDockIcon
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false

    // Thumbnail
    @AppStorage("showFloatingThumbnail") private var showFloatingThumbnail = true
    @AppStorage("thumbnailAutoDismiss") private var thumbnailAutoDismiss: Int = 5
    @AppStorage("thumbnailStacking") private var thumbnailStacking = true
    @AppStorage("thumbnailScale") private var thumbnailScale = 0.8

    // Output (Save Location & Filename)
    @State private var savePath: String = SaveDirectoryAccess.displayPath
    @State private var sharedFilenameFormat = TokenFilenameFormat.sharedFormat
    @State private var previewKind: FilenameOutputKind = .screenshot

    init() {
        let langs = LanguageManager.availableLanguages
        let resolved = LanguageManager.shared.resolvedLanguage
        let idx = langs.firstIndex(where: { $0.code == resolved }) ?? 0
        _selectedLanguageIndex = State(initialValue: idx)
        _accentColor = State(initialValue: Color(nsColor: ToolbarLayout.accentColor))
        _iconColor = State(initialValue: Color(nsColor: ToolbarLayout.iconColor))
        _bgColor = State(initialValue: Color(nsColor: ToolbarLayout.bgColor))
    }

    var body: some View {
        Form {
            // MARK: - Interface (Language + Appearance)
            Section {
                Picker(L("Language"), selection: $selectedLanguageIndex) {
                    ForEach(0..<LanguageManager.availableLanguages.count, id: \.self) { i in
                        Text(LanguageManager.availableLanguages[i].name).tag(i)
                    }
                }
                .onChange(of: selectedLanguageIndex) { newValue in
                    let languages = LanguageManager.availableLanguages
                    guard newValue >= 0, newValue < languages.count else { return }
                    let selectedCode = languages[newValue].code
                    DispatchQueue.main.async {
                        LanguageManager.shared.currentLanguage = selectedCode
                    }
                }

                HStack {
                    ColorPicker(L("Accent color"), selection: $accentColor, supportsOpacity: false)
                        .onChange(of: accentColor) { newValue in
                            applyToolbarColorChange {
                                ToolbarLayout.saveAccentColor(NSColor(newValue))
                            }
                        }
                    Button(L("Reset")) {
                        resetAccentColor()
                    }
                    .controlSize(.small)
                }
                HStack {
                    ColorPicker(L("Icon color"), selection: $iconColor, supportsOpacity: false)
                        .onChange(of: iconColor) { newValue in
                            applyToolbarColorChange {
                                ToolbarLayout.saveIconColor(NSColor(newValue))
                            }
                        }
                    Button(L("Reset")) {
                        resetIconColor()
                    }
                    .controlSize(.small)
                }
                HStack {
                    ColorPicker(L("Background color"), selection: $bgColor, supportsOpacity: true)
                        .onChange(of: bgColor) { newValue in
                            applyToolbarColorChange {
                                ToolbarLayout.saveBgColor(NSColor(newValue))
                            }
                        }
                    Button(L("Reset")) {
                        resetBackgroundColor()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text(L("Interface"))
            }

            // MARK: - Application
            Section {
                Toggle(L("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            #if DEBUG
                            print("Failed to update login item: \(error)")
                            #endif
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("Show Dock icon"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { showDockIcon },
                            set: { newValue in
                                showDockIcon = newValue
                                (NSApp.delegate as? AppDelegate)?.updateDockIconVisibility()
                            }
                        ))
                        .labelsHidden()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("Show menu bar icon"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !hideMenuBarIcon },
                            set: { newValue in
                                hideMenuBarIcon = !newValue
                                (NSApp.delegate as? AppDelegate)?.setMenuBarIconVisible(newValue)
                            }
                        ))
                        .labelsHidden()
                    }

                    if hideMenuBarIcon {
                        Text(L("Hotkeys still work. To show the icon again, re-launch macshot."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

            } header: {
                Text(L("Application"))
            }

            // MARK: - Thumbnail
            Section {
                Toggle(L("Show quick access overlay"), isOn: $showFloatingThumbnail)
                Picker(L("Auto-dismiss after"), selection: $thumbnailAutoDismiss) {
                    Text(L("Never")).tag(0)
                    Text("5 " + L("seconds")).tag(5)
                    Text("10 " + L("seconds")).tag(10)
                    Text("15 " + L("seconds")).tag(15)
                    Text("30 " + L("seconds")).tag(30)
                    Text("45 " + L("seconds")).tag(45)
                    Text("1 " + L("minute")).tag(60)
                    Text("2 " + L("minutes")).tag(120)
                    Text("5 " + L("minutes")).tag(300)
                    Text("10 " + L("minutes")).tag(600)
                }
                Picker(L("Multiple previews"), selection: $thumbnailStacking) {
                    Text(L("Stack (keep all)")).tag(true)
                    Text(L("Replace (show only latest)")).tag(false)
                }
                HStack {
                    Text(L("Preview size"))
                    Spacer()
                    Slider(value: $thumbnailScale, in: 0.5...1.5, step: 0.1)
                        .frame(width: 300)
                    Text(scalePercentString)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Text(L("Thumbnail"))
            }

            // MARK: - Output (Save Location & Filename)
            Section {
                SaveLocationSettingsRow(
                    screenshotPath: savePath,
                    onBrowseScreenshot: browseSavePath
                )

                FilenameFormatSettingsRow(
                    format: $sharedFilenameFormat,
                    previewKind: $previewKind,
                    screenshotExtension: ImageEncoder.fileExtension
                )
                .onChange(of: sharedFilenameFormat) { newFormat in
                    TokenFilenameFormat.sharedFormat = newFormat
                }
            } header: {
                Text(L("Output"))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: normalizePickerSelections)
    }

    private func resetAccentColor() {
        ToolbarLayout.resetAccentColor()
        accentColor = Color(nsColor: ToolbarLayout.defaultAccentColor)
        postToolbarColorsDidChange()
    }

    private func resetIconColor() {
        ToolbarLayout.saveIconColor(ToolbarLayout.defaultIconColor)
        iconColor = Color(nsColor: ToolbarLayout.defaultIconColor)
        postToolbarColorsDidChange()
    }

    private func resetBackgroundColor() {
        ToolbarLayout.saveBgColor(ToolbarLayout.defaultBgColor)
        bgColor = Color(nsColor: ToolbarLayout.defaultBgColor)
        postToolbarColorsDidChange()
    }

    private func postToolbarColorsDidChange() {
        NotificationCenter.default.post(name: .toolbarColorsDidChange, object: nil)
    }

    private func applyToolbarColorChange(_ update: @escaping () -> Void) {
        DispatchQueue.main.async {
            update()
            postToolbarColorsDidChange()
        }
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

    // MARK: - Thumbnail Helpers

    private var scalePercentString: String {
        "\(Int(round(thumbnailScale * 100)))%"
    }

    private func normalizePickerSelections() {
        let langs = LanguageManager.availableLanguages
        let resolved = LanguageManager.shared.resolvedLanguage
        if let idx = langs.firstIndex(where: { $0.code == resolved }) {
            selectedLanguageIndex = idx
        }
        thumbnailAutoDismiss = normalized(
            thumbnailAutoDismiss,
            allowed: [0, 5, 10, 15, 30, 45, 60, 120, 300, 600],
            fallback: 5
        )
        TokenFilenameFormat.migrateIfNeeded()
        sharedFilenameFormat = TokenFilenameFormat.sharedFormat
    }

    private func normalized<T: Equatable>(_ value: T, allowed: [T], fallback: T) -> T {
        allowed.contains(value) ? value : fallback
    }

    // MARK: - Output Helpers

    private func browseSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveDirectoryAccess.directoryHint()
        FilePanelPresenter.begin(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            SaveDirectoryAccess.save(url: url)
            savePath = url.path
        }
    }
}
