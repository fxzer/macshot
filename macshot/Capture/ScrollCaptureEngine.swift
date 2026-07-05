import Cocoa
import ScreenCaptureKit
import Vision

// MARK: - ScrollCaptureEngine

/// Scroll capture engine:
///
/// - **`CGWindowListCreateImage`** for on-demand frame capture — each grab is a
///   complete, compositor-finished snapshot. No stream management, no stale frames.
/// - **Raw pixel byte comparison** — two consecutive identical pixel buffers
///   = content has truly stopped rendering. Zero tolerance, no false positives.
/// - **Timer-driven `captureAndCompare`** on a dedicated serial queue — consistent
///   timing, no main-thread contention.
/// - **Incremental stitching** — new content is merged into `mergedImage` immediately
///   after each match, keeping memory bounded (no storing all raw strips).
/// - **Vision-only offset detection** — `VNTranslationalImageRegistrationRequest`
///   for pixel-precise scroll offset measurement.
/// - **`matchNotFoundCount`** tracking — surfaces errors to the user via callbacks
///   instead of silently failing.
/// - **Programmatic scrolling** via `CGEventCreateScrollWheelEvent2`.
/// - **Frozen header detection** — identifies sticky headers and excludes from stitching.
/// - **Scrollbar exclusion** — auto-detects scrollbar width, excludes from comparisons.
/// - **Max height: 30,000 pixels** (configurable via UserDefaults).
@MainActor
final class ScrollCaptureEngine {

    // MARK: - Public state

    private(set) var stripCount: Int = 0
    private(set) var stitchedImage: CGImage?
    private(set) var stitchedPixelSize: CGSize = .zero
    private(set) var isActive: Bool = false
    private(set) var frozenTopHeight: CGFloat = 0

    /// Current estimated total height of the final image (points).
    var estimatedTotalHeight: CGFloat {
        guard let merged = mergedImage else { return 0 }
        return CGFloat(merged.height) / backingScale
    }

    // MARK: - Callbacks

    var onStripAdded:  ((Int) -> Void)?
    var onSessionDone: ((NSImage?) -> Void)?
    var onAutoScrollStarted: (() -> Void)?
    var onPreviewUpdated: ((NSImage) -> Void)?

    // MARK: - Config

    var excludedWindowIDs: [CGWindowID] = []

    // MARK: - Settings

    private var autoScrollEnabled: Bool = false
    private var autoScrollSpeed: Int = 3
    private var maxScrollHeight: Int = 30000
    private var frozenDetectionEnabled: Bool = true

    // MARK: - Private

    private let captureRect: NSRect
    private let screen: NSScreen
    private let backingScale: CGFloat

    // Dedicated serial queue for capture-and-compare (off main thread)
    private let captureQueue = DispatchQueue(label: "macshot.scrollcapture", qos: .userInitiated)

    // Frame state
    private var shotA: CGImage?          // previous frame
    private var shotB: CGImage?          // current frame
    private var mergedImage: CGImage?    // accumulated stitched result
    private var headerHeight: Int = 0    // frozen header height in pixels
    private var headerDetectionDone: Bool = false
    private var headerDetectionSamples: Int = 0

    // Scrollbar exclusion
    private var rightMarginPx: Int = 0
    private var rightMarginDetected: Bool = false

    // Match tracking
    private var matchNotFoundCount: Int = 0
    private let maxMatchNotFound: Int = 8  // stop after 8 consecutive failures
    private var didReportFirstMatch: Bool = false
    private var hasScrolledOnce: Bool = false
    private var consecutiveZeroShifts: Int = 0
    private let maxZeroShiftsBeforeStop: Int = 6

    // Scroll monitors (for manual scroll).
    // `nonisolated(unsafe)`: written only on MainActor; deinit (last reference
    // release) is the only off-main access, and ARC guarantees no concurrent
    // writer at that point. Lets deinit tear down leaked monitors/tasks.
    private nonisolated(unsafe) var scrollMonitorGlobal: Any?
    private nonisolated(unsafe) var scrollMonitorLocal:  Any?

