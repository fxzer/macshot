import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreGraphics

// Callback types
typealias RecordingProgressCallback = (_ seconds: Int) -> Void
typealias RecordingCompletionCallback = (_ url: URL?, _ error: Error?) -> Void

@MainActor
final class RecordingEngine: NSObject {

    // MARK: - State (main-actor-isolated UI/lifecycle state)

    enum State { case idle, recording, paused, stopping }
    private(set) var state: State = .idle

    // MARK: - Config (read from UserDefaults at start)

    private var fps: Int = 30
    private var cropRect: CGRect = .zero      // in screen coordinates (top-left origin)
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()

    // MARK: - SCStream

    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?

    // Writer actor — owns AVAssetWriter + encoder graph off the main thread.
    // SCKit delivers frames on recordingQueue; routing them straight into the
    // actor (instead of DispatchQueue.main.async) keeps the per-frame encode
    // cost (~0.5-2ms at 30-60fps) off the main thread entirely.
    private var writer: RecordingWriter?

    /// Serial queue for SCStream sample delivery + mic output.
    private let recordingQueue = DispatchQueue(label: "macshot.recording")
    private var outputURL: URL?

    // MARK: - Mic capture

    private var micCaptureSession: AVCaptureSession?
    private var micDataOutput: AVCaptureAudioDataOutput?
    private var micDelegate: MicCaptureDelegate?

    // MARK: - Callbacks

    var onProgress: RecordingProgressCallback?
    var onCompletion: RecordingCompletionCallback?

    private var progressTimer: Timer?
    private var elapsedSeconds: Int = 0
    private var pauseStartTime: Date?
    var onPauseChanged: ((Bool) -> Void)?

    // MARK: - Public API

    /// Start recording the given rect (in NSScreen/AppKit coordinates, bottom-left origin).
    /// Optional overrides take precedence over UserDefaults for this session.
    /// Window IDs to exclude from the recording (e.g. selection border, HUD).
    private var excludeWindowNumbers: [CGWindowID] = []

