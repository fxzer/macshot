import Cocoa
import ScreenCaptureKit

struct ScreenCapture {
    let screen: NSScreen
    let asset: CaptureImageAsset
}

class ScreenCaptureManager {

    private static func makeAsset(screen: NSScreen, image: CGImage) -> CaptureImageAsset {
        CaptureImageAsset(
            displayCGImage: image,
            pointSize: screen.frame.size
        ) { rawImage in
            convertTo8BitBGRA(rawImage)
        }
    }

    // MARK: - SCShareableContent cache

    /// Cached shareable content to avoid repeated (slow) enumeration.
    private static var cachedContent: SCShareableContent?
    private static var cachedContentTime: Date = .distantPast
    /// Cache is valid for 2 seconds — long enough to survive the hotkey→capture gap,
    /// short enough that display changes are picked up.
    private static let cacheTTL: TimeInterval = 2.0

    /// Coalesces concurrent `shareableContent()` callers (e.g. `prewarm()` Task + capture Task)
    /// so two overlapping requests only trigger one `SCShareableContent` enumeration.
    private static let shareableFetchLock = NSLock()
    private static var inFlightShareableFetch: Task<SCShareableContent, Error>?

    /// Lightweight screenshot-pipeline warmup.
    /// This does not cache user-visible screenshots; it only pays the framework startup
    /// cost ahead of time with tiny throwaway captures so the real capture path is steadier.
    private static let screenshotWarmLock = NSLock()
    private static var lastScreenshotWarmTime: Date = .distantPast
    private static var inFlightScreenshotWarm: Task<Void, Never>?
    private static let screenshotWarmTTL: TimeInterval = 10.0

    /// Fetch shareable content, using a short-lived cache to avoid redundant enumeration.
    private static func shareableContent() async throws -> SCShareableContent {
        shareableFetchLock.lock()
        if let cached = cachedContent, Date().timeIntervalSince(cachedContentTime) < cacheTTL {
            shareableFetchLock.unlock()
            return cached
        }
        if let existing = inFlightShareableFetch {
            shareableFetchLock.unlock()
            return try await existing.value
        }
        let task = Task<SCShareableContent, Error> {
            defer {
                shareableFetchLock.lock()
                inFlightShareableFetch = nil
                shareableFetchLock.unlock()
            }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            shareableFetchLock.lock()
            cachedContent = content
            cachedContentTime = Date()
            shareableFetchLock.unlock()
            return content
        }
        inFlightShareableFetch = task
        shareableFetchLock.unlock()
        return try await task.value
    }

    /// Returns shareable content plus `SCWindow` values for exclusion. Uses the cached
    /// enumeration when every excluded window ID is present; otherwise refreshes once so
    /// windows created after the cache (e.g. floating thumbnails) are visible to ScreenCaptureKit.
    private static func shareableContentForCapture(excludingWindowNumbers: [CGWindowID]) async throws -> (SCShareableContent, [SCWindow]) {
        if excludingWindowNumbers.isEmpty {
            #if DEBUG
            NSLog("[macshot] shareableContentForCapture: no exclusions, using cached content")
            #endif
            let content = try await shareableContent()
            return (content, [])
        }

        let uniqueIDs = Array(Set(excludingWindowNumbers))

        func resolve(_ content: SCShareableContent) -> [SCWindow] {
            uniqueIDs.compactMap { wid in
                content.windows.first(where: { CGWindowID($0.windowID) == wid })
            }
        }

        var content = try await shareableContent()
        var resolved = resolve(content)
        var didRefresh = false

        if resolved.count != uniqueIDs.count {
            // Cache is missing one or more windows to exclude — enumerate again and refresh cache.
            #if DEBUG
            let missingIDs = uniqueIDs.filter { id in !resolved.contains(where: { CGWindowID($0.windowID) == id }) }
            NSLog("[macshot] shareableContentForCapture: cache missing \(missingIDs.count) windows, refreshing: \(missingIDs)")
            #endif
            let fresh = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            shareableFetchLock.lock()
            cachedContent = fresh
            cachedContentTime = Date()
            shareableFetchLock.unlock()
            content = fresh
            resolved = resolve(content)
            didRefresh = true
        } else {
            #if DEBUG
            NSLog("[macshot] shareableContentForCapture: cache HIT for all \(uniqueIDs.count) excluded windows")
            #endif
        }

        // Use the already-resolved windows instead of re-filtering (SCContentFilter doesn't care about order)
        #if DEBUG
        if didRefresh {
            NSLog("[macshot] shareableContentForCapture: after refresh, resolved \(resolved.count)/\(uniqueIDs.count) windows")
        }
        #endif
        return (content, resolved)
    }