    /// Defensive cleanup if the engine is released without an explicit
    /// stopSession()/cancelSession() (e.g. overlay dismissed mid-capture).
    /// Without this, global NSEvent monitors leak (system resource) and the
    /// autoScrollTask keeps posting CGEvents to whatever is under the cursor.
    deinit {
        autoScrollTask?.cancel()
        settlementTimer?.invalidate()
        pendingCaptureTask?.cancel()
        if let m = scrollMonitorGlobal { NSEvent.removeMonitor(m) }
        if let m = scrollMonitorLocal { NSEvent.removeMonitor(m) }
    }

    // Auto-scroll.
    // `nonisolated(unsafe)` for the Task/Timer so deinit can cancel them.
    private(set) var autoScrollActive: Bool = false
    private nonisolated(unsafe) var autoScrollTask: Task<Void, Never>?

    // Manual scroll throttle
    private let manualCaptureInterval: TimeInterval = 0.15
    private var lastCaptureTime: TimeInterval = 0
    private nonisolated(unsafe) var pendingCaptureTask: Task<Void, Never>?
    private nonisolated(unsafe) var settlementTimer: Timer?
    private let settlementInterval: TimeInterval = 0.25

    // Guard: only one capture at a time
    private var isCapturing: Bool = false

    // Target app for scroll events
    private var targetAppPID: pid_t = 0

    // CGWindowList capture config
    private var targetWindowID: CGWindowID = kCGNullWindowID
    private var captureRectCG: CGRect = .zero  // CG coordinates (top-left origin)

    // MARK: - Init

    init(captureRect: NSRect, screen: NSScreen) {
        self.captureRect = captureRect
        self.screen      = screen
        self.backingScale = screen.backingScaleFactor
    }

    // MARK: - Session

    func startSession() async {
        guard !isActive else { return }

        let ud = UserDefaults.standard
        autoScrollEnabled = ud.object(forKey: "scrollAutoScrollEnabled") as? Bool ?? false
        autoScrollSpeed = ud.object(forKey: "scrollAutoScrollSpeed") as? Int ?? 3
        maxScrollHeight = ud.object(forKey: "scrollMaxHeight") as? Int ?? 30000
        frozenDetectionEnabled = ud.object(forKey: "scrollFrozenDetection") as? Bool ?? true

        // Convert AppKit coords to CG coords (top-left origin) for CGWindowListCreateImage
        let primaryScreenH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        captureRectCG = CGRect(
            x: captureRect.origin.x,
            y: primaryScreenH - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )

        // Find the target window under the capture region
        resolveTargetWindow()
        resolveTargetApp()

        // Capture first settled frame
        guard let firstFrame = await captureSettledFrame() else {
            onSessionDone?(nil)
            return
        }

        isActive = true
        shotA = nil
        shotB = nil
        mergedImage = firstFrame
        headerHeight = 0
        headerDetectionDone = false
        headerDetectionSamples = 0
        rightMarginPx = 0
        rightMarginDetected = false
        matchNotFoundCount = 0
        didReportFirstMatch = false
        hasScrolledOnce = false
        consecutiveZeroShifts = 0
        frozenTopHeight = 0
        stripCount = 1

        stitchedImage = firstFrame
        stitchedPixelSize = CGSize(width: CGFloat(firstFrame.width), height: CGFloat(firstFrame.height))
        emitPreview()
        onStripAdded?(stripCount)

        if autoScrollEnabled {
            startAutoScroll()
        } else {
            startManualScrollMonitors()
        }
    }

    func stopSession() {
        guard isActive else { return }
        isActive = false

        autoScrollTask?.cancel(); autoScrollTask = nil
        settlementTimer?.invalidate(); settlementTimer = nil
        pendingCaptureTask?.cancel(); pendingCaptureTask = nil
        if let m = scrollMonitorGlobal { NSEvent.removeMonitor(m); scrollMonitorGlobal = nil }
        if let m = scrollMonitorLocal  { NSEvent.removeMonitor(m); scrollMonitorLocal  = nil }
        autoScrollActive = false

        // Deliver final image
        let finalImage: NSImage?
        if let cg = mergedImage {
            let ptSize = CGSize(width: CGFloat(cg.width) / backingScale,
                                height: CGFloat(cg.height) / backingScale)
            finalImage = NSImage(cgImage: cg, size: ptSize)
        } else {
            finalImage = nil
        }
        onSessionDone?(finalImage)
    }

