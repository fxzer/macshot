import AppKit

/// 区域截图的窗口识别：在系统窗口列表里按叠放顺序做命中测试。不依赖 OverlayView，可单独编译测试。
enum WindowSnapDetector {
    struct Target: Equatable, Sendable {
        /// 窗口在遮罩视图坐标下的矩形，已裁剪到当前屏幕。
        let rect: NSRect
        let windowID: CGWindowID
        let ownerPID: pid_t
        /// 窗口在全局屏幕坐标（AppKit，主显示器左下角为原点）下的矩形。
        let screenRect: NSRect
    }

    /// 普通窗口与浮动窗口（画中画、钉图、Raycast 面板等）可以吸附。
    /// 菜单栏、程序坞、弹出菜单、通知属于系统层级：遇到它们时继续向后找真正的窗口。
    nonisolated private static let snappableLayers: Set<Int> = [
        Int(CGWindowLevelForKey(.normalWindow)),
        Int(CGWindowLevelForKey(.floatingWindow)),
    ]

    /// 完全透明的窗口看不见，常被应用留作事件接收层。
    nonisolated private static let minimumAlpha: CGFloat = 0.01
    nonisolated private static let minimumSize: CGFloat = 10

    /// 同步查询系统窗口列表并识别 `screenPoint` 下的窗口。
    /// 访问 WindowServer，本机中位约 0.4ms、忙碌时十余毫秒，只在点击瞬间调用。
    nonisolated static func target(
        atScreenPoint screenPoint: NSPoint,
        overlayWindowNumber: Int,
        overlayWindowOrigin: NSPoint,
        overlayBounds: NSRect
    ) -> Target? {
        let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return target(
            in: windowInfos,
            atScreenPoint: screenPoint,
            overlayWindowNumber: overlayWindowNumber,
            overlayWindowOrigin: overlayWindowOrigin,
            overlayBounds: overlayBounds,
            mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height
        )
    }

    /// `windowInfos` 必须按从前往后的叠放顺序排列，即 `CGWindowListCopyWindowInfo` 的返回顺序。
    /// `screenPoint` 使用 AppKit 全局屏幕坐标；`mainDisplayHeight` 是主显示器高度，
    /// 用于把 CG 窗口坐标（主显示器左上角为原点）换算到 AppKit 坐标（左下角为原点）。
    nonisolated static func target(
        in windowInfos: [[String: Any]],
        atScreenPoint screenPoint: NSPoint,
        overlayWindowNumber: Int,
        overlayWindowOrigin: NSPoint,
        overlayBounds: NSRect,
        mainDisplayHeight: CGFloat
    ) -> Target? {
        for info in windowInfos {
            guard let layer = info[kCGWindowLayer as String] as? Int, snappableLayers.contains(layer),
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  windowNumber != overlayWindowNumber
            else { continue }

            let alpha = CGFloat((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            let screenRect = NSRect(
                x: bounds["X"] ?? 0,
                y: mainDisplayHeight - (bounds["Y"] ?? 0) - (bounds["Height"] ?? 0),
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            guard alpha > minimumAlpha,
                  screenRect.width > minimumSize, screenRect.height > minimumSize,
                  screenRect.contains(screenPoint)
            else { continue }

            let localRect = NSRect(
                x: screenRect.minX - overlayWindowOrigin.x,
                y: screenRect.minY - overlayWindowOrigin.y,
                width: screenRect.width,
                height: screenRect.height
            )
            return Target(
                rect: localRect.intersection(overlayBounds),
                windowID: CGWindowID(windowNumber),
                ownerPID: ownerPID,
                screenRect: screenRect
            )
        }
        return nil
    }
}