    /// Pre-warm the shareable content cache so the next capture is instant.
    /// Call this when the menu bar opens or a hotkey is pressed — before the actual capture starts.
    static func prewarm() {
        Task {
            _ = try? await shareableContent()
        }
        warmScreenshotPipelineIfNeeded()
    }

    /// Warm ScreenCaptureKit's screenshot path with tiny throwaway captures.
    /// This reduces the cold-start spike without holding large screenshots in memory or
    /// risking menu-window ghosts from reusing a real cached capture.
    private static func warmScreenshotPipelineIfNeeded() {
        guard #available(macOS 14.0, *) else { return }

        screenshotWarmLock.lock()
        if Date().timeIntervalSince(lastScreenshotWarmTime) < screenshotWarmTTL {
            screenshotWarmLock.unlock()
            return
        }
        if inFlightScreenshotWarm != nil {
            screenshotWarmLock.unlock()
            return
        }

        let task = Task<Void, Never> {
            defer {
                screenshotWarmLock.lock()
                inFlightScreenshotWarm = nil
                screenshotWarmLock.unlock()
            }

            let t0 = CFAbsoluteTimeGetCurrent()
            guard let content = try? await shareableContent() else { return }

            await withTaskGroup(of: Void.self) { group in
                for display in content.displays {
                    group.addTask {
                        let filter = SCContentFilter(display: display, excludingWindows: [])
                        let config = SCStreamConfiguration()
                        let targetWidth = min(display.width, 64)
                        let aspectRatio = display.width > 0 ? Double(display.height) / Double(display.width) : 1.0
                        let targetHeight = max(1, min(display.height, Int((Double(targetWidth) * aspectRatio).rounded())))
                        config.width = max(1, targetWidth)
                        config.height = targetHeight
                        config.showsCursor = false
                        config.captureResolution = .automatic
                        config.colorSpaceName = CGColorSpace.sRGB
                        _ = try? await SCScreenshotManager.captureImage(
                            contentFilter: filter,
                            configuration: config
                        )
                    }
                }
            }

            screenshotWarmLock.lock()
            lastScreenshotWarmTime = Date()
            screenshotWarmLock.unlock()
            NSLog("[PERF] prewarm screenshot pipeline: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        }

        inFlightScreenshotWarm = task
        screenshotWarmLock.unlock()
    }

    static func captureAllScreens(excludingWindowNumbers: [CGWindowID] = [], completion: @escaping ([ScreenCapture]) -> Void) {
        Task {
            do {
                let scT0 = CFAbsoluteTimeGetCurrent()
                let (content, excludedSCWindows) = try await shareableContentForCapture(excludingWindowNumbers: excludingWindowNumbers)
                NSLog("[PERF] shareableContentForCapture: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - scT0) * 1000))ms")
                let displays = content.displays
                let screens = NSScreen.screens

                // Build display-screen pairs
                var pairs: [(SCDisplay, NSScreen)] = []
                for display in displays {
                    if let screen = screens.first(where: { nsScreen in
                        let screenNumber = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        return screenNumber == display.displayID
                    }) {
                        pairs.append((display, screen))
                    }
                }

                // Capture all displays concurrently
                let capT0 = CFAbsoluteTimeGetCurrent()
                let captures = await withTaskGroup(of: ScreenCapture?.self, returning: [ScreenCapture].self) { group in
                    for (display, screen) in pairs {
                        group.addTask {
                            let taskT0 = CFAbsoluteTimeGetCurrent()
                            if #available(macOS 14.0, *) {
                                // SCScreenshotManager: single-shot API, no stream overhead
                                let filter = SCContentFilter(display: display, excludingWindows: excludedSCWindows)
                                let config = SCStreamConfiguration()
                                let scale = Int(screen.backingScaleFactor)
                                config.width = display.width * scale
                                config.height = display.height * scale
                                config.showsCursor = UserDefaults.standard.bool(forKey: "captureCursor")
                                config.captureResolution = .best

                                guard let image = try? await SCScreenshotManager.captureImage(
                                    contentFilter: filter, configuration: config
                                ) else { return nil }
                                NSLog("[PERF] SCScreenshotManager.captureImage(display=\(display.displayID)): \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - taskT0) * 1000))ms")
                                // Skip expensive pixel conversion on the capture path —
                                // CoreAnimation composites the GPU-native ARGB16F image
                                // directly without CPU readback. Convert to 8-bit BGRA
                                // asynchronously after the overlay is visible for accurate
                                // color sampling and CPU-side pixel operations.
                                return ScreenCapture(
                                    screen: screen,
                                    asset: makeAsset(screen: screen, image: image)
                                )
                            } else {
                                // macOS 12.3–13.x: use CGWindowListCreateImage which returns
                                // a CGImage directly — no pixel buffer format ambiguity.
                                // Convert the AppKit screen frame (bottom-left origin) to the
                                // CGDisplay coordinate space (top-left origin) for the capture rect.
                                let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
                                let cgRect = CGRect(
                                    x: screen.frame.origin.x,
                                    y: mainHeight - screen.frame.origin.y - screen.frame.height,
                                    width: screen.frame.width,
                                    height: screen.frame.height)
                                guard let image = CGWindowListCreateImage(
                                    cgRect, .optionAll, kCGNullWindowID, .bestResolution
                                ) else { return nil }
                                return ScreenCapture(
                                    screen: screen,
                                    asset: makeAsset(screen: screen, image: image)
                                )
                            }
                        }
                    }
                    var results: [ScreenCapture] = []
                    for await capture in group {
                        if let capture = capture {
                            results.append(capture)
                        }
                    }
                    return results
                }
                NSLog("[PERF] all displays captured (concurrent): \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - capT0) * 1000))ms")

                await MainActor.run { completion(captures) }
            } catch {
                #if DEBUG
                NSLog("macshot: screen capture error: \(error.localizedDescription)")
                #endif
                await MainActor.run { completion([]) }
            }
        }
    }

    /// Convert a CGImage (potentially ARGB16F or other GPU format) into an 8-bit BGRA bitmap
    /// in the **sRGB** color space. Using sRGB ensures that pixel values correspond directly
    /// to standard hex color codes (#RRGGBB) and that color sampling is accurate regardless
    /// of the display's native color space (e.g. Display P3).
    /// CoreGraphics will automatically convert sRGB images to the display profile when drawing.
    static func convertTo8BitBGRA(_ src: CGImage) -> CGImage? {
        let w = src.width
        let h = src.height
        // Force sRGB so pixel values match standard hex/RGB color codes.
        // On Display P3 monitors, the source image is in P3 — keeping P3 means
        // pixel R/G/B values don't match what users expect from sRGB hex codes.
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let result = ctx.makeImage() else { return nil }
        // Force pixel data to materialize now (not lazily on first draw).
        // Accessing the data provider triggers any deferred rendering.
        _ = result.dataProvider?.data
        return result
    }
    // MARK: - Single window capture (with transparency)

    /// Captures a single window by its CGWindowID, returning an image with transparent corners.
    /// On macOS 14+, uses `desktopIndependentWindow` filter for clean transparent background.
    /// On macOS 12–13, uses `CGWindowListCreateImage` targeting the specific window.
    static func captureWindow(windowID: CGWindowID, screen: NSScreen) async -> CGImage? {
        if #available(macOS 14.0, *) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
            guard let scWindow = content.windows.first(where: { CGWindowID($0.windowID) == windowID }) else { return nil }

            let filter: SCContentFilter
            if #available(macOS 14.2, *) {
                filter = SCContentFilter(desktopIndependentWindow: scWindow)
            } else {
                guard let display = content.displays.first(where: {
                    let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    return screenID != nil && $0.displayID == screenID!
                }) ?? content.displays.first else { return nil }
                let otherWindows = content.windows.filter { CGWindowID($0.windowID) != windowID }
                filter = SCContentFilter(display: display, excludingWindows: otherWindows)
            }

            let config = SCStreamConfiguration()
            let scale = Int(screen.backingScaleFactor)
            config.width = Int(scWindow.frame.width) * scale
            config.height = Int(scWindow.frame.height) * scale
            config.showsCursor = false
            config.captureResolution = .best

            guard let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            ) else { return nil }
            return image
        } else {
            // macOS 12.3–13.x: CGWindowListCreateImage targeting the specific window
            return CGWindowListCreateImage(
                .null, .optionIncludingWindow, windowID, .bestResolution)
        }
    }
}
