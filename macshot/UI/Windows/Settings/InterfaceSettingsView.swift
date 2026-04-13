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
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false

    // Updates
    @AppStorage("SUEnableAutomaticChecks") private var autoUpdate = true
    @AppStorage("betaUpdatesEnabled") private var betaUpdates = false

    init() {
        let currentLang = LanguageManager.shared.currentLanguage
        let idx = LanguageManager.availableLanguages.firstIndex(where: { $0.code == currentLang }) ?? 0
        _selectedLanguageIndex = State(initialValue: idx)
        _accentColor = State(initialValue: Color(nsColor: ToolbarLayout.accentColor))
        _iconColor = State(initialValue: Color(nsColor: ToolbarLayout.iconColor))
        _bgColor = State(initialValue: Color(nsColor: ToolbarLayout.bgColor))
    }

    var body: some View {
        Form {
            // MARK: - Language
            Section {
                Picker(L("Language"), selection: $selectedLanguageIndex) {
                    ForEach(0..<LanguageManager.availableLanguages.count, id: \.self) { i in
                        Text(LanguageManager.availableLanguages[i].name).tag(i)
                    }
                }
                .onChange(of: selectedLanguageIndex) { newValue in
                    let languages = LanguageManager.availableLanguages
                    guard newValue >= 0, newValue < languages.count else { return }
                    LanguageManager.shared.currentLanguage = languages[newValue].code
                }
            } header: {
                Text(L("Language"))
            }

            // MARK: - Appearance
            Section {
                HStack {
                    ColorPicker(L("Accent color"), selection: $accentColor, supportsOpacity: false)
                        .onChange(of: accentColor) { newValue in
                            ToolbarLayout.saveAccentColor(NSColor(newValue))
                            postToolbarColorsDidChange()
                        }
                    Button(L("Reset")) {
                        resetAccentColor()
                    }
                    .controlSize(.small)
                }
                HStack {
                    ColorPicker(L("Icon color"), selection: $iconColor, supportsOpacity: false)
                        .onChange(of: iconColor) { newValue in
                            ToolbarLayout.saveIconColor(NSColor(newValue))
                            postToolbarColorsDidChange()
                        }
                    Button(L("Reset")) {
                        resetIconColor()
                    }
                    .controlSize(.small)
                }
                HStack {
                    ColorPicker(L("Background color"), selection: $bgColor, supportsOpacity: true)
                        .onChange(of: bgColor) { newValue in
                            ToolbarLayout.saveBgColor(NSColor(newValue))
                            postToolbarColorsDidChange()
                        }
                    Button(L("Reset")) {
                        resetBackgroundColor()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text(L("Appearance"))
            }

            // MARK: - Window
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

            // MARK: - Updates
            Section {
                Toggle(L("Check for updates automatically"), isOn: $autoUpdate)
                settingWithDescription(
                    title: L("Check for beta updates"),
                    description: L("Include pre-release versions in update checks.")
                ) {
                    Toggle("", isOn: $betaUpdates).labelsHidden()
                }
            } header: {
                HStack {
                    Text(L("Updates"))
                    Spacer()
                    Button(L("Check Now")) {
                        NSApp.sendAction(Selector(("checkForUpdates")), to: NSApp.delegate, from: nil)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .foregroundStyle(Color.settingsSystemAccent)
                }
            }
        }
        .formStyle(.grouped)
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
}
