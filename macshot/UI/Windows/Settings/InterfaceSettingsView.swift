import SwiftUI
import ServiceManagement

struct InterfaceSettingsView: View {

    // Language
    @State private var selectedLanguageIndex: Int

    // Appearance
    @State private var accentColor: Color
    @State private var iconColor: Color

    // Window
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false

    init() {
        let currentLang = LanguageManager.shared.currentLanguage
        let idx = LanguageManager.availableLanguages.firstIndex(where: { $0.code == currentLang }) ?? 0
        _selectedLanguageIndex = State(initialValue: idx)
        _accentColor = State(initialValue: Color(nsColor: ToolbarLayout.accentColor))
        _iconColor = State(initialValue: Color(nsColor: ToolbarLayout.iconColor))
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
            } footer: {
                Text(L("Changes take effect immediately."))
            }

            // MARK: - Appearance
            Section {
                ColorPicker(L("Accent color"), selection: $accentColor, supportsOpacity: false)
                    .onChange(of: accentColor) { newValue in
                        ToolbarLayout.saveAccentColor(NSColor(newValue))
                        NotificationCenter.default.post(name: .toolbarColorsDidChange, object: nil)
                    }
                ColorPicker(L("Icon color"), selection: $iconColor, supportsOpacity: false)
                    .onChange(of: iconColor) { newValue in
                        ToolbarLayout.saveIconColor(NSColor(newValue))
                        NotificationCenter.default.post(name: .toolbarColorsDidChange, object: nil)
                    }
                Button(L("Reset")) {
                    ToolbarLayout.resetColors()
                    accentColor = Color(nsColor: ToolbarLayout.defaultAccentColor)
                    iconColor = Color(nsColor: ToolbarLayout.defaultIconColor)
                    NotificationCenter.default.post(name: .toolbarColorsDidChange, object: nil)
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
                Toggle(L("Hide menu bar icon"), isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) { newValue in
                        (NSApp.delegate as? AppDelegate)?.setMenuBarIconVisible(!newValue)
                    }
            } header: {
                Text(L("Window"))
            } footer: {
                Text(L("Hotkeys still work. To show the icon again, re-launch macshot."))
            }
        }
        .formStyle(.grouped)
    }
}
