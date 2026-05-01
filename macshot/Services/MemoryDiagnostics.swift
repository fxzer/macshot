import AppKit
import Darwin.Mach
import Foundation

enum MemoryDiagnostics {
    static let enabledDefaultsKey = "memoryDiagnosticsEnabled"

    struct Snapshot {
        let timestamp: CFAbsoluteTime
        let residentBytes: UInt64
        let physFootprintBytes: UInt64
        let virtualBytes: UInt64

        var compactDescription: String {
            "footprint=\(format(bytes: physFootprintBytes)) resident=\(format(bytes: residentBytes)) virtual=\(format(bytes: virtualBytes))"
        }
    }

    struct Scope {
        let label: String
        let startTime: CFAbsoluteTime
        let startSnapshot: Snapshot?
        private(set) var lastSnapshot: Snapshot?

        init(
            label: String,
            images: [(String, NSImage?)] = [],
            cgImages: [(String, CGImage?)] = [],
            metadata: @autoclosure () -> String = ""
        ) {
            self.label = label
            self.startTime = CFAbsoluteTimeGetCurrent()
            let snapshot = MemoryDiagnostics.currentSnapshot()
            self.startSnapshot = snapshot
            self.lastSnapshot = snapshot
            MemoryDiagnostics.logSnapshot(
                kind: "BEGIN",
                label: label,
                snapshot: snapshot,
                previous: nil,
                elapsedMs: 0,
                totalMs: 0,
                images: images,
                cgImages: cgImages,
                metadata: metadata()
            )
        }

        mutating func step(
            _ phase: String,
            images: [(String, NSImage?)] = [],
            cgImages: [(String, CGImage?)] = [],
            metadata: @autoclosure () -> String = ""
        ) {
            let now = CFAbsoluteTimeGetCurrent()
            let snapshot = MemoryDiagnostics.currentSnapshot()
            MemoryDiagnostics.logSnapshot(
                kind: phase,
                label: label,
                snapshot: snapshot,
                previous: lastSnapshot,
                elapsedMs: (now - startTime) * 1000,
                totalMs: (now - startTime) * 1000,
                images: images,
                cgImages: cgImages,
                metadata: metadata()
            )
            lastSnapshot = snapshot
        }

