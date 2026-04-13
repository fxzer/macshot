import SwiftUI

extension Color {
    /// Settings links and action text should follow the current macOS system accent color.
    static var settingsSystemAccent: Color {
        Color(nsColor: .controlAccentColor)
    }
}
