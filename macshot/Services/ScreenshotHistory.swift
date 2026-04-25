import Cocoa
import UniformTypeIdentifiers

struct HistoryEntry {
    let id: String           // UUID filename (without extension)
    let fileExtension: String // "png" or "jpg"
    let timestamp: Date
    let pixelWidth: Int
    let pixelHeight: Int
    var hasAnnotations: Bool = false  // true if editable annotations are saved alongside
    var thumbnail: NSImage?  // lazily cached, tiny

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    var timeAgoString: String {
        let seconds = Int(-timestamp.timeIntervalSinceNow)
        if seconds < 5 { return L("just now") }
        if seconds < 60 { return String(format: L("%ds ago"), seconds) }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: L("%dm ago"), minutes) }
        let hours = minutes / 60
        if hours < 24 { return String(format: L("%dh ago"), hours) }
        return Self.dateFormatter.string(from: timestamp)
    }
}

@MainActor
class ScreenshotHistory {

    static let shared = ScreenshotHistory()

    private(set) var entries: [HistoryEntry] = []

    private let historyDir: URL
    private let indexFile: URL

    var maxEntries: Int {
        if let stored = UserDefaults.standard.object(forKey: "historySize") as? Int {
            return stored == 999 ? Int.max : stored
        }
        return 10  // default
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyDir = appSupport.appendingPathComponent("com.fxzer.macshot/history")
        indexFile = historyDir.appendingPathComponent("index.json")

        // Create directory with 0700 permissions (owner only)
        if !FileManager.default.fileExists(atPath: historyDir.path) {
            try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        loadIndex()
    }

    // MARK: - Public API

    /// Add a screenshot to history.
    /// - Parameters:
    ///   - image: The composited image (annotations baked in) used for display, clipboard, and sharing.
    ///   - rawImage: The raw screenshot without annotations (optional — for editable history).
    ///   - annotations: Live annotation objects (optional — serialized to JSON for editable history).
    func add(image: NSImage, rawImage: NSImage? = nil, annotations: [Annotation]? = nil) {
        let max = maxEntries
        guard max > 0 else { return }

        let id = UUID().uuidString
        let ext = "png"

        // Capture metadata on main thread (cheap)
        let size = image.size
        let scale: CGFloat = ImageEncoder.downscaleRetina ? 1.0 : (NSScreen.main?.backingScaleFactor ?? 2.0)

        let hasAnns = annotations != nil && !(annotations!.isEmpty) && rawImage != nil

        // Create entry with a placeholder thumbnail (tiny, fast)
        let entry = HistoryEntry(
            id: id,
            fileExtension: ext,
            timestamp: Date(),
            pixelWidth: Int(size.width * scale),
            pixelHeight: Int(size.height * scale),
            hasAnnotations: hasAnns,
            thumbnail: NSImage(size: NSSize(width: 1, height: 1))
        )
        entries.insert(entry, at: 0)

        // Prune oldest entries beyond max
        while entries.count > max {
            let removed = entries.removeLast()
            deleteFiles(for: removed.id, ext: removed.fileExtension)
        }

        // Serialize annotations on main thread (fast — just JSON encoding)
        let annotationData: Data? = hasAnns ? AnnotationSerializer.encode(annotations!) : nil

        // Move all expensive work off main thread: thumbnail, preview, PNG encoding, index save
        let fileURL = historyDir.appendingPathComponent("\(id).\(ext)")
        let thumbURL = historyDir.appendingPathComponent("\(id)_thumb.png")
        let previewURL = historyDir.appendingPathComponent("\(id)_preview.png")
        let rawURL = historyDir.appendingPathComponent("\(id)_raw.png")
        let annURL = historyDir.appendingPathComponent("\(id)_annotations.json")
        let histDir = historyDir
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let thumb = self.makeScaledImage(image, maxDimension: 36)
            let preview = self.makeScaledImage(image, maxDimension: 240)

            // Update the entry's thumbnail on main thread
            DispatchQueue.main.async {
                if let idx = self.entries.firstIndex(where: { $0.id == id }) {
                    self.entries[idx].thumbnail = thumb
                }
                self.saveIndex()
            }

            // Write images using direct CGImageDestination (avoids tiff→bitmap→png overhead)
            Self.writePNG(image, to: fileURL)
            Self.writePNG(thumb, to: thumbURL)
            Self.writePNG(preview, to: previewURL)
            if let raw = rawImage { Self.writePNG(raw, to: rawURL) }
            if let annData = annotationData {
                try? annData.write(to: annURL, options: .atomic)
            }
        }
    }

