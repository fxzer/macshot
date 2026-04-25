import Cocoa

@MainActor
final class FocusCoordinator {

    private var previousApp: NSRunningApplication?

    func rememberPreviousApp(_ app: NSRunningApplication?) {
        previousApp = app
    }

    func peekPreviousApp() -> NSRunningApplication? {
        previousApp
    }

    func clearPreviousApp() {
        previousApp = nil
    }

    func returnFocusIfNeeded(
        isRecordingInProgress: @escaping @MainActor () -> Bool,
        visibleWindows: @escaping @MainActor () -> [NSWindow]
    ) {
        let appToActivate = previousApp
        previousApp = nil

        DispatchQueue.main.async {
            if isRecordingInProgress() { return }

            let hasVisibleWindows = visibleWindows().contains {
                $0.isVisible && $0.styleMask.contains(.titled)
            }
            guard !hasVisibleWindows else { return }

            NSApp.setActivationPolicy(.accessory)

            if let previousApp = appToActivate,
               !previousApp.isTerminated,
               previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                Self.activateApp(previousApp)
                return
            }

            let fallbackApp = NSWorkspace.shared.runningApplications.first {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            } ?? NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current
            Self.activateApp(fallbackApp)
        }
    }

    static func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }
}