    func startRecording(rect: NSRect, screen: NSScreen, fpsOverride: Int? = nil, excludeWindowNumbers: [CGWindowID] = []) {
        self.excludeWindowNumbers = excludeWindowNumbers
        guard state == .idle else { return }
        state = .recording

        self.screen = screen
        // Convert AppKit rect (bottom-left origin) → screen coords (top-left origin)
        // SCStream uses top-left origin matching the display's coordinate system.
        let displayBounds = screen.frame
        let flippedY = displayBounds.maxY - rect.maxY
        // Scale to points — SCStream works in points on the display
        self.cropRect = CGRect(x: rect.minX - displayBounds.minX,
                               y: flippedY,
                               width: rect.width,
                               height: rect.height)

        let defaultFPS = normalizedRecordingFPS(UserDefaults.standard.integer(forKey: "recordingFPS"))
        self.fps = fpsOverride ?? defaultFPS
        Task { [weak self] in
            guard let self = self else { return }
            // Resolve mic permission before starting capture so the prompt
            // doesn't block the UI while frames are already being recorded.
            if UserDefaults.standard.bool(forKey: "recordMicAudio") {
                let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                if micStatus == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .audio)
                    if !granted {
                        UserDefaults.standard.set(false, forKey: "recordMicAudio")
                    }
                } else if micStatus == .denied || micStatus == .restricted {
                    UserDefaults.standard.set(false, forKey: "recordMicAudio")
                }
            }
            await self.beginCapture(rect: rect)
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        state = .paused
        pauseStartTime = Date()
        progressTimer?.invalidate()
        progressTimer = nil
        Task { [writer] in await writer?.beginPause() }
        onPauseChanged?(true)
    }

    func resumeRecording() {
        guard state == .paused else { return }
        if let start = pauseStartTime {
            let duration = Date().timeIntervalSince(start)
            pauseStartTime = nil
            Task { [writer] in await writer?.endPause(duration: duration) }
        }
        state = .recording
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.elapsedSeconds += 1
                self.onProgress?(self.elapsedSeconds)
            }
        }
        onPauseChanged?(false)
    }

    func stopRecording() {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        progressTimer?.invalidate()
        progressTimer = nil
        Task { [weak self] in await self?.finalizeCapture() }
    }

    /// Called when the SCStream reported an error via `stream(_:didStopWithError:)`.
    /// Shares the stop guard with `stopRecording()`: if the user already initiated a
    /// normal stop (state == .stopping), the error is swallowed. Otherwise we mark a
    /// pending error so the writer's `finalize()` routes to `fail()` instead of
    /// `succeed()`, producing a user-visible failure instead of a "successful" truncated file.
    private func handleStreamError(_ error: Error) {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        progressTimer?.invalidate()
        progressTimer = nil
        Task { [weak self, error] in
            guard let self else { return }
            await self.writer?.reportStreamError(error)
            await self.finalizeCapture()
        }
    }

    // MARK: - Setup

    private func beginCapture(rect: NSRect) async {
        do {
            // Find the SCDisplay matching our screen by display ID
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { d in
                screenID != nil && d.displayID == screenID!
            }) ?? content.displays.first else {
                self.fail(RecordingError.noDisplay)
                return
            }

            // Exclude specific macshot UI chrome windows (selection border, HUD)
            // but NOT recording overlays (webcam, mouse highlight, keystrokes)
            // which are intentionally part of the recording.
            let excludeIDs = excludeWindowNumbers
            let excludeWindows = excludeIDs.compactMap { wid in
                content.windows.first(where: { CGWindowID($0.windowID) == wid })
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludeWindows)
            let config = SCStreamConfiguration()
            config.width = Int(cropRect.width * screen.backingScaleFactor)
            config.height = Int(cropRect.height * screen.backingScaleFactor)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.showsCursor = true   // we'll draw our own highlight on top if needed
            config.sourceRect = cropRect
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.scalesToFit = false

            // System audio capture (off by default, macOS 13+)
            if #available(macOS 13.0, *) {
                let recordAudio = UserDefaults.standard.bool(forKey: "recordSystemAudio")
                config.capturesAudio = recordAudio
                config.excludesCurrentProcessAudio = true  // don't capture macshot's own sounds
            }

            let pixelW = config.width
            let pixelH = config.height

            // Prepare output file
            outputURL = makeOutputURL()
            guard let outURL = outputURL else {
                self.fail(RecordingError.noOutput)
                return
            }

            // Build the writer graph on a background queue — AVAssetWriter setup
            // + input configuration is real work (~5-20ms) that doesn't need to
            // block the main thread.
            let recordMic = UserDefaults.standard.bool(forKey: "recordMicAudio")
            let recordSystemAudio: Bool
            if #available(macOS 13.0, *) {
                recordSystemAudio = UserDefaults.standard.bool(forKey: "recordSystemAudio")
            } else {
                recordSystemAudio = false
            }
            let newWriter: RecordingWriter
            do {
                newWriter = try await RecordingWriter(
                    url: outURL,
                    width: pixelW,
                    height: pixelH,
                    fps: fps,
                    recordMic: recordMic,
                    recordSystemAudio: recordSystemAudio
                )
            } catch {
                self.fail(error)
                return
            }
            self.writer = newWriter

            let output = RecordingStreamOutput()
            // Frames arrive on recordingQueue. Hand them to the writer actor
            // directly — NO main-thread hop. The actor serializes appends; the
            // main thread stays free for UI / status bar / overlay work.
            output.onFrame = { [weak newWriter] pixelBuffer, presentationTime in
                Task { await newWriter?.appendFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime) }
            }
            output.onAudioSample = { [weak newWriter] sampleBuffer in
                Task { await newWriter?.appendSystemAudio(sampleBuffer) }
            }
            output.onError = { [weak self] error in
                self?.handleStreamError(error)
            }
            self.streamOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: output)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: recordingQueue)
            if #available(macOS 13.0, *) {
                if recordSystemAudio {
                    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: recordingQueue)
                }
            }
            try await stream.startCapture()
            self.stream = stream

            // Start mic capture if enabled and authorized (permission resolved before capture started)
            if recordMic &&
               AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.startMicCapture()
            }

            self.elapsedSeconds = 0
            self.progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.elapsedSeconds += 1
                    self.onProgress?(self.elapsedSeconds)
                }
            }
        } catch {
            self.fail(error)
        }
    }

    private func finalizeCapture() async {
        if let stream = stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        streamOutput = nil
        self.stopMicCapture()

        guard let writer else { return }
        self.writer = nil
        let result = await writer.finalize()
        switch result {
        case .success(let url):
            self.succeed(url: url)
        case .failure(let error):
            self.fail(error)
        }
    }

    // MARK: - Mic capture

    private func startMicCapture() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let micDevice: AVCaptureDevice
        if let uid = UserDefaults.standard.string(forKey: "selectedMicDeviceUID"),
           let device = AVCaptureDevice(uniqueID: uid) {
            micDevice = device
        } else {
            guard let device = AVCaptureDevice.default(for: .audio) else { return }
            micDevice = device
        }

        // Configure + start the session on a background queue — `commitConfiguration`
        // and especially `startRunning()` are documented as slow and should not run
        // on the main thread. The mic callback queue is recordingQueue, so samples
        // flow straight into the writer actor without touching main.
        let session = AVCaptureSession()
        let dataOutput = AVCaptureAudioDataOutput()
        let delegate = MicCaptureDelegate()
        let weakWriter = writer
        delegate.onSample = { sampleBuffer in
            Task { await weakWriter?.appendMicAudio(sampleBuffer) }
        }
        let queue = recordingQueue
        DispatchQueue.global(qos: .userInitiated).async {
            session.beginConfiguration()

            guard let deviceInput = try? AVCaptureDeviceInput(device: micDevice),
                  session.canAddInput(deviceInput) else {
                session.commitConfiguration()
                return
            }
            session.addInput(deviceInput)

            dataOutput.setSampleBufferDelegate(delegate, queue: queue)
            guard session.canAddOutput(dataOutput) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(dataOutput)

            session.commitConfiguration()
            session.startRunning()
        }

        self.micCaptureSession = session
        self.micDataOutput = dataOutput
        self.micDelegate = delegate
    }

    private func stopMicCapture() {
        micCaptureSession?.stopRunning()
        micCaptureSession = nil
        micDataOutput = nil
        micDelegate = nil
    }

    // MARK: - Output URL

    private func makeOutputURL() -> URL? {
        // Save to temp directory — always writable in sandbox.
        // The video editor handles final export to the user's chosen location.
        let baseName = FilenameTemplateEngine.makeBaseName(kind: .recording)
        return TemporaryFileManager.makeRecordingOutputURL(fileExtension: "mp4", baseName: baseName)
    }

    // MARK: - Lifecycle completion (main-actor)

    private func succeed(url: URL) {
        state = .idle
        outputURL = nil
        onCompletion?(url, nil)
    }

    private func fail(_ error: Error) {
        state = .idle
        // Discard any truncated/partial output file — a half-written MP4 is not
        // reliably playable and we don't want the user to think it succeeded.
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        onCompletion?(nil, error)
    }

    enum RecordingError: LocalizedError {
        case noDisplay, noOutput
        var errorDescription: String? {
            switch self {
            case .noDisplay: return "Could not find the screen to record."
            case .noOutput: return "Could not create output file."
            }
        }
    }
}

