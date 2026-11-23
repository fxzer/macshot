import AppKit

// MARK: - NSColor Extension for Hex Parsing

extension NSColor {
    /// Create an NSColor from a hex string (e.g., "#FFFFFF" or "FFFFFF").
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb), hexSanitized.count == 6 else {
            return nil
        }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Color Gamut Enum

/// Color gamut / color space options for color sampler display.
enum ColorGamut: Int, CaseIterable {
    case native = 0      // Display native values (Display P3 on modern Macs)
    case p3 = 1          // Display P3
    case srgb = 2        // Display sRGB
    case displayRGB = 3  // Display generic RGB
    case adobeRGB = 4    // Display Adobe RGB

    var displayName: String {
        switch self {
        case .native: return L("Native")
        case .p3: return "P3"
        case .srgb: return "sRGB"
        case .displayRGB: return L("Generic RGB")
        case .adobeRGB: return "Adobe RGB"
        }
    }

    /// Get the CGColorSpace for this gamut (safe for 8-bit RGB CGContext).
    func targetCGColorSpace(source: CGColorSpace?) -> CGColorSpace {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        switch self {
        case .native:
            guard let source else { return p3 }
            let name = (source.name as String?) ?? ""
            let isExtendedOrLinear = name.localizedCaseInsensitiveContains("extended")
                || name.localizedCaseInsensitiveContains("linear")
            if source.model == .rgb && source.supportsOutput && source.numberOfComponents == 3 && !isExtendedOrLinear {
                return source
            }
            return source.isWideGamutRGB ? p3 : srgb
        case .p3:
            return p3
        case .srgb:
            return srgb
        case .displayRGB:
            return CGColorSpaceCreateDeviceRGB()
        case .adobeRGB:
            return CGColorSpace(name: CGColorSpace.adobeRGB1998) ?? srgb
        }
    }

    /// Get the matching NSColorSpace for display construction.
    func targetNSColorSpace(source: CGColorSpace?) -> NSColorSpace {
        if self == .displayRGB {
            return .deviceRGB
        }
        return NSColorSpace(cgColorSpace: targetCGColorSpace(source: source)) ?? .sRGB
    }
}

/// Pixel-perfect magnifier view for color sampler.
/// Shows a 15x15 pixel area magnified to 120x120 with nearest-neighbor interpolation,
/// crosshair cursor, and color/coordinate HUD.
final class ColorSamplerMagnifierView: NSView {

    // MARK: - Types

    enum ColorFormat: Int {
        case hex = 0
        case rgb = 1

        var displayName: String {
            switch self {
            case .hex: return "HEX"
            case .rgb: return "RGB"
            }
        }
    }

    // MARK: - Configuration

    private let magnifierWidth: CGFloat = 140  // Width stays 140
    private let magnifierHeight: CGFloat = 100  // Reduced height for better proportion
    private let sourceSize: CGFloat = 15  // Capture 15x15 pixel area
    private let hudHeight: CGFloat = 40
    private let magnifierToHudGap: CGFloat = 0  // No gap between magnifier and HUD
    private let hudPadding: CGFloat = 6  // Internal padding for HUD text
    private let crosshairColor = NSColor.white.withAlphaComponent(0.6)
    private let crosshairWidth: CGFloat = 1.0
    private let valueFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private let coordinateFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
    private let valueColor = NSColor.white
    private let coordinateColor = NSColor.white.withAlphaComponent(0.6)

    var magnificationLevel: CGFloat { magnifierWidth / sourceSize }

    // MARK: - State

    private var cachedScreenImage: NSImage?
    private var currentColor: NSColor = .white
    private var currentHexColor: String = "#FFFFFF"
    private var currentPoint: NSPoint = .zero
    // Store raw RGB values for format switching
    private var currentRGB: (r: Int, g: Int, b: Int) = (255, 255, 255)

