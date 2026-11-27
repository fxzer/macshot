import Cocoa
import CoreGraphics

/// CoreGraphics display snapshots directly from the window server framebuffer.
/// This preserves 100% accurate native window shadows, subpixel rendering, and active states,
/// which are discarded by ScreenCaptureKit's re-compositing pipeline.
enum WindowListDisplaySnapshot {
    // CGDisplayCreateImage / CGWindowListCreateImageFromArray 均遵循 Core Foundation Create Rule，
    // 返回 +1 retained 的 CGImageRef。Swift 对 @convention(c) 函数指针看不到 CF_RETURNS_RETAINED，
    // 若直接写成 `-> CGImage?` 会按 +0 unretained 额外插入一次 CFRetain，导致每次截屏的整屏
    // CGImage 及其底层 Mach Message 像素缓冲（8 MB - 31.6 MB）永久泄漏。
    // 因此必须声明返回 `Unmanaged<CGImage>?` 并在调用点用 `takeRetainedValue()` 接管所有权。
    private typealias CGDisplayCreateImageFunc = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?
    private typealias CGWindowListCreateImageFromArrayFunc = @convention(c) (CGRect, CFArray, CGWindowImageOption) -> Unmanaged<CGImage>?

    // RTLD_DEFAULT ((void*)-2)：直接在当前进程已加载符号表中查找，无需额外的 dlopen 句柄。
    nonisolated(unsafe) private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    nonisolated private static let cgDisplayCreateImage: CGDisplayCreateImageFunc? = {
        guard let sym = dlsym(rtldDefault, "CGDisplayCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CGDisplayCreateImageFunc.self)
    }()

    nonisolated private static let cgWindowListCreateImageFromArray: CGWindowListCreateImageFromArrayFunc? = {
        guard let sym = dlsym(rtldDefault, "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(sym, to: CGWindowListCreateImageFromArrayFunc.self)
    }()

    /// 项目默认隔离到 MainActor；必须显式脱离，避免同步 WindowServer 调用阻塞输入。
    nonisolated static func captureDisplayInBackground(
        _ displayID: CGDirectDisplayID,
        excludingWindowIDs: Set<CGWindowID> = []
    ) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            dispatchPrecondition(condition: .notOnQueue(.main))
            return autoreleasepool {
                captureDisplay(displayID, excludingWindowIDs: excludingWindowIDs)
            }
        }.value
    }

    /// Capture display using CoreGraphics with window shadows preserved.
    /// Falls back to nil if CG symbols are unavailable, letting caller fallback to ScreenCaptureKit.
    nonisolated static func captureDisplay(
        _ displayID: CGDirectDisplayID,
        excludingWindowIDs: Set<CGWindowID> = []
    ) -> CGImage? {
        let bounds = CGDisplayBounds(displayID)
        let excluded = excludingWindowIDs.filter { $0 != 0 && $0 != CGWindowID.max }

        if excluded.isEmpty {
            if let fn = cgDisplayCreateImage, let img = fn(displayID)?.takeRetainedValue() {
                return img
            }
        }

        // When windows need to be excluded (e.g. macshot overlays / pins),
        // composite all on-screen windows except the excluded ones.
        if let fn = cgWindowListCreateImageFromArray,
           let arr = makeFilteredWindowArray(excluding: excluded),
           let img = fn(bounds, arr, .bestResolution)?.takeRetainedValue() {
            return img
        }

        // Only allow the unexcluded display snapshot fallback when no windows needed exclusion;
        // otherwise return nil so ScreenCaptureKit handles window exclusion safely.
        if excluded.isEmpty,
           let fn = cgDisplayCreateImage,
           let img = fn(displayID)?.takeRetainedValue() {
            return img
        }

        return nil
    }

    /// Capture a CG-coordinate region excluding the given window IDs via CoreGraphics.
    nonisolated static func captureRegion(
        _ cgRect: CGRect,
        excludingWindowIDs: Set<CGWindowID>,
        imageOption: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
    ) -> CGImage? {
        let excluded = excludingWindowIDs.filter { $0 != 0 && $0 != CGWindowID.max }
        guard !excluded.isEmpty,
              let fn = cgWindowListCreateImageFromArray,
              let arr = makeFilteredWindowArray(excluding: excluded),
              let img = fn(cgRect, arr, imageOption)?.takeRetainedValue() else {
            return nil
        }
        return img
    }

    nonisolated private static func makeFilteredWindowArray(excluding excluded: Set<CGWindowID>) -> CFArray? {
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenIDs = windowInfo.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let filteredIDs = onScreenIDs.filter { !excluded.contains($0) }

        var pointers = filteredIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        return pointers.withUnsafeMutableBufferPointer {
            CFArrayCreate(kCFAllocatorDefault, $0.baseAddress, $0.count, nil)
        }
    }
}
