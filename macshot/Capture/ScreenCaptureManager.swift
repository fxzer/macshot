import Cocoa
import ScreenCaptureKit

struct ScreenCapture {
    let screen: NSScreen
    let asset: CaptureImageAsset
}

class ScreenCaptureManager {

    enum PrewarmMode: Equatable {
        case lightweight
        case full
    }

    private static func screenDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func pair(for screen: NSScreen, in content: SCShareableContent) -> (SCDisplay, NSScreen)? {
        guard let screenID = screenDisplayID(for: screen) else { return nil }
        guard let display = content.displays.first(where: { $0.displayID == screenID }) else { return nil }
        return (display, screen)
    }

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
    private static let cacheTTL: TimeInterval = 600.0
    private static let screenshotWarmTTL: TimeInterval = 10.0

    /// Fetch shareable content, using a short-lived cache to avoid redundant enumeration.
    private static func shareableContent() async throws -> SCShareableContent {
        try await CacheManager.shared.shareableContent(cacheTTL: cacheTTL).content
    }

    /// Returns shareable content plus `SCWindow` values for exclusion. Required exclusions
    /// refresh the cache once when missing so windows created after the cache (e.g. floating
    /// thumbnails) are still excluded. Best-effort exclusions are resolved opportunistically
    /// from the current cache and never block capture on a refresh when absent.
    private static func shareableContentForCapture(
        excludingWindowNumbers: [CGWindowID],
        bestEffortExcludingWindowNumbers: [CGWindowID] = []
    ) async throws -> (SCShareableContent, [SCWindow]) {
        var perf = PerfMonitor(label: "SCContent")
        var memory = MemoryDiagnostics.makeScope(
            "SCContent",
            metadata: "excludedWindowNumbers=\(excludingWindowNumbers.count) bestEffortExcluded=\(bestEffortExcludingWindowNumbers.count)"
        )
        if excludingWindowNumbers.isEmpty, bestEffortExcludingWindowNumbers.isEmpty {
            let resolved = try await CacheManager.shared.shareableContent(cacheTTL: cacheTTL)
            let content = resolved.content
            let sourceLabel: String
            switch resolved.source {
            case .cached:
                sourceLabel = "cache HIT"
            case .inFlight:
                sourceLabel = "cache WAIT inFlight"
            case .freshFetch:
                sourceLabel = "cache MISS fetched"
            }
            perf.step("\(sourceLabel) (no exclusions)")
            memory.finish(
                "no exclusions",
                metadata: "source=\(sourceLabel) displays=\(content.displays.count) windows=\(content.windows.count)"
            )
            return (content, [])
        }

        let uniqueRequiredIDs = Array(Set(excludingWindowNumbers))
        let uniqueBestEffortIDs = Array(Set(bestEffortExcludingWindowNumbers).subtracting(uniqueRequiredIDs))

        func resolve(windowIDs: [CGWindowID], in content: SCShareableContent) -> [SCWindow] {
            windowIDs.compactMap { wid in
                content.windows.first(where: { CGWindowID($0.windowID) == wid })
            }
        }

        var content = try await shareableContent()
        var resolvedRequired = resolve(windowIDs: uniqueRequiredIDs, in: content)
        var resolvedBestEffort = resolve(windowIDs: uniqueBestEffortIDs, in: content)

        if resolvedRequired.count != uniqueRequiredIDs.count {
            // Cache is missing one or more windows to exclude — enumerate again and refresh cache.
            let missingRequiredIDs = uniqueRequiredIDs.filter { id in
                !resolvedRequired.contains(where: { CGWindowID($0.windowID) == id })
            }
            let fresh = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            await CacheManager.shared.updateCache(fresh)
            content = fresh
            resolvedRequired = resolve(windowIDs: uniqueRequiredIDs, in: content)
            resolvedBestEffort = resolve(windowIDs: uniqueBestEffortIDs, in: content)
            perf.step(
                "cache miss, refreshed required=\(resolvedRequired.count)/\(uniqueRequiredIDs.count) optional=\(resolvedBestEffort.count)/\(uniqueBestEffortIDs.count)"
            )
            memory.step(
                "cache refresh",
                metadata: "missingRequiredIDs=\(missingRequiredIDs.count) resolvedRequired=\(resolvedRequired.count)/\(uniqueRequiredIDs.count) resolvedOptional=\(resolvedBestEffort.count)/\(uniqueBestEffortIDs.count)"
            )
        } else {
            perf.step(
                "cache HIT required=\(uniqueRequiredIDs.count) optional=\(resolvedBestEffort.count)/\(uniqueBestEffortIDs.count)"
            )
            memory.step(
                "cache hit",
                metadata: "resolvedRequired=\(resolvedRequired.count)/\(uniqueRequiredIDs.count) resolvedOptional=\(resolvedBestEffort.count)/\(uniqueBestEffortIDs.count)"
            )
        }

        let resolved = resolvedRequired + resolvedBestEffort.filter { optionalWindow in
            !resolvedRequired.contains(where: { $0.windowID == optionalWindow.windowID })
        }
        memory.finish(
            "resolved exclusions",
            metadata: "displays=\(content.displays.count) windows=\(content.windows.count) resolvedRequired=\(resolvedRequired.count) resolvedOptional=\(resolvedBestEffort.count)"
        )
        return (content, resolved)
    }

