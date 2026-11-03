import Cocoa
import CoreGraphics

/// CoreGraphics display snapshots directly from the window server framebuffer.
/// This preserves 100% accurate native window shadows, subpixel rendering, and active states,
/// which are discarded by ScreenCaptureKit's re-compositing pipeline.
enum WindowListDisplaySnapshot {
    private typealias CGDisplayCreateImageFunc = @convention(c) (CGDirectDisplayID) -> CGImage?
    private typealias CGWindowListCreateImageFromArrayFunc = @convention(c) (CGRect, CFArray, CGWindowImageOption) -> CGImage?

    private static let cgDisplayCreateImage: CGDisplayCreateImageFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "CGDisplayCreateImage") else { return nil }
        return unsafeBitCast(sym, to: CGDisplayCreateImageFunc.self)
    }()

    private static let cgWindowListCreateImageFromArray: CGWindowListCreateImageFromArrayFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(sym, to: CGWindowListCreateImageFromArrayFunc.self)
    }()

    /// Capture display using CoreGraphics with window shadows preserved.
    /// Falls back to nil if CG symbols are unavailable, letting caller fallback to ScreenCaptureKit.
    static func captureDisplay(
        _ displayID: CGDirectDisplayID,
        excludingWindowIDs: Set<CGWindowID> = []
    ) -> CGImage? {
        let bounds = CGDisplayBounds(displayID)
        let excluded = excludingWindowIDs.filter { $0 != 0 && $0 != CGWindowID.max }

        if excluded.isEmpty {
            if let fn = cgDisplayCreateImage, let img = fn(displayID) {
                return img
            }
        }

        // When windows need to be excluded (e.g. macshot overlays / pins),
        // composite all on-screen windows except the excluded ones.
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenIDs = windowInfo.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let filteredIDs = onScreenIDs.filter { !excluded.contains($0) }

        var pointers = filteredIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        let windowArray = pointers.withUnsafeMutableBufferPointer {
            CFArrayCreate(kCFAllocatorDefault, $0.baseAddress, $0.count, nil)
        }

        if let fn = cgWindowListCreateImageFromArray, let arr = windowArray, let img = fn(bounds, arr, .bestResolution) {
            return img
        }

        if let fn = cgDisplayCreateImage, let img = fn(displayID) {
            return img
        }

        return nil
    }
}
