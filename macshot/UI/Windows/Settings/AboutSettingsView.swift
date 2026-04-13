import SwiftUI

struct AboutSettingsView: View {

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
            Text("\(L("Made by")) fxzer")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            // GitHub link
            Link("github.com/fxzer/macshot", destination: URL(string: "https://github.com/fxzer/macshot")!)
                .font(.subheadline)
                .foregroundStyle(Color.settingsSystemAccent)

            Spacer().frame(height: 4)

            // License
            Text(L("Licensed under the GPLv3"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