    // Color format (synced with UserDefaults)
    private let formatKey = "colorSamplerFormat"
    var currentFormat: ColorFormat {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: formatKey)
            return ColorFormat(rawValue: rawValue) ?? .hex
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: formatKey)
            // Don't set needsDisplay here - let toggleFormat handle it
        }
    }

    // Callbacks
    var onColorCopied: ((String, ColorFormat) -> Void)?
    var onExitRequested: (() -> Void)?

    /// Whether to exit after copying color. true for selecting state, false for annotation state.
    var exitAfterCopy: Bool = true

    // MARK: - Initialization

    init() {
        super.init(frame: .zero)
        setFrameSize(intrinsicContentSize)
        wantsLayer = true
        layer?.magnificationFilter = .nearest  // 🔑 Pixel-perfect scaling
        layer?.minificationFilter = .nearest
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Don't receive mouse events — let them pass through to the overlay
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        return NSSize(width: magnifierWidth, height: magnifierHeight + hudHeight + magnifierToHudGap)
    }

    // MARK: - Public API

    static func parseHexRGB(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        return (
            r: Int((rgb & 0xFF0000) >> 16),
            g: Int((rgb & 0x00FF00) >> 8),
            b: Int(rgb & 0x0000FF)
        )
    }

    /// Update the magnifier with a new screen position, image, and pre-extracted color.
    /// - Parameters:
    ///   - screenPoint: The position in screenshot image point coordinates
    ///   - screenImage: The screenshot image
    ///   - hexColor: Pre-extracted hex color string in the active gamut
    ///   - color: Optional pre-extracted NSColor in the target color space
    func update(at screenPoint: NSPoint, screenImage: NSImage, hexColor: String = "#FFFFFF", color: NSColor? = nil) {
        self.currentPoint = screenPoint
        self.cachedScreenImage = screenImage
        self.currentHexColor = hexColor

        if let rgb = Self.parseHexRGB(hexColor) {
            self.currentRGB = rgb
            self.currentColor = color ?? NSColor(hex: hexColor) ?? .white
        } else {
            self.currentColor = color ?? .white
            self.currentRGB = (255, 255, 255)
        }

        needsDisplay = true
    }

    /// Toggle between HEX and RGB format (triggered by Shift key).
    func toggleFormat() {
        // Switch format
        let newFormat: ColorFormat = currentFormat == .hex ? .rgb : .hex
        guard newFormat != currentFormat else { return }
        currentFormat = newFormat

        // Avoid synchronous display/update here.
        // Pressing Shift can also refresh SwiftUI preferences via AppStorage;
        // invalidating the view is enough and avoids re-entrant redraw churn.
        layer?.setNeedsDisplay()
        setNeedsDisplay(bounds)
    }

    /// Copy current color in the selected format to clipboard.
    func copyColorAndExit() {
        // Use stored RGB values for accurate color copying
        let colorString = formatColorFromRGB(currentRGB, as: currentFormat)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(colorString, forType: .string)

        onColorCopied?(colorString, currentFormat)

        // Only exit if exitAfterCopy is true (selecting state)
        if exitAfterCopy {
            onExitRequested?()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let screenImage = cachedScreenImage else { return }

        // 1. Calculate source region (15x15 pixels around cursor)
        let halfSource = sourceSize / 2
        let sourceRect = NSRect(
            x: currentPoint.x - halfSource,
            y: currentPoint.y - halfSource,
            width: sourceSize,
            height: sourceSize
        )

        // 2. Draw pixelated magnified image
        context.interpolationQuality = .none  // 🔑 Disable anti-aliasing

        let magnifierRect = NSRect(x: 0, y: hudHeight + magnifierToHudGap, width: magnifierWidth, height: magnifierHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        screenImage.draw(
            in: magnifierRect,
            from: sourceRect,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )

        // 3. Draw white border around magnifier
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(0.5)
        context.stroke(magnifierRect)

        // 4. Draw crosshair
        drawCrosshair(in: context, rect: magnifierRect)

        // 4. Draw HUD background
        let hudRect = NSRect(x: 0, y: 0, width: magnifierWidth, height: hudHeight)
        drawHUDBackground(in: hudRect)

        // 5. Draw color value and coordinates
        drawHUDContent(in: hudRect)
    }

    private func drawCrosshair(in context: CGContext, rect: NSRect) {
        context.setStrokeColor(crosshairColor.cgColor)
        context.setLineWidth(crosshairWidth)

        let centerX = rect.midX
        let centerY = rect.midY

        // Vertical line
        context.move(to: CGPoint(x: centerX, y: rect.minY))
        context.addLine(to: CGPoint(x: centerX, y: rect.maxY))

        // Horizontal line
        context.move(to: CGPoint(x: rect.minX, y: centerY))
        context.addLine(to: CGPoint(x: rect.maxX, y: centerY))

        context.strokePath()

        // Draw a small highlight box around the center pixel
        let cellSize = magnifierWidth / sourceSize
        let centerPixelRect = CGRect(
            x: centerX - cellSize / 2,
            y: centerY - cellSize / 2,
            width: cellSize,
            height: cellSize
        )

        context.setStrokeColor(NSColor.red.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.5)
        context.stroke(centerPixelRect)
    }

    private func drawHUDBackground(in rect: NSRect) {
        // No rounded corners - match the magnifier's sharp edges
        NSColor.black.withAlphaComponent(0.7).setFill()
        rect.fill()
    }

    private func drawHUDContent(in rect: NSRect) {
        // Use stored RGB values to format color string (works correctly when switching formats)
        let colorString = formatColorFromRGB(currentRGB, as: currentFormat)
        let coordString = String(format: "(%.0f, %.0f)", currentPoint.x, currentPoint.y)

        let colorAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: valueColor,
        ]

        let coordAttrs: [NSAttributedString.Key: Any] = [
            .font: coordinateFont,
            .foregroundColor: coordinateColor,
        ]

        let colorSize = colorString.size(withAttributes: colorAttrs)
        let coordSize = coordString.size(withAttributes: coordAttrs)

        // Draw color value (top)
        let colorX = (rect.width - colorSize.width) / 2
        let colorY = rect.maxY - hudPadding - colorSize.height - 4
        colorString.draw(at: CGPoint(x: colorX, y: colorY), withAttributes: colorAttrs)

        // Draw coordinates (bottom)
        let coordX = (rect.width - coordSize.width) / 2
        let coordY = rect.minY + hudPadding
        coordString.draw(at: CGPoint(x: coordX, y: coordY), withAttributes: coordAttrs)
    }

    // MARK: - Helpers

    private func formatColor(_ color: NSColor, as format: ColorFormat) -> String {
        guard let rgbColor = color.usingColorSpace(.sRGB) else { return "#000000" }

        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))

        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "RGB(\(r), \(g), \(b))"
        }
    }

    /// Format color from stored RGB values (used for display and format switching).
    private func formatColorFromRGB(_ rgb: (r: Int, g: Int, b: Int), as format: ColorFormat) -> String {
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
        case .rgb:
            return "RGB(\(rgb.r), \(rgb.g), \(rgb.b))"
        }
    }
}
