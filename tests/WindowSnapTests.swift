import Cocoa

@main
struct WindowSnapTests {
    typealias Target = WindowSnapDetector.Target

    /// 与 `CGWindowListCopyWindowInfo` 一致：数值经 NSNumber 传递，按从前往后的叠放顺序排列。
    static func windowInfo(
        number: Int, layer: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
        alpha: Double = 1, pid: Int32 = 100
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowOwnerPID as String: NSNumber(value: Int(pid)),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: [
                "X": NSNumber(value: Double(x)),
                "Y": NSNumber(value: Double(y)),
                "Width": NSNumber(value: Double(width)),
                "Height": NSNumber(value: Double(height)),
            ] as NSDictionary,
        ]
    }

    @MainActor
    static func main() {
        checkStackingOrder()
        checkWindowLayers()
        checkTransparentWindows()
        checkMultiDisplayCoordinates()
        checkClippingToOverlay()
        checkStaleResultsAreDropped()
        checkMovesDuringQueryAreKept()
        checkWindowIDUpdatesIndependently()
        print("PASS: 窗口识别与悬停查询状态")
    }

    @MainActor
    static func checkStackingOrder() {
        // 本机实测数据：备忘录窗口叠在多个全屏窗口前面。
        let notes = windowInfo(number: 2512, layer: 0, x: 297, y: 187, width: 1380, height: 835)
        let antigravity = windowInfo(number: 161, layer: 0, x: 0, y: 30, width: 1920, height: 1050, pid: 200)
        let list = [notes, antigravity]
        let overlayWindowNumber = 9999
        let origin = NSPoint.zero
        let overlayBounds = NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let front = WindowSnapDetector.target(
            in: list, atScreenPoint: NSPoint(x: 987, y: 476),
            overlayWindowNumber: overlayWindowNumber, overlayWindowOrigin: origin,
            overlayBounds: overlayBounds, mainDisplayHeight: 1080)
        precondition(front?.windowID == 2512, "重叠区域没有取到最前面的窗口")
        precondition(
            front?.rect == NSRect(x: 297, y: 1080 - 187 - 835, width: 1380, height: 835),
            "命中窗口的矩形换算错误")

        let back = WindowSnapDetector.target(
            in: list, atScreenPoint: NSPoint(x: 1900, y: 1000),
            overlayWindowNumber: overlayWindowNumber, overlayWindowOrigin: origin,
            overlayBounds: overlayBounds, mainDisplayHeight: 1080)
        precondition(back?.windowID == 161, "上层窗口不包含鼠标时没有继续向后查找")

        let missed = WindowSnapDetector.target(
            in: list, atScreenPoint: NSPoint(x: 3000, y: 500),
            overlayWindowNumber: overlayWindowNumber, overlayWindowOrigin: origin,
            overlayBounds: overlayBounds, mainDisplayHeight: 1080)
        precondition(missed == nil, "鼠标不在任何窗口上时不应返回目标")
    }

    @MainActor
    static func checkWindowLayers() {
        func target(_ layer: Int, overlayWindowNumber: Int = 9999) -> Target? {
            let list = [
                windowInfo(number: 1, layer: layer, x: 500, y: 300, width: 600, height: 400, alpha: 0.9),
                windowInfo(number: 2, layer: 0, x: 0, y: 30, width: 1920, height: 1050, pid: 300),
            ]
            return WindowSnapDetector.target(
                in: list, atScreenPoint: NSPoint(x: 800, y: 600),
                overlayWindowNumber: overlayWindowNumber, overlayWindowOrigin: .zero,
                overlayBounds: NSRect(x: 0, y: 0, width: 1920, height: 1080), mainDisplayHeight: 1080)
        }

        precondition(target(3)?.windowID == 1, "浮动窗口（画中画、钉图、Raycast）没有被识别")
        precondition(target(0)?.windowID == 1, "普通窗口没有被识别")
        for layer in [24, 25, 20, 101, 102, 1000] {
            precondition(
                target(layer)?.windowID == 2,
                "层级 \(layer) 的系统界面挡住了鼠标，却没有继续向后找窗口")
        }
        precondition(
            target(0, overlayWindowNumber: 1)?.windowID == 2,
            "遮罩自身成了吸附目标，没有跳过去识别后面的窗口")
    }

    @MainActor
    static func checkTransparentWindows() {
        for alpha in [0.0, 0.005] {
            let list = [
                windowInfo(
                    number: 1, layer: 0, x: 0, y: 0, width: 1920, height: 1080, alpha: alpha),
                windowInfo(number: 2, layer: 0, x: 100, y: 100, width: 800, height: 600, pid: 300),
            ]
            let found = WindowSnapDetector.target(
                in: list, atScreenPoint: NSPoint(x: 400, y: 400),
                overlayWindowNumber: 9999, overlayWindowOrigin: .zero,
                overlayBounds: NSRect(x: 0, y: 0, width: 1920, height: 1080), mainDisplayHeight: 1080)
            precondition(found?.windowID == 2, "透明窗口（alpha=\(alpha)）挡住了后面的窗口")
        }

        let tiny = [
            windowInfo(number: 1, layer: 0, x: 395, y: 395, width: 5, height: 5),
        ]
        let none = WindowSnapDetector.target(
            in: tiny, atScreenPoint: NSPoint(x: 400, y: 400),
            overlayWindowNumber: 9999, overlayWindowOrigin: .zero,
            overlayBounds: NSRect(x: 0, y: 0, width: 1920, height: 1080), mainDisplayHeight: 1080)
        precondition(none == nil, "极小窗口成了吸附目标")
    }

    @MainActor
    static func checkMultiDisplayCoordinates() {
        // 本机实测：主显示器 1920x1080，内置显示器 CG bounds=(1920,46,1512x982)、
        // AppKit frame=(1920,52,1512,982)，访达窗口 CG bounds=(2303,100,1129x928)。
        let finder = windowInfo(number: 1251, layer: 0, x: 2303, y: 100, width: 1129, height: 928, pid: 927)
        let found = WindowSnapDetector.target(
            in: [finder], atScreenPoint: NSPoint(x: 2867, y: 516),
            overlayWindowNumber: 9999, overlayWindowOrigin: NSPoint(x: 1920, y: 52),
            overlayBounds: NSRect(x: 0, y: 0, width: 1512, height: 982), mainDisplayHeight: 1080)
        precondition(
            found?.screenRect == NSRect(x: 2303, y: 1080 - 100 - 928, width: 1129, height: 928),
            "副屏窗口的全局坐标换算错误")
        precondition(
            found?.rect == NSRect(x: 2303 - 1920, y: 52 - 52, width: 1129, height: 928),
            "副屏窗口在遮罩视图内的矩形换算错误")

        let wrongDisplay = WindowSnapDetector.target(
            in: [finder], atScreenPoint: NSPoint(x: 800, y: 500),
            overlayWindowNumber: 9999, overlayWindowOrigin: .zero,
            overlayBounds: NSRect(x: 0, y: 0, width: 1920, height: 1080), mainDisplayHeight: 1080)
        precondition(wrongDisplay == nil, "主屏遮罩识别到了副屏上的窗口")
    }

    @MainActor
    static func checkClippingToOverlay() {
        let spanning = windowInfo(number: 1, layer: 0, x: -200, y: 30, width: 1000, height: 500)
        let found = WindowSnapDetector.target(
            in: [spanning], atScreenPoint: NSPoint(x: 300, y: 800),
            overlayWindowNumber: 9999, overlayWindowOrigin: .zero,
            overlayBounds: NSRect(x: 0, y: 0, width: 1920, height: 1080), mainDisplayHeight: 1080)
        precondition(found?.rect == NSRect(x: 0, y: 550, width: 800, height: 500), "跨屏窗口没有裁剪到当前屏幕")
    }

    /// 记录每次查询的鼠标位置与完成回调，测试里按需要的顺序手动完成查询。
    @MainActor
    final class QueryRecorder {
        var queriedPoints: [NSPoint] = []
        var completions: [WindowSnapHoverTracker.Handler] = []
        var updates: [Target?] = []

        var query: WindowSnapHoverTracker.Query {
            { [weak self] point, completion in
                guard let self else { return }
                self.queriedPoints.append(point)
                self.completions.append(completion)
            }
        }

        var handler: WindowSnapHoverTracker.Handler {
            { [weak self] target in self?.updates.append(target) }
        }
    }

    @MainActor
    static func target(
        _ windowID: CGWindowID, rect: NSRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    ) -> Target {
        Target(
            rect: rect, windowID: windowID, ownerPID: 100,
            screenRect: NSRect(x: 10, y: 10, width: 100, height: 100))
    }

    @MainActor
    static func checkStaleResultsAreDropped() {
        let tracker = WindowSnapHoverTracker()
        let recorder = QueryRecorder()
        tracker.track(NSPoint(x: 1, y: 1), query: recorder.query, handler: recorder.handler)
        precondition(recorder.completions.count == 1, "首次请求没有发起查询")
        tracker.track(NSPoint(x: 9, y: 9), query: recorder.query, handler: recorder.handler)

        // 点击确认等场景会让在途查询失效：旧结果和待补查的鼠标位置都必须作废。
        precondition(!tracker.invalidate(), "重复清空报告了目标变化")
        recorder.completions[0](target(1))
        precondition(tracker.target == nil, "清空之后返回的旧查询覆盖了当前状态")
        precondition(recorder.updates.isEmpty, "被丢弃的旧查询仍触发了更新回调")
        precondition(recorder.completions.count == 1, "清空之后仍按点击前的鼠标位置发起了补查")

        tracker.track(NSPoint(x: 2, y: 2), query: recorder.query, handler: recorder.handler)
        precondition(
            recorder.completions.count == 2,
            "清空后在途标记没有释放，新查询被旧查询挂住")
        recorder.completions[1](target(2))
        precondition(tracker.target?.windowID == 2, "新查询的结果没有生效")
        precondition(recorder.updates.count == 1, "新查询没有触发更新回调")

        precondition(tracker.invalidate(), "已有目标时清空没有报告目标变化")
        precondition(tracker.target == nil, "清空后目标仍然存在")
    }

    @MainActor
    static func checkMovesDuringQueryAreKept() {
        let tracker = WindowSnapHoverTracker()
        let recorder = QueryRecorder()
        let first = NSPoint(x: 10, y: 10)
        let second = NSPoint(x: 20, y: 20)
        let latest = NSPoint(x: 30, y: 30)
        tracker.track(first, query: recorder.query, handler: recorder.handler)
        tracker.track(second, query: recorder.query, handler: recorder.handler)
        tracker.track(latest, query: recorder.query, handler: recorder.handler)
        precondition(recorder.completions.count == 1, "查询进行中并发发起了新查询")

        recorder.completions[0](nil)
        precondition(recorder.queriedPoints == [first, latest], "查询返回后没有按最新鼠标位置补查")
        precondition(recorder.completions.count == 2, "补查没有发起")

        recorder.completions[1](target(3))
        precondition(tracker.target?.windowID == 3, "补查结果没有生效")
        precondition(recorder.updates.count == 1, "补查结果没有触发更新回调")
    }

    @MainActor
    static func checkWindowIDUpdatesIndependently() {
        let tracker = WindowSnapHoverTracker()
        let recorder = QueryRecorder()
        let sameRect = NSRect(x: 0, y: 0, width: 1920, height: 1050)
        let windowIDs: [CGWindowID] = [161, 3236, 3236]
        for windowID in windowIDs {
            tracker.track(NSPoint(x: 500, y: 500), query: recorder.query, handler: recorder.handler)
            recorder.completions.last!(target(windowID, rect: sameRect))
        }
        precondition(tracker.target?.windowID == 3236, "矩形相同时窗口 ID 没有更新")
        precondition(recorder.updates.count == 2, "目标未变化时仍触发了重绘")
    }

}
