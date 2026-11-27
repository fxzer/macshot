import Cocoa

/// Linear gradient definition for stroke/fill annotations.
/// Colors are stored in sRGB so encoding, decoding, and equality checks stay consistent across displays.
struct AnnotationGradient: Equatable {
    var colors: [NSColor]
    var locations: [CGFloat]
    /// Gradient angle in degrees in AppKit coordinates (0 = left→right, 90 = bottom→top, -90 = top→bottom).
    var angle: CGFloat

    init(colors: [NSColor], locations: [CGFloat]? = nil, angle: CGFloat = -45) {
        let validColors = colors.count >= 2 ? colors : [.systemPurple, .systemBlue]
        self.colors = validColors.map { $0.usingColorSpace(.sRGB) ?? $0 }
        if let locations, locations.count == validColors.count {
            self.locations = locations
        } else {
            let count = validColors.count
            self.locations = (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
        }
        self.angle = angle
    }

    /// Primary representative color (used as fallback color and for cursor/preview seeding).
    var primaryColor: NSColor {
        colors.first ?? .systemPurple
    }

    /// Average perceptual luminance across stops (0...1), used to pick contrasting text on bubbles.
    var averageLuminance: CGFloat {
        guard !colors.isEmpty else { return 0.5 }
        var total: CGFloat = 0
        for c in colors {
            let srgb = c.usingColorSpace(.sRGB) ?? c
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            total += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return total / CGFloat(colors.count)
    }

    func withAngle(_ newAngle: CGFloat) -> AnnotationGradient {
        AnnotationGradient(colors: colors, locations: locations, angle: newAngle)
    }

    func makeCGGradient(colorSpace: CGColorSpace? = nil) -> CGGradient? {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let cgColors: [CGColor] = colors.map { ($0.usingColorSpace(.sRGB) ?? $0).cgColor }
        return locations.withUnsafeBufferPointer { locPtr in
            CGGradient(colorsSpace: space, colors: cgColors as CFArray, locations: locPtr.baseAddress)
        }
    }

    /// Compute edge-to-edge gradient start and end points inside `rect` at `angle`.
    func startEndPoints(in rect: NSRect) -> (NSPoint, NSPoint) {
        let rad = angle * .pi / 180.0
        let dx = cos(rad)
        let dy = sin(rad)
        let halfSpan = max(1, (rect.width * abs(dx) + rect.height * abs(dy)) / 2)
        let cx = rect.midX
        let cy = rect.midY
        return (
            NSPoint(x: cx - halfSpan * dx, y: cy - halfSpan * dy),
            NSPoint(x: cx + halfSpan * dx, y: cy + halfSpan * dy)
        )
    }

    static func == (lhs: AnnotationGradient, rhs: AnnotationGradient) -> Bool {
        guard abs(lhs.angle - rhs.angle) < 0.01,
              lhs.colors.count == rhs.colors.count,
              lhs.locations.count == rhs.locations.count
        else { return false }
        for (l, r) in zip(lhs.locations, rhs.locations) where abs(l - r) >= 0.002 {
            return false
        }
        for (lc, rc) in zip(lhs.colors, rhs.colors) {
            let ls = lc.usingColorSpace(.sRGB) ?? lc
            let rs = rc.usingColorSpace(.sRGB) ?? rc
            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
            var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
            ls.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
            rs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
            if abs(lr - rr) > 0.004 || abs(lg - rg) > 0.004 || abs(lb - rb) > 0.004 || abs(la - ra) > 0.004 {
                return false
            }
        }
        return true
    }

    // MARK: - Presets & Random Generator

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// 16 curated vivid gradients tuned for dark & light screenshot readability.
    static let presets: [AnnotationGradient] = [
        // 1. Violet → Electric Blue (vertical, matches classic curly brace look)
        AnnotationGradient(colors: [srgb(0.75, 0.24, 1.00), srgb(0.35, 0.44, 1.00)], angle: -90),
        // 2. Neon Mint → Yellow → Cyan (matches neon 3-stop frame)
        AnnotationGradient(colors: [srgb(0.24, 1.00, 0.62), srgb(1.00, 0.94, 0.20), srgb(0.20, 0.94, 1.00)], angle: -25),
        // 3. Amber Orange → Coral Red (matches warm orange-red frame)
        AnnotationGradient(colors: [srgb(1.00, 0.56, 0.00), srgb(1.00, 0.23, 0.30)], angle: -35),
        // 4. Hot Pink → Sunset Orange
        AnnotationGradient(colors: [srgb(1.00, 0.18, 0.58), srgb(1.00, 0.56, 0.22)], angle: -45),
        // 5. Aqua Cyan → Azure Blue
        AnnotationGradient(colors: [srgb(0.00, 0.96, 0.83), srgb(0.00, 0.53, 1.00)], angle: -45),
        // 6. Rose → Violet → Sky
        AnnotationGradient(colors: [srgb(1.00, 0.30, 0.48), srgb(0.62, 0.30, 0.87), srgb(0.23, 0.53, 1.00)], angle: -35),
        // 7. Emerald → Ocean Teal
        AnnotationGradient(colors: [srgb(0.18, 0.90, 0.62), srgb(0.05, 0.65, 0.91)], angle: -45),
        // 8. Gold → Crimson Pink
        AnnotationGradient(colors: [srgb(1.00, 0.82, 0.30), srgb(0.94, 0.28, 0.44)], angle: -45),
        // 9. Cyber Green → Cyan → Purple
        AnnotationGradient(colors: [srgb(0.00, 0.96, 0.63), srgb(0.00, 0.85, 0.96), srgb(0.61, 0.36, 0.90)], angle: -25),
        // 10. Ruby → Peach
        AnnotationGradient(colors: [srgb(0.92, 0.12, 0.32), srgb(0.99, 0.57, 0.24)], angle: -45),
        // 11. Indigo → Ice Blue
        AnnotationGradient(colors: [srgb(0.39, 0.40, 0.95), srgb(0.22, 0.74, 0.97)], angle: -90),
        // 12. Lime → Emerald
        AnnotationGradient(colors: [srgb(0.64, 0.96, 0.20), srgb(0.06, 0.78, 0.52)], angle: -45),
        // 13. Orchid → Magenta
        AnnotationGradient(colors: [srgb(0.94, 0.38, 0.98), srgb(0.55, 0.22, 0.96)], angle: -45),
        // 14. Tangerine → Lemon
        AnnotationGradient(colors: [srgb(1.00, 0.42, 0.16), srgb(1.00, 0.86, 0.20)], angle: 0),
        // 15. Glacier Blue → Lavender
        AnnotationGradient(colors: [srgb(0.22, 0.82, 1.00), srgb(0.72, 0.48, 1.00)], angle: -45),
        // 16. Prism Rainbow
        AnnotationGradient(
            colors: [srgb(1.00, 0.23, 0.42), srgb(1.00, 0.72, 0.00), srgb(0.13, 0.90, 0.55), srgb(0.18, 0.77, 1.00)],
            angle: -25
        ),
    ]

    /// Vibrant rainbow swatch used in UI buttons/cursors to represent Random Gradient mode.
    static let randomPreviewSwatch = presets[15]

    @MainActor private static var lastRandomHue: CGFloat?

    /// Generates a vivid, harmonious 2- or 3-stop gradient with guaranteed hue separation from the previous stroke.
    @MainActor
    static func nextRandom(angle preferredAngle: CGFloat? = nil) -> AnnotationGradient {
        var hue1 = CGFloat.random(in: 0..<1)
        if let prev = lastRandomHue {
            for _ in 0..<8 {
                let rawDiff = abs(hue1 - prev)
                let circularDiff = min(rawDiff, 1.0 - rawDiff)
                if circularDiff >= 0.16 { break }
                hue1 = CGFloat.random(in: 0..<1)
            }
        }
        lastRandomHue = hue1

        let direction: CGFloat = Bool.random() ? 1.0 : -1.0
        let delta = CGFloat.random(in: 0.10...0.24) * direction
        let useThreeStops = Int.random(in: 0..<100) < 35

        func wrapHue(_ h: CGFloat) -> CGFloat {
            let m = h.truncatingRemainder(dividingBy: 1.0)
            return m < 0 ? m + 1.0 : m
        }

        func vividColor(hue: CGFloat) -> NSColor {
            NSColor(
                calibratedHue: wrapHue(hue),
                saturation: CGFloat.random(in: 0.78...0.96),
                brightness: CGFloat.random(in: 0.90...1.0),
                alpha: 1.0
            ).usingColorSpace(.sRGB) ?? .systemPurple
        }

        var stops: [NSColor] = [
            vividColor(hue: hue1),
            vividColor(hue: hue1 + delta),
        ]
        if useThreeStops {
            stops.append(vividColor(hue: hue1 + delta * 1.9))
        }

        let candidateAngles: [CGFloat] = [-90, -45, -25, 0, 25, 45]
        let resolvedAngle = preferredAngle ?? candidateAngles.randomElement() ?? -45
        return AnnotationGradient(colors: stops, angle: resolvedAngle)
    }

    // MARK: - UserDefaults Serialization

    private struct EncodedGradient: Codable {
        let colorsRGBA: [[CGFloat]]
        let locations: [CGFloat]
        let angle: CGFloat
    }

    func toJSONData() -> Data? {
        let rgba: [[CGFloat]] = colors.map { color in
            let c = color.usingColorSpace(.sRGB) ?? color
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        return try? JSONEncoder().encode(EncodedGradient(colorsRGBA: rgba, locations: locations, angle: angle))
    }

    static func fromJSONData(_ data: Data) -> AnnotationGradient? {
        guard let decoded = try? JSONDecoder().decode(EncodedGradient.self, from: data),
              decoded.colorsRGBA.count >= 2
        else { return nil }
        let decodedColors: [NSColor] = decoded.colorsRGBA.map { rgba in
            guard rgba.count >= 4 else { return .systemPurple }
            return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
        return AnnotationGradient(colors: decodedColors, locations: decoded.locations, angle: decoded.angle)
    }
}

/// Active paint mode for newly drawn annotations.
enum DrawPaintMode: Equatable {
    case solid
    case gradient(AnnotationGradient)
    case randomGradient

    private enum StoredKind: String {
        case solid
        case gradient
        case randomGradient
    }

    static func loadPersisted() -> (mode: DrawPaintMode, lastGradient: AnnotationGradient) {
        let savedGradient: AnnotationGradient
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.drawGradient),
           let decoded = AnnotationGradient.fromJSONData(data)
        {
            savedGradient = decoded
        } else {
            savedGradient = AnnotationGradient.presets[0]
        }

        let rawKind = UserDefaults.standard.string(forKey: DefaultsKey.drawPaintMode) ?? StoredKind.solid.rawValue
        let kind = StoredKind(rawValue: rawKind) ?? .solid
        switch kind {
        case .solid:
            return (.solid, savedGradient)
        case .gradient:
            return (.gradient(savedGradient), savedGradient)
        case .randomGradient:
            return (.randomGradient, savedGradient)
        }
    }

    func persist(lastGradient: AnnotationGradient) {
        let kind: StoredKind
        let gradientToSave: AnnotationGradient
        switch self {
        case .solid:
            kind = .solid
            gradientToSave = lastGradient
        case .gradient(let grad):
            kind = .gradient
            gradientToSave = grad
        case .randomGradient:
            kind = .randomGradient
            gradientToSave = lastGradient
        }
        UserDefaults.standard.set(kind.rawValue, forKey: DefaultsKey.drawPaintMode)
        if let data = gradientToSave.toJSONData() {
            UserDefaults.standard.set(data, forKey: DefaultsKey.drawGradient)
        }
    }
}
