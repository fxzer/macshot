import Cocoa
import SwiftUI

/// Beautify rendering mode
enum BeautifyMode: Int {
    case window = 0   // macOS window chrome with traffic lights
    case rounded = 1  // just rounded corners, no title bar
}

/// Mesh gradient definition for macOS 15+ (3×3 grid of control points with colors)
struct MeshGradientDef {
    let width: Int   // always 3
    let height: Int  // always 3
    let points: [SIMD2<Float>]   // 9 points (row-major)
    let colors: [NSColor]        // 9 colors
}

/// A beautify gradient style definition
struct BeautifyStyle {
    let stops: [(NSColor, CGFloat)]  // (color, location 0..1) — used for linear gradients & macOS 14 fallback
    let angle: CGFloat               // degrees, 0 = left→right, 90 = bottom→top
    let meshDef: MeshGradientDef?    // non-nil = mesh gradient (macOS 15+)

    init(stops: [(NSColor, CGFloat)], angle: CGFloat = 135) {
        self.stops = stops
        self.angle = angle
        self.meshDef = nil
    }

    init(stops: [(NSColor, CGFloat)], angle: CGFloat = 135, mesh: MeshGradientDef) {
        self.stops = stops
        self.angle = angle
        self.meshDef = mesh
    }
}

/// Helper function to create a mesh gradient style
private func meshStyle(points: [SIMD2<Float>], colors: [NSColor], fallbackStops: [(NSColor, CGFloat)], fallbackAngle: CGFloat = 135) -> BeautifyStyle {
    BeautifyStyle(
        stops: fallbackStops,
        angle: fallbackAngle,
        mesh: MeshGradientDef(width: 3, height: 3, points: points, colors: colors)
    )
}

