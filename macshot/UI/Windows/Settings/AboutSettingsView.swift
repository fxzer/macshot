import SwiftUI

struct AboutSettingsView: View {

    @AppStorage("SUEnableAutomaticChecks") private var autoUpdate = true
    @AppStorage("betaUpdatesEnabled") private var betaUpdates = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 12)

            // App icon
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            // App name
            Text("macshot")
                .font(.system(size: 22, weight: .bold))

            // Version
            Text(String(format: L("Version %@ (%@)"), version, build))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer().frame(height: 12)

            // Description
            Text(L("A free, open-source screenshot & screen recording tool for macOS.\nFully native — built with Swift and AppKit."))
                .font(.body)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 12)

            // Author
            Text("\(L("Made by")) sw33tLie")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            // GitHub link
            Link("github.com/sw33tLie/macshot", destination: URL(string: "https://github.com/sw33tLie/macshot")!)
                .font(.subheadline)

            Spacer().frame(height: 4)

            // License
            Text(L("Licensed under the GPLv3"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer().frame(height: 12)

            // Updates section - use Form for card style
            Form {
                Section {
                    Toggle(L("Check for updates automatically"), isOn: $autoUpdate)
                    Toggle(L("Check for beta updates"), isOn: $betaUpdates)
                } header: {
                    Text(L("Updates"))
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity)
    }
}
