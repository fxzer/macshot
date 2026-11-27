import Cocoa

// 只替换控制器的数据依赖；窗口呈现、绘制、提交和焦点路由直接运行生产实现。
@MainActor
final class OverlayWindowController {
    var isDismissed = false
    var presentationStartedAt: CFAbsoluteTime = 0
    var onInputReady: (() -> Void)?
    var captureAsset: NSObject?
    var overlayWindow: OverlayWindow?
    var overlayView: PresentationTestView?
}

@MainActor
final class PresentationTestView: NSView {
    var screenshotImage: NSImage?
    var suppressBackdropUntilCapture = true
    var drewCapture = false
    var hoverRefreshCount = 0
    var hasEmittedFirstFrame: Bool { drewCapture }

    func refreshWindowSnapHoverAtMouseLocation() { hoverRefreshCount += 1 }

    override func draw(_ dirtyRect: NSRect) {
        if screenshotImage != nil && !suppressBackdropUntilCapture {
            NSColor.red.setFill()
            bounds.fill()
            drewCapture = true
        }
    }
}

@MainActor
final class PresentationTestWindow: OverlayWindow {
    var promoted = false

    override func makeKeyAndOrderFront(_ sender: Any?) {
        precondition((contentView as? PresentationTestView)?.screenshotImage != nil,
                     "截图数据就绪前接管了键盘焦点")
        promoted = true
        super.makeKeyAndOrderFront(sender)
    }
}

enum CaptureDiagnostics {
    static func log(_ message: String) {}
}

@main
struct OverlayPresentationTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let countdown = CaptureCountdownPanel(
            contentRect: NSRect(x: 20, y: 20, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        countdown.isReleasedWhenClosed = false
        countdown.hidesOnDeactivate = false
        countdown.ignoresMouseEvents = true
        countdown.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousPID,
                     "倒计时激活了应用，导致目标窗口提前隐藏")
        precondition(countdown.isKeyWindow && !countdown.canBecomeMain,
                     "倒计时未在保持原应用激活的同时接收键盘")
        countdown.orderOut(nil)
        countdown.close()
        print("PASS: 倒计时保留原应用激活状态并接收键盘")
        let window = PresentationTestWindow(
            contentRect: NSRect(x: 20, y: 20, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        let view = PresentationTestView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        window.contentView = view
        let controller = OverlayWindowController()
        controller.overlayWindow = window
        controller.overlayView = view

        controller.presentWindow(window, acceptInputIfReady: false)
        controller.makeKey()
        precondition(!view.drewCapture && window.ignoresMouseEvents && !window.promoted,
                     "透明占位窗口提前接管输入")
        precondition(view.hoverRefreshCount == 0, "输入未就绪就发起了窗口识别")
        print("PASS: 透明占位阶段不接管输入")

        controller.captureAsset = NSObject()
        view.screenshotImage = NSImage(size: view.bounds.size)
        controller.makeKey()
        precondition(!view.drewCapture && window.ignoresMouseEvents,
                     "背景抑制阶段提前接管输入")
        precondition(view.hoverRefreshCount == 0, "背景未就绪就发起了窗口识别")
        print("PASS: 截图数据存在但尚未就绪时不接管输入")

        view.suppressBackdropUntilCapture = false
        view.needsDisplay = true
        controller.makeKey()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(view.drewCapture && !window.ignoresMouseEvents,
                     "截图背景或输入未就绪")
        precondition(window.promoted && window.isKeyWindow, "截图就绪后未接管键盘焦点")
        precondition(view.hoverRefreshCount == 1, "接管输入时没有识别当前鼠标下的窗口")
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousPID,
                     "区域截图激活了应用，导致目标窗口提前隐藏")
        print("PASS: 截图就绪后接管输入，保持原应用激活")

        controller.isDismissed = true
        window.promoted = false
        window.ignoresMouseEvents = true
        controller.makeKey()
        precondition(!window.promoted && window.ignoresMouseEvents, "已关闭的会话重新抢占焦点")
        precondition(view.hoverRefreshCount == 1, "已关闭会话仍发起了窗口识别")
        print("PASS: 已关闭会话不重新接管输入")
        window.orderOut(nil)
        window.close()
    }
}