/// All available beautify gradient styles
let beautifyStyles: [BeautifyStyle] = {
    var s: [BeautifyStyle] = []

    // Mesh gradients — macOS 15+ only (18 = 3 rows of 6)
    // Bold colors, high contrast between neighbors, aggressive point displacement
    if #available(macOS 15.0, *) {
        let c = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
        s.append(contentsOf: [
            // Row 1
            // Ultraviolet — vivid purple/magenta with electric blue
            meshStyle( points: [
                SIMD2(0, 0),    SIMD2(0.7, 0),   SIMD2(1, 0),
                SIMD2(0, 0.3),  SIMD2(0.25, 0.7), SIMD2(1, 0.6),
                SIMD2(0, 1),    SIMD2(0.65, 1),  SIMD2(1, 1),
            ], colors: [
                c(0.55, 0.10, 0.95), c(0.80, 0.15, 0.80), c(1.0, 0.30, 0.55),
                c(0.30, 0.15, 0.98), c(0.90, 0.40, 0.90), c(1.0, 0.50, 0.60),
                c(0.15, 0.20, 0.95), c(0.50, 0.25, 0.95), c(0.85, 0.35, 0.70),
            ], fallbackStops: [
                (c(0.55, 0.10, 0.95), 0), (c(0.90, 0.40, 0.90), 0.5), (c(0.85, 0.35, 0.70), 1),
            ]),
            // Inferno — hot pink/red smashing into orange/yellow
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.3, 0),   SIMD2(1, 0),
                SIMD2(0, 0.65), SIMD2(0.75, 0.35), SIMD2(1, 0.5),
                SIMD2(0, 1),    SIMD2(0.4, 1),   SIMD2(1, 1),
            ], colors: [
                c(1.0, 0.25, 0.40), c(1.0, 0.50, 0.20), c(1.0, 0.85, 0.25),
                c(0.95, 0.15, 0.50), c(1.0, 0.65, 0.30), c(1.0, 0.90, 0.40),
                c(0.85, 0.10, 0.35), c(1.0, 0.40, 0.25), c(1.0, 0.75, 0.20),
            ], fallbackStops: [
                (c(1.0, 0.25, 0.40), 0), (c(1.0, 0.65, 0.30), 0.5), (c(1.0, 0.85, 0.25), 1),
            ]),
            // Deep Ocean — rich blue/teal with bright cyan burst
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.6, 0),   SIMD2(1, 0),
                SIMD2(0, 0.4),  SIMD2(0.3, 0.65), SIMD2(1, 0.55),
                SIMD2(0, 1),    SIMD2(0.7, 1),   SIMD2(1, 1),
            ], colors: [
                c(0.05, 0.15, 0.60), c(0.10, 0.40, 0.90), c(0.05, 0.20, 0.70),
                c(0.08, 0.25, 0.75), c(0.20, 0.90, 0.95), c(0.10, 0.50, 0.85),
                c(0.03, 0.10, 0.45), c(0.08, 0.35, 0.80), c(0.05, 0.18, 0.55),
            ], fallbackStops: [
                (c(0.05, 0.15, 0.60), 0), (c(0.20, 0.90, 0.95), 0.5), (c(0.05, 0.18, 0.55), 1),
            ]),
            // Candy Floss — saturated pink/peach/lavender
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.45, 0),  SIMD2(1, 0),
                SIMD2(0, 0.6),  SIMD2(0.7, 0.4),  SIMD2(1, 0.55),
                SIMD2(0, 1),    SIMD2(0.35, 1),  SIMD2(1, 1),
            ], colors: [
                c(1.0, 0.60, 0.70), c(1.0, 0.75, 0.55), c(0.95, 0.55, 0.75),
                c(0.95, 0.50, 0.80), c(1.0, 0.85, 0.70), c(0.80, 0.55, 0.95),
                c(0.85, 0.45, 0.90), c(0.95, 0.70, 0.80), c(0.70, 0.50, 0.98),
            ], fallbackStops: [
                (c(1.0, 0.60, 0.70), 0), (c(1.0, 0.85, 0.70), 0.5), (c(0.70, 0.50, 0.98), 1),
            ]),
            // Emerald Fire — vivid green clashing with hot orange
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.55, 0),  SIMD2(1, 0),
                SIMD2(0, 0.5),  SIMD2(0.25, 0.55), SIMD2(1, 0.4),
                SIMD2(0, 1),    SIMD2(0.6, 1),   SIMD2(1, 1),
            ], colors: [
                c(0.10, 0.85, 0.40), c(0.30, 0.95, 0.50), c(0.90, 0.75, 0.15),
                c(0.05, 0.70, 0.35), c(0.60, 0.90, 0.30), c(1.0, 0.60, 0.15),
                c(0.08, 0.55, 0.30), c(0.40, 0.80, 0.25), c(1.0, 0.45, 0.10),
            ], fallbackStops: [
                (c(0.10, 0.85, 0.40), 0), (c(0.60, 0.90, 0.30), 0.5), (c(1.0, 0.45, 0.10), 1),
            ]),
            // Electric Dusk — neon pink/orange sunset over deep blue
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.5, 0),   SIMD2(1, 0),
                SIMD2(0, 0.35), SIMD2(0.65, 0.55), SIMD2(1, 0.4),
                SIMD2(0, 1),    SIMD2(0.45, 1),  SIMD2(1, 1),
            ], colors: [
                c(1.0, 0.50, 0.30), c(1.0, 0.35, 0.50), c(0.90, 0.25, 0.70),
                c(1.0, 0.65, 0.20), c(0.85, 0.30, 0.60), c(0.45, 0.15, 0.80),
                c(0.15, 0.10, 0.50), c(0.10, 0.12, 0.55), c(0.08, 0.08, 0.40),
            ], fallbackStops: [
                (c(1.0, 0.50, 0.30), 0), (c(0.85, 0.30, 0.60), 0.5), (c(0.08, 0.08, 0.40), 1),
            ], fallbackAngle: 180),

            // Row 2
            // Plasma — magenta/cyan/yellow high-energy
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.25, 0),  SIMD2(1, 0),
                SIMD2(0, 0.7),  SIMD2(0.8, 0.3),  SIMD2(1, 0.5),
                SIMD2(0, 1),    SIMD2(0.55, 1),  SIMD2(1, 1),
            ], colors: [
                c(0.95, 0.20, 0.60), c(1.0, 0.50, 0.15), c(1.0, 0.90, 0.20),
                c(0.70, 0.10, 0.90), c(0.20, 0.85, 0.85), c(0.50, 0.95, 0.40),
                c(0.25, 0.15, 0.95), c(0.15, 0.60, 0.95), c(0.10, 0.90, 0.70),
            ], fallbackStops: [
                (c(0.95, 0.20, 0.60), 0), (c(0.20, 0.85, 0.85), 0.5), (c(0.25, 0.15, 0.95), 1),
            ]),
            // Silk Storm — whites/grays with vivid color pockets
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.65, 0),  SIMD2(1, 0),
                SIMD2(0, 0.45), SIMD2(0.3, 0.6),  SIMD2(1, 0.55),
                SIMD2(0, 1),    SIMD2(0.5, 1),   SIMD2(1, 1),
            ], colors: [
                c(0.92, 0.90, 0.95), c(0.70, 0.80, 0.98), c(0.55, 0.60, 0.98),
                c(0.95, 0.85, 0.88), c(0.85, 0.75, 0.95), c(0.50, 0.70, 0.95),
                c(0.98, 0.92, 0.88), c(0.90, 0.82, 0.90), c(0.65, 0.75, 0.95),
            ], fallbackStops: [
                (c(0.92, 0.90, 0.95), 0), (c(0.85, 0.75, 0.95), 0.5), (c(0.65, 0.75, 0.95), 1),
            ]),
            // Opal — orange/teal/violet iridescent clash
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.7, 0),   SIMD2(1, 0),
                SIMD2(0, 0.4),  SIMD2(0.25, 0.65), SIMD2(1, 0.5),
                SIMD2(0, 1),    SIMD2(0.6, 1),   SIMD2(1, 1),
            ], colors: [
                c(1.0, 0.60, 0.15), c(1.0, 0.85, 0.30), c(0.20, 0.90, 0.90),
                c(0.95, 0.40, 0.40), c(0.65, 0.70, 0.95), c(0.15, 0.75, 0.95),
                c(0.60, 0.15, 0.85), c(0.40, 0.35, 0.95), c(0.20, 0.55, 0.95),
            ], fallbackStops: [
                (c(1.0, 0.60, 0.15), 0), (c(0.65, 0.70, 0.95), 0.5), (c(0.60, 0.15, 0.85), 1),
            ]),
            // Nebula — deep purple/blue with hot pink explosion
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.55, 0),  SIMD2(1, 0),
                SIMD2(0, 0.55), SIMD2(0.3, 0.4),  SIMD2(1, 0.65),
                SIMD2(0, 1),    SIMD2(0.7, 1),   SIMD2(1, 1),
            ], colors: [
                c(0.10, 0.05, 0.40), c(0.30, 0.08, 0.60), c(0.08, 0.15, 0.55),
                c(0.50, 0.10, 0.65), c(1.0, 0.30, 0.55), c(0.15, 0.30, 0.80),
                c(0.65, 0.15, 0.50), c(0.35, 0.20, 0.70), c(0.10, 0.40, 0.75),
            ], fallbackStops: [
                (c(0.10, 0.05, 0.40), 0), (c(1.0, 0.30, 0.55), 0.5), (c(0.10, 0.40, 0.75), 1),
            ]),
            // Sunset Blaze — intense orange/red to deep indigo
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.5, 0),   SIMD2(1, 0),
                SIMD2(0, 0.35), SIMD2(0.4, 0.55), SIMD2(1, 0.4),
                SIMD2(0, 1),    SIMD2(0.6, 1),   SIMD2(1, 1),
            ], colors: [
                c(1.0, 0.85, 0.25), c(1.0, 0.55, 0.15), c(1.0, 0.30, 0.25),
                c(1.0, 0.50, 0.10), c(0.90, 0.25, 0.40), c(0.55, 0.12, 0.60),
                c(0.12, 0.08, 0.35), c(0.10, 0.06, 0.45), c(0.08, 0.05, 0.35),
            ], fallbackStops: [
                (c(1.0, 0.85, 0.25), 0), (c(0.90, 0.25, 0.40), 0.5), (c(0.08, 0.05, 0.35), 1),
            ], fallbackAngle: 180),
            // Lagoon — vivid teal/cyan/deep blue tropical
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.4, 0),   SIMD2(1, 0),
                SIMD2(0, 0.5),  SIMD2(0.7, 0.6),  SIMD2(1, 0.45),
                SIMD2(0, 1),    SIMD2(0.35, 1),  SIMD2(1, 1),
            ], colors: [
                c(0.10, 0.95, 0.70), c(0.20, 0.95, 0.90), c(0.15, 0.65, 0.98),
                c(0.05, 0.80, 0.55), c(0.15, 0.90, 0.85), c(0.25, 0.50, 0.95),
                c(0.03, 0.55, 0.40), c(0.08, 0.70, 0.65), c(0.10, 0.35, 0.85),
            ], fallbackStops: [
                (c(0.10, 0.95, 0.70), 0), (c(0.15, 0.90, 0.85), 0.5), (c(0.10, 0.35, 0.85), 1),
            ]),

            // Row 3 — maximum drama
            // Molten Core — black with searing orange/white-hot center
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.6, 0),   SIMD2(1, 0),
                SIMD2(0, 0.5),  SIMD2(0.35, 0.45), SIMD2(1, 0.6),
                SIMD2(0, 1),    SIMD2(0.5, 1),   SIMD2(1, 1),
            ], colors: [
                c(0.08, 0.05, 0.05), c(0.20, 0.05, 0.02), c(0.10, 0.03, 0.05),
                c(0.30, 0.08, 0.02), c(1.0, 0.70, 0.15), c(0.45, 0.10, 0.03),
                c(0.05, 0.03, 0.03), c(0.85, 0.35, 0.05), c(0.08, 0.04, 0.04),
            ], fallbackStops: [
                (c(0.08, 0.05, 0.05), 0), (c(1.0, 0.70, 0.15), 0.5), (c(0.08, 0.04, 0.04), 1),
            ]),
            // Aurora Borealis — green/cyan curtains over dark sky
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.35, 0),  SIMD2(1, 0),
                SIMD2(0, 0.6),  SIMD2(0.75, 0.35), SIMD2(1, 0.55),
                SIMD2(0, 1),    SIMD2(0.45, 1),  SIMD2(1, 1),
            ], colors: [
                c(0.05, 0.90, 0.50), c(0.10, 0.95, 0.80), c(0.20, 0.70, 0.95),
                c(0.08, 0.70, 0.40), c(0.15, 0.85, 0.70), c(0.30, 0.50, 0.90),
                c(0.03, 0.08, 0.18), c(0.05, 0.10, 0.25), c(0.04, 0.06, 0.20),
            ], fallbackStops: [
                (c(0.05, 0.90, 0.50), 0), (c(0.15, 0.85, 0.70), 0.5), (c(0.04, 0.06, 0.20), 1),
            ], fallbackAngle: 180),
            // Prism Burst — rainbow refraction: every color at full saturation
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.3, 0),   SIMD2(1, 0),
                SIMD2(0, 0.55), SIMD2(0.7, 0.5),  SIMD2(1, 0.45),
                SIMD2(0, 1),    SIMD2(0.4, 1),   SIMD2(1, 1),
            ], colors: [
                c(0.20, 0.40, 1.0),  c(1.0, 0.60, 0.10), c(1.0, 0.25, 0.50),
                c(0.10, 0.85, 0.70), c(1.0, 0.95, 0.50), c(0.90, 0.20, 0.80),
                c(0.15, 0.90, 0.35), c(0.95, 0.80, 0.15), c(0.60, 0.10, 0.95),
            ], fallbackStops: [
                (c(0.20, 0.40, 1.0), 0), (c(1.0, 0.95, 0.50), 0.5), (c(0.60, 0.10, 0.95), 1),
            ]),
            // Velvet Night — dark burgundy/plum with rose-gold glow
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.55, 0),  SIMD2(1, 0),
                SIMD2(0, 0.55), SIMD2(0.3, 0.4),  SIMD2(1, 0.5),
                SIMD2(0, 1),    SIMD2(0.65, 1),  SIMD2(1, 1),
            ], colors: [
                c(0.25, 0.05, 0.15), c(0.40, 0.08, 0.20), c(0.30, 0.06, 0.25),
                c(0.35, 0.10, 0.18), c(0.95, 0.65, 0.50), c(0.45, 0.12, 0.35),
                c(0.20, 0.05, 0.15), c(0.60, 0.30, 0.30), c(0.25, 0.08, 0.22),
            ], fallbackStops: [
                (c(0.25, 0.05, 0.15), 0), (c(0.95, 0.65, 0.50), 0.5), (c(0.25, 0.08, 0.22), 1),
            ]),
            // Cosmic Reef — deep space with teal/coral/gold nebula clouds
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.65, 0),  SIMD2(1, 0),
                SIMD2(0, 0.4),  SIMD2(0.25, 0.65), SIMD2(1, 0.55),
                SIMD2(0, 1),    SIMD2(0.55, 1),  SIMD2(1, 1),
            ], colors: [
                c(0.06, 0.04, 0.20), c(0.15, 0.60, 0.70), c(0.08, 0.08, 0.30),
                c(0.90, 0.45, 0.30), c(0.10, 0.10, 0.25), c(0.20, 0.50, 0.80),
                c(1.0, 0.80, 0.25),  c(0.06, 0.06, 0.22), c(0.12, 0.35, 0.65),
            ], fallbackStops: [
                (c(0.06, 0.04, 0.20), 0), (c(0.90, 0.45, 0.30), 0.4), (c(1.0, 0.80, 0.25), 1),
            ]),
            // Ember Glow — searing warm gradient: gold/coral/crimson
            meshStyle(points: [
                SIMD2(0, 0),    SIMD2(0.45, 0),  SIMD2(1, 0),
                SIMD2(0, 0.6),  SIMD2(0.7, 0.4),  SIMD2(1, 0.5),
                SIMD2(0, 1),    SIMD2(0.35, 1),  SIMD2(1, 1),
            ], colors: [
                c(1.0, 0.85, 0.35), c(1.0, 0.65, 0.25), c(1.0, 0.50, 0.30),
                c(1.0, 0.55, 0.20), c(0.95, 0.40, 0.35), c(0.90, 0.30, 0.45),
                c(0.80, 0.20, 0.25), c(0.90, 0.30, 0.30), c(0.75, 0.15, 0.40),
            ], fallbackStops: [
                (c(1.0, 0.85, 0.35), 0), (c(0.95, 0.40, 0.35), 0.5), (c(0.75, 0.15, 0.40), 1),
            ]),
        ])
    }

    // Linear gradients
    s.append(contentsOf: [
        // Warm / sunset / orange
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 1.00, green: 0.60, blue: 0.15, alpha: 1), 0),
            (NSColor(calibratedRed: 0.98, green: 0.35, blue: 0.30, alpha: 1), 0.45),
            (NSColor(calibratedRed: 0.85, green: 0.18, blue: 0.45, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.68, alpha: 1), 0),
            (NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.55, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.90, green: 0.25, blue: 0.10, alpha: 1), 0),
            (NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.05, alpha: 1), 0.5),
            (NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.20, alpha: 1), 1),
        ], angle: 135),

        // Blues / cool
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.10, green: 0.70, blue: 0.95, alpha: 1), 0),
            (NSColor(calibratedRed: 0.22, green: 0.40, blue: 0.90, alpha: 1), 0.55),
            (NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.80, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.72, green: 0.90, blue: 0.98, alpha: 1), 0),
            (NSColor(calibratedRed: 0.50, green: 0.75, blue: 0.95, alpha: 1), 1),
        ], angle: 160),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.05, green: 0.15, blue: 0.55, alpha: 1), 0),
            (NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.85, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.30, green: 0.60, blue: 0.95, alpha: 1), 1),
        ], angle: 150),

        // Pink / purple / vibrant
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.98, green: 0.40, blue: 0.55, alpha: 1), 0),
            (NSColor(calibratedRed: 0.90, green: 0.30, blue: 0.70, alpha: 1), 0.4),
            (NSColor(calibratedRed: 0.60, green: 0.25, blue: 0.90, alpha: 1), 0.75),
            (NSColor(calibratedRed: 0.35, green: 0.30, blue: 0.95, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.45, alpha: 1), 0),
            (NSColor(calibratedRed: 0.92, green: 0.50, blue: 0.55, alpha: 1), 1),
        ], angle: 150),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.75, green: 0.65, blue: 0.95, alpha: 1), 0),
            (NSColor(calibratedRed: 0.90, green: 0.78, blue: 0.98, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.98, green: 0.20, blue: 0.60, alpha: 1), 0),
            (NSColor(calibratedRed: 0.90, green: 0.50, blue: 0.15, alpha: 1), 0.3),
            (NSColor(calibratedRed: 0.20, green: 0.90, blue: 0.60, alpha: 1), 0.6),
            (NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.98, alpha: 1), 1),
        ], angle: 135),

        // Greens / nature
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.30, alpha: 1), 0),
            (NSColor(calibratedRed: 0.10, green: 0.60, blue: 0.40, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.50, alpha: 1), 1),
        ], angle: 150),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.10, green: 0.75, blue: 0.50, alpha: 1), 0),
            (NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.80, alpha: 1), 0.35),
            (NSColor(calibratedRed: 0.40, green: 0.30, blue: 0.85, alpha: 1), 0.65),
            (NSColor(calibratedRed: 0.70, green: 0.25, blue: 0.75, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.55, green: 0.90, blue: 0.20, alpha: 1), 0),
            (NSColor(calibratedRed: 0.30, green: 0.75, blue: 0.35, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.15, green: 0.60, blue: 0.45, alpha: 1), 1),
        ], angle: 135),

        // Multicolor / dreamy
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.98, alpha: 1), 0),
            (NSColor(calibratedRed: 0.75, green: 0.60, blue: 0.95, alpha: 1), 0.35),
            (NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.70, alpha: 1), 0.7),
            (NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.40, alpha: 1), 1),
        ], angle: 150),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.30, alpha: 1), 0),
            (NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.20, alpha: 1), 0.25),
            (NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.40, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.30, green: 0.60, blue: 0.95, alpha: 1), 0.75),
            (NSColor(calibratedRed: 0.70, green: 0.30, blue: 0.90, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.35, alpha: 1), 0),
            (NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.60, alpha: 1), 0.4),
            (NSColor(calibratedRed: 0.85, green: 0.40, blue: 0.50, alpha: 1), 0.7),
            (NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.40, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.40, green: 0.90, blue: 0.85, alpha: 1), 0),
            (NSColor(calibratedRed: 0.50, green: 0.65, blue: 0.98, alpha: 1), 0.35),
            (NSColor(calibratedRed: 0.80, green: 0.50, blue: 0.95, alpha: 1), 0.65),
            (NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.80, alpha: 1), 1),
        ], angle: 120),

        // Dark / moody
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.15, alpha: 1), 0),
            (NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.30, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.45, alpha: 1), 1),
        ], angle: 150),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.12, alpha: 1), 0),
            (NSColor(calibratedRed: 0.05, green: 0.15, blue: 0.30, alpha: 1), 0.4),
            (NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.50, alpha: 1), 0.75),
            (NSColor(calibratedRed: 0.15, green: 0.50, blue: 0.55, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.03, alpha: 1), 0),
            (NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.15, alpha: 1), 1),
        ], angle: 135),

        // Clean / neutral / light
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), 0),
            (NSColor(calibratedRed: 0.90, green: 0.91, blue: 0.93, alpha: 1), 1),
        ], angle: 160),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.90, alpha: 1), 0),
            (NSColor(calibratedRed: 0.95, green: 0.90, blue: 0.80, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.30, green: 0.35, blue: 0.42, alpha: 1), 0),
            (NSColor(calibratedRed: 0.45, green: 0.50, blue: 0.58, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.60, green: 0.65, blue: 0.72, alpha: 1), 1),
        ], angle: 135),
        BeautifyStyle(stops: [
            (NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.18, alpha: 1), 0),
            (NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.30, alpha: 1), 0.5),
            (NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.40, alpha: 1), 1),
        ], angle: 150),
    ])

    // Extra non-mesh gradients
    let c = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
    s.append(contentsOf: [
        BeautifyStyle(stops: [(c(0.0, 0.6, 0.4), 0), (c(0.1, 0.85, 0.6), 0.5), (c(0.0, 0.5, 0.3), 1)], angle: 135),
        BeautifyStyle(stops: [(c(0.7, 0.1, 0.2), 0), (c(0.9, 0.2, 0.3), 0.5), (c(0.55, 0.05, 0.15), 1)], angle: 150),
        BeautifyStyle(stops: [(c(0.1, 0.15, 0.5), 0), (c(0.2, 0.3, 0.75), 0.5), (c(0.05, 0.1, 0.4), 1)], angle: 120),
        BeautifyStyle(stops: [(c(0.85, 0.75, 0.55), 0), (c(0.95, 0.88, 0.7), 0.5), (c(0.75, 0.65, 0.45), 1)], angle: 135),
        BeautifyStyle(stops: [(c(0.95, 0.95, 0.95), 0), (c(1.0, 1.0, 1.0), 0.5), (c(0.92, 0.92, 0.92), 1)], angle: 180),
        BeautifyStyle(stops: [(c(0.05, 0.05, 0.05), 0), (c(0.12, 0.12, 0.12), 0.5), (c(0.0, 0.0, 0.0), 1)], angle: 180),
    ])

    return s
}()