    func cancelSession() {
        guard isActive else { return }
        isActive = false

        autoScrollTask?.cancel(); autoScrollTask = nil
        settlementTimer?.invalidate(); settlementTimer = nil
        pendingCaptureTask?.cancel(); pendingCaptureTask = nil
        if let m = scrollMonitorGlobal { NSEvent.removeMonitor(m); scrollMonitorGlobal = nil }
        if let m = scrollMonitorLocal  { NSEvent.removeMonitor(m); scrollMonitorLocal  = nil }
        autoScrollActive = false
    }

    // MARK: - Target window/app management

    /// Finds the window ID under the capture region center for targeted capture.
    private func resolveTargetWindow() {
        let centerX = captureRectCG.midX
        let centerY = captureRectCG.midY

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let excluded = Set(excludedWindowIDs)
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let winID = info[kCGWindowNumber as String] as? Int,
                  !excluded.contains(CGWindowID(winID))
            else { continue }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            let cgRect = CGRect(x: x, y: y, width: w, height: h)

            if cgRect.contains(CGPoint(x: centerX, y: centerY)) {
                targetWindowID = CGWindowID(winID)
                return
            }
        }
    }

    private func resolveTargetApp() {
        let centerX = captureRectCG.midX
        let centerY = captureRectCG.midY

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let excluded = Set(excludedWindowIDs)
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let winID = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  !excluded.contains(CGWindowID(winID))
            else { continue }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            let cgRect = CGRect(x: x, y: y, width: w, height: h)

            if cgRect.contains(CGPoint(x: centerX, y: centerY)) {
                targetAppPID = pid
                return
            }
        }
    }

    private func activateTargetApp() {
        guard targetAppPID != 0 else { return }
        NSRunningApplication(processIdentifier: targetAppPID)?.activate(options: [])
    }

    // MARK: - Frame capture via CGWindowListCreateImage

    /// Captures the screen region using CGWindowListCreateImage.
    /// Returns a complete, compositor-finished snapshot — no stream management needed.
    private func captureFrame() -> CGImage? {
        let excludeSet = Set(excludedWindowIDs)
        let listOption: CGWindowListOption = [.optionOnScreenBelowWindow]
        let windowID = excludeSet.isEmpty ? kCGNullWindowID : (excludeSet.first ?? kCGNullWindowID)

        let imageOption: CGWindowImageOption = [.boundsIgnoreFraming]

        guard let image = CGWindowListCreateImage(
            captureRectCG, listOption, windowID, imageOption
        ) else { return nil }

        return image
    }

    /// Captures a settled frame: grabs frames until two consecutive raw pixel buffers
    /// match byte-for-byte. Used for initial capture and manual scroll mode.
    private func captureSettledFrame() async -> CGImage? {
        var previousPixelData: Data? = nil
        var previousCG: CGImage? = nil
        var waitNs: UInt64 = 10_000_000  // 10ms

        for _ in 0..<30 {
            guard let cg = captureFrame() else {
                try? await Task.sleep(nanoseconds: 30_000_000)
                continue
            }

            let pixelData = await extractPixelData(from: cg)
            guard let currentData = pixelData else {
                try? await Task.sleep(nanoseconds: waitNs)
                waitNs = min(waitNs * 3 / 2, 80_000_000)
                continue
            }

            if let prevData = previousPixelData, currentData == prevData {
                return cg
            }

            previousPixelData = currentData
            previousCG = cg
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        return previousCG
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        autoScrollActive = true
        onAutoScrollStarted?()

        let primaryScreenH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cursorX = captureRect.midX
        let cursorY = primaryScreenH - captureRect.midY
        CGWarpMouseCursorPosition(CGPoint(x: cursorX, y: cursorY))

        activateTargetApp()

        // autoScrollSpeed is one of 1=Slow, 2=Medium, 3=Fast (default), 4=Very fast.
        // linesPerTick stays at 1 for Slow/Medium/Fast (burstCount already scales the
        // rate); only Very fast doubles linesPerTick. All legal cases are listed
        // explicitly so the default branch only handles unexpected values.
        let linesPerTick: Int32
        switch autoScrollSpeed {
        case 1, 2, 3: linesPerTick = 1
        case 4:       linesPerTick = 2
        default:      linesPerTick = 1
        }

        let burstCount: Int
        switch autoScrollSpeed {
        case 1: burstCount = 1
        case 2: burstCount = 2
        case 3: burstCount = 3
        case 4: burstCount = 4
        default: burstCount = 3
        }

        autoScrollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self, self.isActive, self.autoScrollActive else { return }
            await self.autoScrollLoop(linesPerTick: linesPerTick, burstCount: burstCount)
        }
    }

    /// Core auto-scroll loop: scroll → captureAndCompare → repeat.
    private func autoScrollLoop(linesPerTick: Int32, burstCount: Int) async {
        while isActive && autoScrollActive {
            // Post scroll event(s)
            for _ in 0..<burstCount {
                if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                       wheel1: linesPerTick, wheel2: 0, wheel3: 0) {
                    event.post(tap: .cghidEventTap)
                }
            }

            // captureAndCompare: settle, capture, compare, stitch
            let success = await captureAndCompare()

            if !success {
                matchNotFoundCount += 1
                if matchNotFoundCount >= maxMatchNotFound {
                    stopSession()
                    return
                }
            } else {
                matchNotFoundCount = 0
            }

            // Check max height
            if let merged = mergedImage, maxScrollHeight > 0 {
                if merged.height >= maxScrollHeight {
                    stopSession()
                    return
                }
            }

            // Small breathing room
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// The core capture-and-compare cycle.
    /// Waits for pixel-perfect settlement via raw pixel byte comparison, then computes
    /// the scroll offset via Vision and merges new content into the accumulated image.
    /// Returns true if a match was found, false if no shift detected.
    private func captureAndCompare() async -> Bool {
        // Initial delay for scroll animation to begin
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // Wait for settlement: poll frames until two consecutive pixel buffers match
        var previousPixelData: Data? = nil
        var settledCG: CGImage? = nil
        var waitNs: UInt64 = 12_000_000

        for _ in 0..<30 {
            guard isActive else { return false }

            guard let cg = captureFrame() else {
                try? await Task.sleep(nanoseconds: 30_000_000)
                continue
            }

            let pixelData = await extractPixelData(from: cg)
            guard let currentData = pixelData else {
                try? await Task.sleep(nanoseconds: waitNs)
                waitNs = min(waitNs * 3 / 2, 80_000_000)
                continue
            }

            if let prevData = previousPixelData, currentData == prevData {
                settledCG = cg
                break
            }

            previousPixelData = currentData
            try? await Task.sleep(nanoseconds: waitNs)
            waitNs = min(waitNs * 3 / 2, 80_000_000)
        }

        guard let currentFrame = settledCG else { return false }
        guard let previousFrame = shotA ?? mergedImage?.cropping(to: CGRect(
            x: 0, y: 0, width: currentFrame.width, height: currentFrame.height
        )) else {
            shotA = currentFrame
            return false
        }

        // Scrollbar detection (once)
        if !rightMarginDetected {
            await detectRightMargin(current: currentFrame, previous: previousFrame)
        }

        // Compute offset via Vision
        guard let offset = await visionShift(current: currentFrame, previous: previousFrame) else {
            shotA = currentFrame
            consecutiveZeroShifts += 1
            if hasScrolledOnce && consecutiveZeroShifts >= maxZeroShiftsBeforeStop {
                stopSession()
            }
            return false
        }

        let offsetPx = Int(round(offset))
        guard offsetPx > 0 else {
            shotA = currentFrame
            return false
        }

        // Need minimum shift to avoid noise
        let minShift = currentFrame.height / 10
        if offsetPx < minShift {
            // Don't update shotA — let shifts accumulate
            return false
        }

        consecutiveZeroShifts = 0
        hasScrolledOnce = true

        // Header detection (first few frames)
        if frozenDetectionEnabled && !headerDetectionDone {
            await detectHeader(current: currentFrame, previous: previousFrame, shiftPx: offsetPx)
        }

        // Incremental stitch: merge new content into mergedImage
        await mergeNewContent(currentFrame: currentFrame, offsetPx: offsetPx)

        shotA = currentFrame
        stripCount += 1
        didReportFirstMatch = true

        emitPreview()
        onStripAdded?(stripCount)

        return true
    }

    /// Merges the newly-scrolled content from `currentFrame` into `mergedImage`.
    /// The new content (bottom `offsetPx` rows of the frame) is placed at y=0
    /// (image bottom / page bottom), and the existing accumulated image is
    /// shifted above it at y=offsetPx (image top / page top). This produces a
    /// continuous page from top to bottom.
    ///
    /// The strip is cropped `overlap` rows taller than `offsetPx` (extending 1 row
    /// up into the overlap region with `existing`) and drawn *after* `existing`,
    /// so the newer frame overwrites that 1 row. This hides any sub-pixel seam
    /// caused by Vision's fractional offset being rounded to an integer.
    ///
    /// CGContext uses bottom-left origin: y=0 → displayed at image bottom,
    /// higher y → displayed higher (image top). New content is page-bottom
    /// content that just scrolled into view, so it goes at y=0. Older
    /// accumulated content is page-top content shifted above.
    ///
    /// Note: `headerHeight` is intentionally NOT consulted here. Sticky-header
    /// handling is confined to `visionShift` (which crops the frozen top rows out
    /// of the registration inputs) and to `frozenTopHeight` reporting. The strip
    /// is always the bottom `offsetPx` rows of the frame, which is correct with
    /// or without a frozen header: a frozen header sits at the top of the frame
    /// and never reaches the bottom strip, so it's naturally excluded.
    private func mergeNewContent(currentFrame: CGImage, offsetPx: Int) async {
        guard let existing = mergedImage else {
            mergedImage = currentFrame
            return
        }

        let w = currentFrame.width
        let existingH = existing.height
        let newRows = offsetPx
        guard newRows > 0, newRows <= currentFrame.height else { return }

        // 1px overlap bias: extend the strip upward by one row so it covers the
        // bottom row of `existing`, hiding any rounding error in the Vision offset.
        let overlap = 1
        let stripHeight = min(newRows + overlap, currentFrame.height)
        let totalH = existingH + newRows

        let merged: CGImage? = await withCheckedContinuation { cont in
            captureQueue.async {
                let cs = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                guard let ctx = CGContext(data: nil, width: w, height: totalH,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: cs, bitmapInfo: bitmapInfo) else {
                    cont.resume(returning: nil)
                    return
                }

                let stripY = currentFrame.height - stripHeight
                guard stripY >= 0,
                      let strip = currentFrame.cropping(to: CGRect(
                          x: 0, y: stripY, width: w, height: stripHeight)) else {
                    cont.resume(returning: nil)
                    return
                }

                // Draw existing first (at y=newRows), then the strip on top (y=0,
                // height=stripHeight) so the strip's top `overlap` rows overwrite
                // existing's bottom rows and hide the seam.
                ctx.draw(existing, in: CGRect(x: 0, y: newRows, width: w, height: existingH))
                ctx.draw(strip, in: CGRect(x: 0, y: 0, width: w, height: stripHeight))
                cont.resume(returning: ctx.makeImage())
            }
        }

        guard let merged = merged else { return }
        mergedImage = merged
        stitchedImage = merged
        stitchedPixelSize = CGSize(width: CGFloat(w), height: CGFloat(totalH))
    }

    private func stopAutoScroll() {
        autoScrollActive = false
        autoScrollTask?.cancel(); autoScrollTask = nil
    }

    func toggleAutoScroll() {
        if autoScrollActive {
            stopAutoScroll()
            startManualScrollMonitors()
        } else {
            if let m = scrollMonitorGlobal { NSEvent.removeMonitor(m); scrollMonitorGlobal = nil }
            if let m = scrollMonitorLocal  { NSEvent.removeMonitor(m); scrollMonitorLocal  = nil }
            settlementTimer?.invalidate(); settlementTimer = nil
            startAutoScroll()
        }
    }

    // MARK: - Manual scroll

    private func startManualScrollMonitors() {
        scrollMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.onManualScrollEvent()
        }
        scrollMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onManualScrollEvent()
            return event
        }
    }

    private func onManualScrollEvent() {
        guard isActive else { return }

        // After scrolling stops, do a final settled capture (TIFF comparison)
        settlementTimer?.invalidate()
        settlementTimer = Timer.scheduledTimer(withTimeInterval: settlementInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in await self.settledCapture() }
        }

        // During scrolling, grab and process frames immediately at a fixed interval —
        // no TIFF settlement. This ensures we capture content continuously even with
        // small selection areas where a single scroll gesture can move past the entire
        // viewport.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= manualCaptureInterval else { return }
        lastCaptureTime = now

        Task { [weak self] in
            guard let self = self else { return }
            await self.grabAndProcess()
        }
    }

    /// Immediate frame grab + process during active scrolling. No TIFF settlement —
    /// just captures whatever is on screen right now and tries to stitch it.
    private func grabAndProcess() async {
        guard isActive, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard let currentFrame = captureFrame() else { return }
        guard let previousFrame = shotA else {
            shotA = currentFrame
            return
        }

        if !rightMarginDetected {
            await detectRightMargin(current: currentFrame, previous: previousFrame)
        }

        guard let offset = await visionShift(current: currentFrame, previous: previousFrame) else {
            shotA = currentFrame
            return
        }

        let offsetPx = Int(round(offset))
        guard offsetPx > 0 else {
            shotA = currentFrame
            return
        }

        let minShift = currentFrame.height / 10
        if offsetPx < minShift { return }

        hasScrolledOnce = true
        consecutiveZeroShifts = 0

        if frozenDetectionEnabled && !headerDetectionDone {
            await detectHeader(current: currentFrame, previous: previousFrame, shiftPx: offsetPx)
        }

        await mergeNewContent(currentFrame: currentFrame, offsetPx: offsetPx)

        shotA = currentFrame
        stripCount += 1
        didReportFirstMatch = true

        emitPreview()
        onStripAdded?(stripCount)
    }

    /// Final settled capture after scrolling stops — uses full TIFF settlement.
    private func settledCapture() async {
        guard isActive, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let _ = await captureAndCompare()
    }

    // MARK: - Vision shift detection

    /// Vision framework translational image registration.
    /// Runs on `captureQueue` (background serial queue) so the main thread stays
    /// responsive. VNImageRequestHandler is thread-safe and the CGImage data is
    /// already backed by immutable pixel data, so this is safe to dispatch.
    private func visionShift(current: CGImage, previous: CGImage) async -> CGFloat? {
        var curImg = current
        var prevImg = previous
        let maxCropY = current.height / 5
        let cropY = headerDetectionDone ? min(headerHeight, maxCropY) : 0
        let cropW = current.width - rightMarginPx
        let cropH = current.height - cropY
        if cropY > 0 || rightMarginPx > 0 {
            guard cropH > 20 && cropW > 20 else { return nil }
            let cropRect = CGRect(x: 0, y: cropY, width: cropW, height: cropH)
            guard let cc = current.cropping(to: cropRect),
                  let pc = previous.cropping(to: cropRect) else { return nil }
            curImg = cc
            prevImg = pc
        }

        return await withCheckedContinuation { [curImg, prevImg] cont in
            captureQueue.async {
                let request = VNTranslationalImageRegistrationRequest(targetedCGImage: prevImg)
                let handler = VNImageRequestHandler(cgImage: curImg, options: [:])
                guard (try? handler.perform([request])) != nil,
                      let obs = request.results?.first as? VNImageTranslationAlignmentObservation else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: obs.alignmentTransform.ty)
            }
        }
    }

    /// Extract raw BGRA pixel data from a CGImage as an unsafe pointer.
    /// Pure function — only reads from the immutable CGImage argument, so it's
    /// declared `static` to (a) avoid capturing `self` in `captureQueue.async`
    /// closures (which would otherwise cross actor isolation under Swift 6 strict
    /// concurrency) and (b) make the lack of instance-state access self-evident.
    private static func pixelData(for image: CGImage) -> UnsafePointer<UInt8>? {
        guard let provider = image.dataProvider,
              let cfData = provider.data else { return nil }
        return CFDataGetBytePtr(cfData)
    }

    /// Extract raw pixel data as `Data` for byte-level comparison.
    /// Runs the extraction on `captureQueue` to avoid blocking the main thread.
    private func extractPixelData(from image: CGImage) async -> Data? {
        await withCheckedContinuation { cont in
            captureQueue.async {
                guard let provider = image.dataProvider,
                      let cfData = provider.data else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: cfData as Data)
            }
        }
    }

    // MARK: - Scrollbar detection

    private func detectRightMargin(current: CGImage, previous: CGImage) async {
        rightMarginDetected = true

        guard current.width == previous.width, current.height == previous.height else { return }

        let scrollbarWidth: Int = await withCheckedContinuation { cont in
            captureQueue.async {
                guard let curData = Self.pixelData(for: current),
                      let prevData = Self.pixelData(for: previous) else {
                    cont.resume(returning: 0)
                    return
                }

                let w = current.width
                let h = current.height
                let bytesPerRow = w * 4

                let rowStart = h * 2 / 10
                let rowEnd = h * 8 / 10
                let rowStep = max(1, (rowEnd - rowStart) / 40)

                var scrollbarWidth = 0
                let maxScanCols = min(50, w / 8)

                for colOffset in 0..<maxScanCols {
                    let col = w - 1 - colOffset
                    var sad: UInt64 = 0
                    var samples: Int = 0

                    for row in stride(from: rowStart, to: rowEnd, by: rowStep) {
                        let idx = row * bytesPerRow + col * 4
                        guard idx + 2 < h * bytesPerRow else { continue }
                        sad += UInt64(abs(Int(curData[idx]) - Int(prevData[idx]))
                                    + abs(Int(curData[idx + 1]) - Int(prevData[idx + 1]))
                                    + abs(Int(curData[idx + 2]) - Int(prevData[idx + 2])))
                        samples += 1
                    }
                    guard samples > 0 else { continue }
                    let avgSAD = sad / UInt64(samples)

                    if avgSAD > 8 {
                        scrollbarWidth = colOffset + 1
                    } else if scrollbarWidth > 0 {
                        break
                    }
                }

                cont.resume(returning: scrollbarWidth)
            }
        }

        if scrollbarWidth >= 3 && scrollbarWidth <= 40 {
            rightMarginPx = scrollbarWidth + 4
        }
    }

    // MARK: - Header (frozen region) detection

    private func detectHeader(current: CGImage, previous: CGImage, shiftPx: Int) async {
        guard current.width == previous.width, current.height == previous.height else { return }
        guard shiftPx > 5 else { return }

        // Snapshot rightMarginPx on the main actor before dispatching — it's a
        // main-actor property and must not be read from captureQueue (data race).
        let marginPx = rightMarginPx
        let result: (frozenRows: Int, w: Int, h: Int) = await withCheckedContinuation { cont in
            captureQueue.async {
                let w = current.width
                let h = current.height

                guard let curData = Self.pixelData(for: current),
                      let prevData = Self.pixelData(for: previous) else {
                    cont.resume(returning: (0, w, h))
                    return
                }

                let bytesPerRow = w * 4
                let compareBytes = max(4, (w - marginPx)) * 4
                let colStep = 4

                var frozenRows = 0
                for row in 0..<h {
                    var rowSAD: UInt64 = 0
                    var samples: Int = 0
                    let offset = row * bytesPerRow
                    for col in stride(from: 0, to: compareBytes, by: colStep * 4) {
                        let cR = Int(curData[offset + col])
                        let cG = Int(curData[offset + col + 1])
                        let cB = Int(curData[offset + col + 2])
                        let pR = Int(prevData[offset + col])
                        let pG = Int(prevData[offset + col + 1])
                        let pB = Int(prevData[offset + col + 2])
                        rowSAD += UInt64(abs(cR - pR) + abs(cG - pG) + abs(cB - pB))
                        samples += 1
                    }
                    let avg = samples > 0 ? rowSAD / UInt64(samples) : 999
                    if avg > 8 {
                        frozenRows = row
                        break
                    }
                    if row == h - 1 {
                        cont.resume(returning: (0, w, h))
                        return
                    }
                }

                cont.resume(returning: (frozenRows, w, h))
            }
        }

        let frozenRows = result.frozenRows
        let h = result.h

        if frozenRows >= 10 && frozenRows < (h * 6 / 10) {
            headerDetectionSamples += 1

            if headerDetectionSamples == 1 {
                headerHeight = frozenRows
                frozenTopHeight = CGFloat(headerHeight) / backingScale
                headerDetectionDone = true
            } else {
                if abs(frozenRows - headerHeight) <= 5 {
                    headerHeight = min(headerHeight, frozenRows)
                    frozenTopHeight = CGFloat(headerHeight) / backingScale
                } else {
                    headerHeight = 0
                    frozenTopHeight = 0
                }
                headerDetectionDone = true
            }
        } else if frozenRows < 10 {
            headerDetectionDone = true
        }
    }

    // MARK: - Preview

    private func emitPreview() {
        guard let cg = mergedImage, let callback = onPreviewUpdated else { return }
        let ptSize = CGSize(width: CGFloat(cg.width) / backingScale,
                            height: CGFloat(cg.height) / backingScale)
        callback(NSImage(cgImage: cg, size: ptSize))
    }
}