    /// Pre-warm capture prerequisites ahead of an upcoming capture.
    /// - note: `.lightweight` only primes shareable content. `.full` additionally warms
    ///   the screenshot pipeline when the app has a short idle gap (e.g. menu bar click).
    static func prewarm(screen: NSScreen? = nil, mode: PrewarmMode = .full) {
        Task {
            _ = try? await shareableContent()
        }
        guard mode == .full else { return }
        warmScreenshotPipelineIfNeeded(screen: screen)
    }

    /// Signal that a real capture is starting/ending, so pipeline warmup is suppressed.
    static func setCaptureInProgress(_ value: Bool) {
        Task {
            await CacheManager.shared.setCaptureInProgress(value)
        }
    }

    /// Warm ScreenCaptureKit's screenshot path with tiny throwaway captures.
    /// This reduces the cold-start spike without holding large screenshots in memory or
    /// risking menu-window ghosts from reusing a real cached capture.
    private static func warmScreenshotPipelineIfNeeded(screen: NSScreen?) {
        Task {
            guard await CacheManager.shared.shouldStartScreenshotWarm() else {
                return
            }

            let task = Task<Void, Never> {
                defer {
                    Task { await CacheManager.shared.endScreenshotWarm() }
                }

                let t0 = CFAbsoluteTimeGetCurrent()
                guard let content = try? await shareableContent() else { return }
                guard !Task.isCancelled, !(await CacheManager.shared.isCaptureInProgress()) else { return }

                let displaysToWarm: [SCDisplay]
                if let screen, let (display, _) = pair(for: screen, in: content) {
                    displaysToWarm = [display]
                } else if let display = content.displays.first {
                    displaysToWarm = [display]
                } else {
                    displaysToWarm = []
                }

                await withTaskGroup(of: Void.self) { group in
                    for display in displaysToWarm {
                        group.addTask {
                            guard !Task.isCancelled, !(await CacheManager.shared.isCaptureInProgress()) else { return }
                            guard #available(macOS 14.0, *) else { return }
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

                guard !Task.isCancelled, !(await CacheManager.shared.isCaptureInProgress()) else { return }

                await CacheManager.shared.recordScreenshotWarmTime()
                CaptureDiagnostics.log(
                    "[macshot-perf][prewarm] screenshot pipeline warm=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms"
                )
            }

            await CacheManager.shared.setInFlightScreenshotWarm(task)
        }
    }

    static func captureAllScreens(excludingWindowNumbers: [CGWindowID] = [], completion: @escaping ([ScreenCapture]) -> Void) {
        Task {
            do {
                var perf = PerfMonitor(label: "captureAll")
                var memory = MemoryDiagnostics.makeScope(
                    "captureAll",
                    metadata: "excludedWindows=\(excludingWindowNumbers.count)"
                )
                let (content, excludedSCWindows) = try await shareableContentForCapture(excludingWindowNumbers: excludingWindowNumbers)
                perf.step("shareableContent")
                memory.step(
                    "shareableContent",
                    metadata: "displays=\(content.displays.count) excludedSCWindows=\(excludedSCWindows.count)"
                )
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
                            var displayMemory = MemoryDiagnostics.makeScope(
                                "captureAll[\(display.displayID)]",
                                metadata: "screen=\(screen.localizedName)"
                            )
                            if #available(macOS 14.0, *) {
                                // SCScreenshotManager: single-shot API, no stream overhead
                                let filter = SCContentFilter(display: display, excludingWindows: excludedSCWindows)
                                let config = SCStreamConfiguration()
                                let scale = Int(screen.backingScaleFactor)
                                config.width = display.width * scale
                                config.height = display.height * scale
                                config.showsCursor = false
                                config.captureResolution = .best
                                config.colorSpaceName = CGColorSpace.sRGB

                                guard let image = try? await SCScreenshotManager.captureImage(
                                    contentFilter: filter, configuration: config
                                ) else { return nil }
                                  CaptureDiagnostics.log(
                                      "[macshot-perf][captureAll] captureImage display=\(display.displayID) elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - taskT0) * 1000))ms"
                                  )
                                displayMemory.step(
                                    "captureImage",
                                    cgImages: [("capture", image)],
                                    metadata: "elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - taskT0) * 1000))ms"
                                )
                                // Skip expensive pixel conversion on the capture path —
                                // CoreAnimation composites the GPU-native ARGB16F image
                                // directly without CPU readback. Convert to 8-bit BGRA
                                // asynchronously after the overlay is visible for accurate
                                // color sampling and CPU-side pixel operations.
                                let capture = ScreenCapture(
                                    screen: screen,
                                    asset: makeAsset(screen: screen, image: image)
                                )
                                displayMemory.finish(
                                    "asset ready",
                                    cgImages: [("capture", image)],
                                    metadata: "displaySize=\(capture.asset.displayImage.size)"
                                )
                                return capture
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
                                let capture = ScreenCapture(
                                    screen: screen,
                                    asset: makeAsset(screen: screen, image: image)
                                )
                                displayMemory.finish(
                                    "asset ready",
                                    cgImages: [("capture", image)],
                                    metadata: "legacy path"
                                )
                                return capture
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
                perf.step("all displays captured")
                let capturedPixelSummary = captures.map { capture in
                    let image = capture.asset.displayImage
                    return "\(capture.screen.localizedName)=\(MemoryDiagnostics.format(bytes: MemoryDiagnostics.estimatedBytes(for: image)))"
                }.joined(separator: ",")
                memory.finish(
                    "all displays captured",
                    metadata: "captures=\(captures.count) \(capturedPixelSummary)"
                )

                await MainActor.run { completion(captures) }
            } catch {
                #if DEBUG
                NSLog("macshot: screen capture error: \(error.localizedDescription)")
                #endif
                await MainActor.run { completion([]) }
            }
        }
    }

    static func captureScreen(
        _ screen: NSScreen,
        excludingWindowNumbers: [CGWindowID] = [],
        bestEffortExcludingWindowNumbers: [CGWindowID] = [],
        completion: @escaping (ScreenCapture?) -> Void
    ) {
        Task {
            do {
                var perf = PerfMonitor(label: "capture1")
                var memory = MemoryDiagnostics.makeScope(
                    "capture1[\(screen.localizedName)]",
                    metadata: "excludedWindows=\(excludingWindowNumbers.count) bestEffortExcluded=\(bestEffortExcludingWindowNumbers.count)"
                )
                let (content, excludedSCWindows) = try await shareableContentForCapture(
                    excludingWindowNumbers: excludingWindowNumbers,
                    bestEffortExcludingWindowNumbers: bestEffortExcludingWindowNumbers
                )
                perf.step("shareableContent")
                memory.step(
                    "shareableContent",
                    metadata: "displays=\(content.displays.count) excludedSCWindows=\(excludedSCWindows.count)"
                )

                guard let (display, matchedScreen) = pair(for: screen, in: content) else {
                    memory.finish("screen pairing failed", metadata: "requestedScreen=\(screen.localizedName)")
                    await MainActor.run { completion(nil) }
                    return
                }

                let taskT0 = CFAbsoluteTimeGetCurrent()
                let capture: ScreenCapture?
                if #available(macOS 14.0, *) {
                    let filter = SCContentFilter(display: display, excludingWindows: excludedSCWindows)
                    let config = SCStreamConfiguration()
                    let scale = Int(matchedScreen.backingScaleFactor)
                    config.width = display.width * scale
                    config.height = display.height * scale
                    config.showsCursor = false
                    config.captureResolution = .best
                    config.colorSpaceName = CGColorSpace.sRGB

                    guard let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: config
                    ) else {
                        memory.finish("captureImage failed", metadata: "display=\(display.displayID)")
                        await MainActor.run { completion(nil) }
                        return
                    }
                    perf.step("SCScreenshotManager display=\(display.displayID)")
                    memory.step(
                        "captureImage",
                        cgImages: [("capture", image)],
                        metadata: "elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - taskT0) * 1000))ms"
                    )
                    capture = ScreenCapture(
                        screen: matchedScreen,
                        asset: makeAsset(screen: matchedScreen, image: image)
                    )
                } else {
                    let mainHeight = NSScreen.screens.first?.frame.height ?? matchedScreen.frame.height
                    let cgRect = CGRect(
                        x: matchedScreen.frame.origin.x,
                        y: mainHeight - matchedScreen.frame.origin.y - matchedScreen.frame.height,
                        width: matchedScreen.frame.width,
                        height: matchedScreen.frame.height
                    )
                    guard let image = CGWindowListCreateImage(
                        cgRect, .optionAll, kCGNullWindowID, .bestResolution
                    ) else {
                        memory.finish("legacy capture failed", metadata: "screen=\(matchedScreen.localizedName)")
                        await MainActor.run { completion(nil) }
                        return
                    }
                    capture = ScreenCapture(
                        screen: matchedScreen,
                        asset: makeAsset(screen: matchedScreen, image: image)
                    )
                }

                memory.finish(
                    "capture complete",
                    images: [("displayImage", capture?.asset.displayImage)],
                    metadata: "display=\(display.displayID) colorSamplingCached=\(capture?.asset.hasCachedColorSamplingImage == true)"
                )
                if let capture {
                    CaptureDiagnostics.log(
                        "[macshot-mem][capture1] screen=\(matchedScreen.localizedName) display=\(display.displayID) image=\(capture.asset.displayCGImage.width)x\(capture.asset.displayCGImage.height) \(MemoryDiagnostics.currentSummary())"
                    )
                }
                let deliveryReadyAt = CFAbsoluteTimeGetCurrent()
                let deliveryDisplayID = display.displayID
                CaptureDiagnostics.log(
                    "[macshot-perf][capture1] READY total=\(String(format: "%.1f", (deliveryReadyAt - taskT0) * 1000))ms display=\(deliveryDisplayID)"
                )
                let mainRunLoop = CFRunLoopGetMain()
                CFRunLoopPerformBlock(mainRunLoop, CFRunLoopMode.commonModes.rawValue) {
                    CaptureDiagnostics.log(
                        "[macshot-perf][capture1] MAIN RUNLOOP DELIVERY total=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - taskT0) * 1000))ms wait=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - deliveryReadyAt) * 1000))ms display=\(deliveryDisplayID)"
                    )
                    completion(capture)
                }
                CFRunLoopWakeUp(mainRunLoop)
            } catch {
                #if DEBUG
                NSLog("macshot: single screen capture error: \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(nil) }
            }
        }
    }

    /// Convert a CGImage (potentially ARGB16F or other GPU format) into an 8-bit BGRA bitmap
    /// in the **sRGB** color space. Using sRGB ensures that pixel values correspond directly
    /// to standard hex color codes (#RRGGBB) and that color sampling is accurate regardless
    /// of the display's native color space (e.g. Display P3).
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
            config.colorSpaceName = CGColorSpace.sRGB

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

// MARK: - Cache Manager Actor

/// Actor-protected cache for ScreenCaptureKit state.
/// Replaces NSLock usage with async-safe actor isolation.
private actor CacheManager {
    static let shared = CacheManager()

    enum ShareableContentSource {
        case cached
        case inFlight
        case freshFetch
    }

    struct ShareableContentResult {
        let content: SCShareableContent
        let source: ShareableContentSource
    }

    /// Cached shareable content to avoid repeated (slow) enumeration.
    private var cachedContent: SCShareableContent?
    private var cachedContentTime: Date = .distantPast

    /// Coalesces concurrent `shareableContent()` callers.
    private var inFlightShareableFetch: Task<SCShareableContent, Error>?

    /// Lightweight screenshot-pipeline warmup state.
    private var lastScreenshotWarmTime: Date = .distantPast
    private var inFlightScreenshotWarm: Task<Void, Never>?

    /// When true, pipeline warmup is suppressed so it doesn't compete with the real capture.
    private var captureInProgress: Bool = false

    func isCaptureInProgress() -> Bool {
        captureInProgress
    }

    func setCaptureInProgress(_ value: Bool) -> Task<Void, Never>? {
        captureInProgress = value
        let task = value ? inFlightScreenshotWarm : nil
        if value {
            task?.cancel()
        }
        return task
    }

    func shareableContent(cacheTTL: TimeInterval) async throws -> ShareableContentResult {
        if let cached = cachedContent, Date().timeIntervalSince(cachedContentTime) < cacheTTL {
            return ShareableContentResult(content: cached, source: .cached)
        }
        if let existing = inFlightShareableFetch {
            return ShareableContentResult(content: try await existing.value, source: .inFlight)
        }
        let task = Task<SCShareableContent, Error> {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            cachedContent = content
            cachedContentTime = Date()
            inFlightShareableFetch = nil
            return content
        }
        inFlightShareableFetch = task
        return ShareableContentResult(content: try await task.value, source: .freshFetch)
    }

    func updateCache(_ content: SCShareableContent) {
        cachedContent = content
        cachedContentTime = Date()
    }

    func shouldStartScreenshotWarm() -> Bool {
        guard !captureInProgress else { return false }
        let screenshotWarmTTL: TimeInterval = 10.0
        guard Date().timeIntervalSince(lastScreenshotWarmTime) >= screenshotWarmTTL else { return false }
        guard inFlightScreenshotWarm == nil else { return false }
        return true
    }

    func setInFlightScreenshotWarm(_ task: Task<Void, Never>?) {
        inFlightScreenshotWarm = task
    }

    func endScreenshotWarm() {
        inFlightScreenshotWarm = nil
    }

    func recordScreenshotWarmTime() {
        lastScreenshotWarmTime = Date()
    }
}