/// Configuration for beautify effect rendering
struct BeautifyConfig {
    var mode: BeautifyMode = .window
    var styleIndex: Int = 0
    var padding: CGFloat = 48       // 16..96
    var cornerRadius: CGFloat = 10  // 0..100 (UI slider range)
    var shadowRadius: CGFloat = 20  // 0..100
    var bgRadius: CGFloat = 8       // 0..30 (outer background corner radius)
    var isWindowSnap: Bool = false  // true = selection came from window snap, skip synthetic title bar
    var customBackgroundImage: NSImage?  // custom image background (nil = use gradient)
    var backgroundBlur: CGFloat = 0     // 0..50 blur radius for custom background
    /// Pre-rendered CGImage of custom background (with blur applied). Set via `prepareBackgroundCache()`.
    var cachedBackgroundCGImage: CGImage?

    /// Whether a custom background image is active
    var isCustomBackground: Bool { customBackgroundImage != nil }

    /// Pre-render the custom background image (with blur) into a CGImage for fast drawing.
    /// Call once when the image or blur changes, not on every draw.
    /// - Parameter blurFunction: A function that applies Gaussian blur to a CGImage
    mutating func prepareBackgroundCache(blurFunction: (CGImage, CGFloat) -> CGImage?) {
        guard let bgImage = customBackgroundImage else {
            cachedBackgroundCGImage = nil
            return
        }
        var source = bgImage
        if backgroundBlur > 0,
           let cgImg = bgImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let blurredCG = blurFunction(cgImg, backgroundBlur) {
            source = NSImage(cgImage: blurredCG, size: bgImage.size)
        }
        cachedBackgroundCGImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Convenience: the resolved style from styles array
    var style: BeautifyStyle {
        let count = beautifyStyles.count
        let idx = ((styleIndex % count) + count) % count
        return beautifyStyles[idx]
    }
}