// MARK: - RecordingWriter (off-main actor)

/// Owns the AVAssetWriter graph and serializes frame/audio appends.
/// Isolated from the main thread: SCKit/mic callbacks hand samples here via
/// `Task { await writer.append... }`, so per-frame encode work (~0.5-2ms at
/// 30-60fps) never blocks UI. `AVAssetWriterInput.append` and
/// `AVAssetWriterInputPixelBufferAdaptor.append` are thread-safe with respect
/// to a single owning writer per Apple's AVFoundation docs.
private actor RecordingWriter {
    enum FinalizeResult {
        case success(URL)
        case failure(Error)
    }

    private let outputURL: URL
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?       // system audio
    private let micAudioInput: AVAssetWriterInput?    // microphone audio
    private let pendingAudioBuffer = PendingSampleBuffer()
    private let pendingMicBuffer = PendingSampleBuffer()

    private var startTime: CMTime = .invalid
    private var sessionStarted: Bool = false
    private var frameCount: Int64 = 0
    private var pendingStreamError: Error?

    /// Pause bookkeeping lives on the actor so audio/video timestamp adjustment
    /// stays consistent with the append path (no cross-actor read of
    /// `totalPausedDuration` while a sample is being appended).
    private var totalPausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    init(url: URL, width: Int, height: Int, fps: Int, recordMic: Bool, recordSystemAudio: Bool) async throws {
        self.outputURL = url
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * fps / 8,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let sourceAttr: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourceAttr)

        writer.add(input)

        var micInput: AVAssetWriterInput? = nil
        var audioInput: AVAssetWriterInput? = nil

        if recordSystemAudio {
            let audioLayout = AudioChannelLayout(
                mChannelLayoutTag: kAudioChannelLayoutTag_Stereo,
                mChannelBitmap: [], mNumberChannelDescriptions: 0,
                mChannelDescriptions: AudioChannelDescription())
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256000,
                AVChannelLayoutKey: Data(bytes: [audioLayout], count: MemoryLayout<AudioChannelLayout>.size),
            ]
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioIn.expectsMediaDataInRealTime = true
            writer.add(audioIn)
            audioInput = audioIn
        }

        // Add mic FIRST so it becomes the primary audio track in the file.
        // Most players only decode the first audio track.
        // Mic is encoded as mono — many USB/interface mics expose a stereo device
        // where only one channel carries audio, causing one-ear playback in stereo.
        // Mono encoding downmixes both channels, fixing this for all mic types.
        if recordMic {
            let micLayout = AudioChannelLayout(
                mChannelLayoutTag: kAudioChannelLayoutTag_Mono,
                mChannelBitmap: [], mNumberChannelDescriptions: 0,
                mChannelDescriptions: AudioChannelDescription())
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000,
                AVChannelLayoutKey: Data(bytes: [micLayout], count: MemoryLayout<AudioChannelLayout>.size),
            ]
            let micIn = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            micIn.expectsMediaDataInRealTime = true
            writer.add(micIn)
            micInput = micIn
        }

        writer.startWriting()
        // Don't start session yet — start at first video frame's timestamp
        // so audio and video are aligned

        self.assetWriter = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.audioInput = audioInput
        self.micAudioInput = micInput
    }

    // MARK: - Appends (called from SCKit/mic callback queues via Task)

    func appendFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) async {
        guard videoInput.isReadyForMoreMediaData else { return }
        let adjusted = adjustedTime(presentationTime)

        if !sessionStarted {
            startTime = adjusted
            assetWriter.startSession(atSourceTime: adjusted)
            sessionStarted = true
            // Drain audio samples that arrived before the first video frame.
            // Done inline (not via Task) so all append calls stay on this actor.
            let pendingSystem = await pendingAudioBuffer.drain()
            let pendingMic = await pendingMicBuffer.drain()
            for sample in pendingSystem {
                if let input = audioInput, input.isReadyForMoreMediaData,
                   let adj = sample.adjustingTime(by: totalPausedDuration) {
                    input.append(adj)
                }
            }
            for sample in pendingMic {
                if let input = micAudioInput, input.isReadyForMoreMediaData,
                   let adj = sample.adjustingTime(by: totalPausedDuration) {
                    input.append(adj)
                }
            }
        }

        adaptor.append(pixelBuffer, withPresentationTime: adjusted)
        frameCount += 1
    }

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput else { return }
        if !sessionStarted {
            Task { [pendingAudioBuffer] in await pendingAudioBuffer.append(sampleBuffer) }
            return
        }
        guard audioInput.isReadyForMoreMediaData else { return }
        if let adjusted = sampleBuffer.adjustingTime(by: totalPausedDuration) {
            audioInput.append(adjusted)
        }
    }

    func appendMicAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let micAudioInput else { return }
        if !sessionStarted {
            Task { [pendingMicBuffer] in await pendingMicBuffer.append(sampleBuffer) }
            return
        }
        guard micAudioInput.isReadyForMoreMediaData else { return }
        if let adjusted = sampleBuffer.adjustingTime(by: totalPausedDuration) {
            micAudioInput.append(adjusted)
        }
    }

    // MARK: - Pause / resume

    func beginPause() {
        pauseStartTime = Date()
    }

    func endPause(duration: TimeInterval) {
        totalPausedDuration += duration
        pauseStartTime = nil
    }

    // MARK: - Error / finalize

    func reportStreamError(_ error: Error) {
        if pendingStreamError == nil {
            pendingStreamError = error
        }
    }

    func finalize() async -> FinalizeResult {
        let pendingError = pendingStreamError
        pendingStreamError = nil

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        micAudioInput?.markAsFinished()
        await assetWriter.finishWriting()
        await pendingAudioBuffer.removeAll()
        await pendingMicBuffer.removeAll()

        if let pendingError {
            try? FileManager.default.removeItem(at: outputURL)
            return .failure(pendingError)
        }
        return .success(outputURL)
    }

    // MARK: - Helpers

    private func adjustedTime(_ time: CMTime) -> CMTime {
        guard totalPausedDuration > 0 else { return time }
        return CMTimeSubtract(time, CMTimeMakeWithSeconds(totalPausedDuration, preferredTimescale: time.timescale))
    }
}

