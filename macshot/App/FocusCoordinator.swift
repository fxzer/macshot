import Cocoa

@MainActor
final class FocusCoordinator {

    private var previousApp: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?

    init() {
        // Track the last active third-party application so we can return focus reliably
        // even when closing editor/preferences windows where previousApp was already cleared.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = front
        }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.lastExternalApp = app
        }
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func rememberPreviousApp(_ app: NSRunningApplication?) {
        previousApp = app
        if let app = app, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = app
        }
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

            if let app = appToActivate,
               !app.isTerminated,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                Self.activateApp(app)
                return
            }

            if let extApp = self.lastExternalApp,
               !extApp.isTerminated,
               extApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                Self.activateApp(extApp)
                return
            }

            let fallbackApp = NSWorkspace.shared.runningApplications.first {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            if let fallback = fallbackApp, !fallback.isTerminated {
                Self.activateApp(fallback)
            } else {
                NSApp.hide(nil)
            }
        }
    }

    static func activateApp(_ app: NSRunningApplication) {
        app.activate(options: .activateIgnoringOtherApps)
    }
}
