import SwiftUI

/// Main SwiftUI container for the settings window
/// Replaces the manual AppKit tab switching with SwiftUI's state-driven approach
struct SwiftUISettingsView: View {
    @State private var selectedTab: SettingsTab = .interface
    @State private var languageIndex: Int = 0

    var onHotkeyChanged: (() -> Void)?
    var onWindowClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            CustomTabBar(selectedTab: $selectedTab)

            // Tab content
            Group {
                switch selectedTab {
                case .interface:
                    InterfaceSettingsView()
                case .capture:
                    CaptureSettingsView()
                case .output:
                    OutputSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView(onHotkeyChanged: onHotkeyChanged)
                case .tools:
                    ToolsSettingsView()
                case .recording:
                    RecordingSettingsView()
                case .uploads:
                    UploadsSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            // Footer
            SettingsFooter()
        }
        .onReceive(NotificationCenter.default.publisher(for: LanguageManager.changedNotification)) { _ in
            // Force view refresh when language changes
            languageIndex += 1
        }
        .id(languageIndex) // Force view recreation on language change
    }
}

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case interface
    case capture
    case output
    case shortcuts
    case tools
    case recording
    case uploads
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interface: return L("General")
        case .capture: return L("Capture")
        case .output: return L("Output")
        case .shortcuts: return L("Shortcuts")
        case .tools: return L("Tools")
        case .recording: return L("Recording")
        case .uploads: return L("Uploads")
        case .about: return L("About")
        }
    }

    var iconName: String {
        switch self {
        case .interface: return "rectangle.3.group"
        case .capture: return "camera"
        case .output: return "arrow.down.doc"
        case .shortcuts: return "command"
        case .tools: return "wrench.and.screwdriver"
        case .recording: return "record.circle"
        case .uploads: return "cloud"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: SettingsTab

    private var tabs: [SettingsTab] { SettingsTab.allCases }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectedTab = tab }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Tab Bar Button

struct TabBarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 22, height: 22)

                Text(tab.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 50)
            .padding(.vertical, 6)
            .contentShape(Rectangle()) // Make entire area clickable
        }
        .buttonStyle(.plain)
        .background(backgroundView)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconColor: Color {
        if isSelected {
            return .accentColor
        } else if isHovered {
            return .primary
        } else {
            return .secondary
        }
    }

    private var textColor: Color {
        if isSelected {
            return .accentColor
        } else {
            return .secondary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isSelected || isHovered {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .padding(.horizontal, 1)
                .padding(.vertical, 3)
        }
    }

    private var backgroundColor: Color {
        // Use system adaptive colors for light/dark mode
        if colorScheme == .dark {
            // Dark mode: lighter gray for visibility
            return Color(red: 0.25, green: 0.25, blue: 0.25)
        } else {
            // Light mode: more visible gray for better contrast
            return Color(red: 0.8, green: 0.8, blue: 0.8)
        }
    }
}

// MARK: - Settings Footer

struct SettingsFooter: View {
    var body: some View {
        HStack {
            Text("\(L("Made by")) sw33tLie")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { openGitHub() }) {
                Text("github.com/sw33tLie/macshot")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func openGitHub() {
        if let url = URL(string: "https://github.com/sw33tLie/macshot") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    SwiftUISettingsView()
        .frame(width: 540, height: 660)
}