        mutating func finish(
            _ phase: String = "END",
            images: [(String, NSImage?)] = [],
            cgImages: [(String, CGImage?)] = [],
            metadata: @autoclosure () -> String = ""
        ) {
            let now = CFAbsoluteTimeGetCurrent()
            let snapshot = MemoryDiagnostics.currentSnapshot()
            let totalMs = (now - startTime) * 1000
            MemoryDiagnostics.logSnapshot(
                kind: phase,
                label: label,
                snapshot: snapshot,
                previous: startSnapshot,
                elapsedMs: totalMs,
                totalMs: totalMs,
                images: images,
                cgImages: cgImages,
                metadata: metadata()
            )
            lastSnapshot = snapshot
        }
    }

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["MACSHOT_MEMORY_DIAGNOSTICS"] == "1" {
            return true
        }
        if UserDefaults.standard.bool(forKey: enabledDefaultsKey) {
            return true
        }
        return CaptureDiagnostics.isEnabled
    }

    static func snapshot(
        _ label: String,
        images: [(String, NSImage?)] = [],
        cgImages: [(String, CGImage?)] = [],
        metadata: @autoclosure () -> String = ""
    ) {
        let current = currentSnapshot()
        logSnapshot(
            kind: "SNAPSHOT",
            label: label,
            snapshot: current,
            previous: nil,
            elapsedMs: nil,
            totalMs: nil,
            images: images,
            cgImages: cgImages,
            metadata: metadata()
        )
    }

    static func makeScope(
        _ label: String,
        images: [(String, NSImage?)] = [],
        cgImages: [(String, CGImage?)] = [],
        metadata: @autoclosure () -> String = ""
    ) -> Scope {
        Scope(label: label, images: images, cgImages: cgImages, metadata: metadata())
    }

    static func format(bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func currentSummary() -> String {
        currentSnapshot()?.compactDescription ?? "snapshot=unavailable"
    }

    static func estimatedBytes(for image: NSImage?) -> UInt64 {
        guard let image else { return 0 }
        if let rep = image.representations.first {
            let bitmapRep = rep as? NSBitmapImageRep
            let bytesPerPixel = max((bitmapRep?.bitsPerPixel ?? 32) / 8, 4)
            let width = rep.pixelsWide > 0 ? rep.pixelsWide : Int(image.size.width)
            let height = rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(image.size.height)
            return UInt64(max(0, width * height * bytesPerPixel))
        }
        return UInt64(max(0, Int(image.size.width * image.size.height * 4 * 4)))
    }

    static func estimatedBytes(for image: CGImage?) -> UInt64 {
        guard let image else { return 0 }
        let fallbackRowBytes = image.width * max(image.bitsPerPixel / 8, 4)
        let rowBytes = max(image.bytesPerRow, fallbackRowBytes)
        return UInt64(max(0, rowBytes * image.height))
    }

    static func imageSummary(named name: String, image: NSImage?) -> String? {
        guard let image else { return nil }
        let sizeBytes = estimatedBytes(for: image)
        let pixelSize: String
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            pixelSize = "\(rep.pixelsWide)x\(rep.pixelsHigh)"
        } else {
            pixelSize = "\(Int(image.size.width.rounded()))x\(Int(image.size.height.rounded()))pt"
        }
        return "\(name)=\(format(bytes: sizeBytes))[\(pixelSize)]"
    }

    static func imageSummary(named name: String, image: CGImage?) -> String? {
        guard let image else { return nil }
        return "\(name)=\(format(bytes: estimatedBytes(for: image)))[\(image.width)x\(image.height)]"
    }

    private static func currentSnapshot() -> Snapshot? {
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vmKernResult: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        guard vmKernResult == KERN_SUCCESS else { return nil }

        var basicInfo = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let basicKernResult: kern_return_t = withUnsafeMutablePointer(to: &basicInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }
        guard basicKernResult == KERN_SUCCESS else { return nil }

        return Snapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            residentBytes: UInt64(basicInfo.resident_size),
            physFootprintBytes: vmInfo.phys_footprint,
            virtualBytes: UInt64(basicInfo.virtual_size)
        )
    }

    private static func logSnapshot(
        kind: String,
        label: String,
        snapshot: Snapshot?,
        previous: Snapshot?,
        elapsedMs: Double?,
        totalMs: Double?,
        images: [(String, NSImage?)],
        cgImages: [(String, CGImage?)],
        metadata: String
    ) {
        guard isEnabled else { return }

        var parts: [String] = ["[macshot-mem][\(label)] \(kind)"]

        if let totalMs {
            parts.append("elapsed=\(String(format: "%.1f", totalMs))ms")
        }

        if let snapshot {
            parts.append(snapshot.compactDescription)
            if let previous {
                let delta = Int64(snapshot.physFootprintBytes) - Int64(previous.physFootprintBytes)
                let residentDelta = Int64(snapshot.residentBytes) - Int64(previous.residentBytes)
                parts.append("Δfootprint=\(signedByteString(delta))")
                parts.append("Δresident=\(signedByteString(residentDelta))")
            }
        } else {
            parts.append("snapshot=unavailable")
        }

        let imageParts = images.compactMap { imageSummary(named: $0.0, image: $0.1) }
            + cgImages.compactMap { imageSummary(named: $0.0, image: $0.1) }
        if !imageParts.isEmpty {
            parts.append(imageParts.joined(separator: " "))
        }

        if !metadata.isEmpty {
            parts.append(metadata)
        }

        CaptureDiagnostics.log(parts.joined(separator: " "))
    }

    private static func signedByteString(_ delta: Int64) -> String {
        let sign = delta >= 0 ? "+" : "-"
        return "\(sign)\(format(bytes: UInt64(abs(delta))))"
    }
}