    /// Update an existing history entry in-place (for "Done" in editor).
    /// Rewrites the composited image, raw image, annotations, thumbnail, and preview.
    func updateEntry(id: String, compositedImage: NSImage, rawImage: NSImage?, annotations: [Annotation]?) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }

        let hasAnns = annotations != nil && !(annotations!.isEmpty) && rawImage != nil
        entries[idx].hasAnnotations = hasAnns

        let annotationData: Data? = hasAnns ? AnnotationSerializer.encode(annotations!) : nil

        let ext = entries[idx].fileExtension
        let fileURL = historyDir.appendingPathComponent("\(id).\(ext)")
        let thumbURL = historyDir.appendingPathComponent("\(id)_thumb.png")
        let previewURL = historyDir.appendingPathComponent("\(id)_preview.png")
        let rawURL = historyDir.appendingPathComponent("\(id)_raw.png")
        let annURL = historyDir.appendingPathComponent("\(id)_annotations.json")

        // Update thumbnail in memory immediately
        let thumb = makeScaledImage(compositedImage, maxDimension: 36)
        entries[idx].thumbnail = thumb
        saveIndex()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            Self.writePNG(compositedImage, to: fileURL)
            Self.writePNG(thumb, to: thumbURL)
            let preview = self.makeScaledImage(compositedImage, maxDimension: 240)
            Self.writePNG(preview, to: previewURL)
            if let raw = rawImage {
                Self.writePNG(raw, to: rawURL)
            } else {
                try? FileManager.default.removeItem(at: rawURL)
            }
            if let annData = annotationData {
                try? annData.write(to: annURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: annURL)
            }
        }
    }

    func pruneToMax() {
        let max = maxEntries
        if max <= 0 {
            clear()
        } else {
            while entries.count > max {
                let removed = entries.removeLast()
                deleteFiles(for: removed.id, ext: removed.fileExtension)
            }
            saveIndex()
        }
    }

    func removeEntry(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        deleteFiles(for: entry.id, ext: entry.fileExtension)
        saveIndex()
    }

    func clear() {
        for entry in entries {
            deleteFiles(for: entry.id, ext: entry.fileExtension)
        }
        entries.removeAll()
        saveIndex()
    }

    func copyEntry(at index: Int) {
        guard index >= 0, index < entries.count else { return }
        let entry = entries[index]
        let fileURL = historyDir.appendingPathComponent("\(entry.id).\(entry.fileExtension)")
        guard let imageData = try? Data(contentsOf: fileURL),
              let image = NSImage(data: imageData) else { return }
        ImageEncoder.copyToClipboard(image)
    }

    func loadImage(for entry: HistoryEntry) -> NSImage? {
        let fileURL = historyDir.appendingPathComponent("\(entry.id).\(entry.fileExtension)")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }

    func fileURL(for entry: HistoryEntry) -> URL {
        historyDir.appendingPathComponent("\(entry.id).\(entry.fileExtension)")
    }

    /// Load the raw (un-annotated) screenshot for editable history entries.
    func loadRawImage(for entry: HistoryEntry) -> NSImage? {
        guard entry.hasAnnotations else { return nil }
        let rawURL = historyDir.appendingPathComponent("\(entry.id)_raw.png")
        guard let data = try? Data(contentsOf: rawURL) else { return nil }
        return NSImage(data: data)
    }

    /// Load saved annotations for editable history entries.
    func loadAnnotations(for entry: HistoryEntry) -> [Annotation]? {
        guard entry.hasAnnotations else { return nil }
        let annURL = historyDir.appendingPathComponent("\(entry.id)_annotations.json")
        guard let data = try? Data(contentsOf: annURL) else { return nil }
        return AnnotationSerializer.decode(data)
    }

    func loadThumbnail(for entry: HistoryEntry) -> NSImage? {
        if let thumb = entry.thumbnail { return thumb }
        let thumbURL = historyDir.appendingPathComponent("\(entry.id)_thumb.png")
        return NSImage(contentsOf: thumbURL)
    }

    /// Load a mid-size preview suitable for history panel cards (~240pt wide).
    /// Falls back to disk thumbnail scaled up, or full image if needed.
    func loadPreview(for entry: HistoryEntry) -> NSImage? {
        // Try preview file first
        let previewURL = historyDir.appendingPathComponent("\(entry.id)_preview.png")
        if let preview = NSImage(contentsOf: previewURL) { return preview }

        // Fall back to full image, scaled down
        guard let full = loadImage(for: entry) else { return nil }
        let preview = makeScaledImage(full, maxDimension: 240)

        // Cache preview to disk for next time (fire and forget)
        DispatchQueue.global(qos: .utility).async {
            Self.writePNG(preview, to: previewURL)
        }

        return preview
    }

    // MARK: - Persistence

    private struct IndexEntry: Codable {
        let id: String
        let fileExtension: String
        let timestamp: Date
        let pixelWidth: Int
        let pixelHeight: Int
        var hasAnnotations: Bool?  // optional for backward compat with old index files
    }

    private func saveIndex() {
        let indexEntries = entries.map {
            IndexEntry(id: $0.id, fileExtension: $0.fileExtension, timestamp: $0.timestamp,
                       pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                       hasAnnotations: $0.hasAnnotations ? true : nil)
        }
        if let data = try? JSONEncoder().encode(indexEntries) {
            try? data.write(to: indexFile, options: .atomic)
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFile),
              let indexEntries = try? JSONDecoder().decode([IndexEntry].self, from: data) else { return }

        entries = indexEntries.compactMap { ie in
            // Only include entries whose image file still exists
            let ext = ie.fileExtension
            let fileURL = historyDir.appendingPathComponent("\(ie.id).\(ext)")
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return HistoryEntry(id: ie.id, fileExtension: ext, timestamp: ie.timestamp, pixelWidth: ie.pixelWidth, pixelHeight: ie.pixelHeight, hasAnnotations: ie.hasAnnotations ?? false, thumbnail: nil)
        }

        // Prune if maxEntries was lowered since last run
        let max = maxEntries
        if max <= 0 {
            clear()
        } else {
            while entries.count > max {
                let removed = entries.removeLast()
                deleteFiles(for: removed.id, ext: removed.fileExtension)
            }
            if entries.count < indexEntries.count {
                saveIndex()
            }
        }
    }

    // MARK: - File helpers

    private func deleteFiles(for id: String, ext: String = "png") {
        let fileURL = historyDir.appendingPathComponent("\(id).\(ext)")
        let thumbURL = historyDir.appendingPathComponent("\(id)_thumb.png")
        let previewURL = historyDir.appendingPathComponent("\(id)_preview.png")
        let rawURL = historyDir.appendingPathComponent("\(id)_raw.png")
        let annURL = historyDir.appendingPathComponent("\(id)_annotations.json")
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: thumbURL)
        try? FileManager.default.removeItem(at: previewURL)
        try? FileManager.default.removeItem(at: rawURL)
        try? FileManager.default.removeItem(at: annURL)
    }

    /// Scale an image to fit within maxDimension on its longest side.
    /// Used for both thumbnails (maxDimension=36) and previews (maxDimension=240).
    private func makeScaledImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let targetSize = NSSize(width: round(size.width * scale), height: round(size.height * scale))
        return NSImage(size: targetSize, flipped: false) { _ in
            image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
    }

    /// Write an NSImage to disk as PNG using CGImageDestination.
    /// Avoids the expensive tiff→NSBitmapImageRep→PNG conversion chain.
    private static func writePNG(_ image: NSImage, to url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }
}