// MARK: - SCStreamOutput

private class RecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onAudioSample: ((CMSampleBuffer) -> Void)?
    var onError: ((Error) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            onFrame?(pixelBuffer, pts)
        case .audio:
            onAudioSample?(sampleBuffer)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The stream stopped unexpectedly (display sleep, permission revoked, encoder
        // failure, ...). Forward the error to the main-actor engine so it can
        // route to finalize() → fail() instead of producing a truncated file.
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }
}

// MARK: - Mic AVCaptureAudioDataOutput delegate

private class MicCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onSample: ((CMSampleBuffer) -> Void)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSample?(sampleBuffer)
    }
}

// MARK: - CMSampleBuffer time adjustment

private extension CMSampleBuffer {
    /// Create a copy of this audio sample buffer with timestamps shifted back
    /// by the given pause duration, so the output has no time gaps.
    func adjustingTime(by pauseDuration: TimeInterval) -> CMSampleBuffer? {
        guard pauseDuration > 0 else { return self }
        let offset = CMTimeMakeWithSeconds(pauseDuration, preferredTimescale: 44100)
        let pts = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(self), offset)
        let dur = CMSampleBufferGetDuration(self)

        var timing = CMSampleTimingInfo(duration: dur, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var adjusted: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: self, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &adjusted)
        return adjusted
    }
}

// MARK: - Pending Sample Buffer Actor

/// Actor protecting pending audio sample buffers from concurrent access.
/// Audio samples can arrive before the first video frame and must be buffered
/// until the session starts. Since audio callbacks execute concurrently,
/// we need actor isolation to prevent data races.
private actor PendingSampleBuffer {
    private var samples: [CMSampleBuffer] = []

    func append(_ sample: CMSampleBuffer) {
        samples.append(sample)
    }

    /// Drain all pending samples and return them. The caller (RecordingWriter)
    /// is responsible for adjusting timestamps and appending to the input —
    /// this keeps all AVAssetWriterInput.append calls on the RecordingWriter
    /// actor's executor.
    func drain() -> [CMSampleBuffer] {
        let drained = samples
        samples.removeAll()
        return drained
    }

    func removeAll() {
        samples.removeAll()
    }
}
