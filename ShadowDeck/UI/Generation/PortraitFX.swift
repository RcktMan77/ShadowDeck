//
//  PortraitFX.swift
//  ShadowDeck
//
//  FX landmarks measured from portrait pixels (864×1152) via luminance/color
//  analysis, drawn in the same letterboxed image rect as the static art so
//  effects track features (fists, lightning path, laptop screen, etc.).
//

import SwiftUI

/// Normalized (0…1) coords in full image space (top-left origin).
struct NormRect: Sendable {
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat

    func cgRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + x * imageRect.width,
            y: imageRect.minY + y * imageRect.height,
            width: w * imageRect.width,
            height: h * imageRect.height
        )
    }
}

struct NormPoint: Sendable {
    var x: CGFloat
    var y: CGFloat

    func cgPoint(in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + x * imageRect.width,
            y: imageRect.minY + y * imageRect.height
        )
    }
}

enum PortraitLayout {
    /// Source art is 864×1152 (3:4).
    static let imageAspect: CGFloat = 864.0 / 1152.0

    /// Letterboxed rect where the image is drawn under `.scaledToFit`.
    static func imageRect(in viewSize: CGSize) -> CGRect {
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        if viewAspect > imageAspect {
            let h = viewSize.height
            let w = h * imageAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: h)
        } else {
            let w = viewSize.width
            let h = w / imageAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: w, height: h)
        }
    }
}

enum PortraitFX {
    // MARK: - Measured landmarks (from pixel analysis of ChargenArt/*.jpg)

    private static let adeptLowerFist = NormPoint(x: 0.290, y: 0.583)
    private static let adeptUpperFist = NormPoint(x: 0.693, y: 0.286)
    private static let adeptScreenL = NormRect(x: 0.00, y: 0.05, w: 0.22, h: 0.55)
    private static let adeptScreenR = NormRect(x: 0.78, y: 0.05, w: 0.22, h: 0.55)

    /// Bright purple core path left-hand → right-hand (combat mage).
    private static let mageArc: [NormPoint] = [
        .init(x: 0.17, y: 0.40),
        .init(x: 0.21, y: 0.43),
        .init(x: 0.28, y: 0.57),
        .init(x: 0.34, y: 0.60),
        .init(x: 0.41, y: 0.66),
        .init(x: 0.47, y: 0.68),
        .init(x: 0.53, y: 0.67),
        .init(x: 0.62, y: 0.70),
        .init(x: 0.73, y: 0.76),
        .init(x: 0.80, y: 0.66),
        .init(x: 0.86, y: 0.66),
    ]

    /// Laptop screen bezel (decker) — tightened after visual check.
    private static let deckerScreen = NormRect(x: 0.10, y: 0.40, w: 0.42, h: 0.20)

    private static let riggerEyeL = NormPoint(x: 0.328, y: 0.313)
    private static let riggerEyeR = NormPoint(x: 0.533, y: 0.379)

    /// Floating card cluster + champagne bowl (technomancer / socialite art).
    private static let technoCards = NormRect(x: 0.68, y: 0.48, w: 0.28, h: 0.22)
    private static let technoGlass = NormRect(x: 0.74, y: 0.58, w: 0.14, h: 0.20)
    private static let technoSign = NormRect(x: 0.50, y: 0.08, w: 0.45, h: 0.16)

    private static let humanMonitors: [NormRect] = [
        .init(x: 0.04, y: 0.04, w: 0.30, h: 0.20),
        .init(x: 0.36, y: 0.02, w: 0.28, h: 0.18),
        .init(x: 0.66, y: 0.05, w: 0.30, h: 0.20),
        .init(x: 0.04, y: 0.27, w: 0.24, h: 0.16),
        .init(x: 0.28, y: 0.25, w: 0.24, h: 0.15),
        .init(x: 0.04, y: 0.46, w: 0.22, h: 0.15),
    ]

    // MARK: - Entry

    static func drawArchetype(
        _ archetype: RunnerArchetype,
        context: GraphicsContext,
        viewSize: CGSize,
        time: Double
    ) {
        let img = PortraitLayout.imageRect(in: viewSize)
        // Clip all FX to the image letterbox so nothing paints into empty bars.
        context.drawLayer { layer in
            layer.clip(to: Path(img))
            switch archetype {
            case .streetSamurai:
                rain(context: layer, imageRect: img, time: time)

            case .adept:
                screenPanel(context: layer, rect: adeptScreenL.cgRect(in: img), time: time, color: .cyan)
                screenPanel(context: layer, rect: adeptScreenR.cgRect(in: img), time: time + 0.9, color: .pink)
                glow(context: layer, at: adeptLowerFist.cgPoint(in: img), radius: img.width * 0.08, time: time, color: .cyan)
                glow(context: layer, at: adeptUpperFist.cgPoint(in: img), radius: img.width * 0.09, time: time + 0.7, color: .mint)

            case .combatMage:
                cracklePath(context: layer, points: mageArc.map { $0.cgPoint(in: img) }, time: time)
                if let first = mageArc.first, let last = mageArc.last {
                    glow(context: layer, at: first.cgPoint(in: img), radius: img.width * 0.07, time: time, color: .purple)
                    glow(context: layer, at: last.cgPoint(in: img), radius: img.width * 0.065, time: time + 0.4, color: .purple)
                }

            case .face:
                // Soft neon blooms only in upper neon-sign bokeh zones (not solid ovals).
                faceNeonFlicker(context: layer, imageRect: img, time: time)

            case .decker:
                let screen = deckerScreen.cgRect(in: img)
                layer.drawLayer { screenLayer in
                    screenLayer.clip(to: Path(roundedRect: screen, cornerRadius: 2))
                    matrixInRect(context: screenLayer, rect: screen, time: time)
                    let g = 0.12 + 0.14 * abs(sin(time * 3.3))
                    screenLayer.fill(Path(screen), with: .color(Color.cyan.opacity(g)))
                }

            case .rigger:
                let l = riggerEyeL.cgPoint(in: img)
                let r = riggerEyeR.cgPoint(in: img)
                glow(context: layer, at: l, radius: 9, time: time, color: .cyan)
                glow(context: layer, at: r, radius: 9, time: time + 0.3, color: .cyan)
                // Tendrils from eyes toward floating icons (upper third)
                beam(context: layer, from: l, to: CGPoint(x: img.minX + img.width * 0.18, y: img.minY + img.height * 0.12), time: time)
                beam(context: layer, from: l, to: CGPoint(x: img.minX + img.width * 0.35, y: img.minY + img.height * 0.08), time: time + 0.5)
                beam(context: layer, from: r, to: CGPoint(x: img.minX + img.width * 0.72, y: img.minY + img.height * 0.10), time: time + 0.9)
                beam(context: layer, from: r, to: CGPoint(x: img.minX + img.width * 0.88, y: img.minY + img.height * 0.18), time: time + 1.2)
                // Neck strand under chin
                beam(
                    context: layer,
                    from: CGPoint(x: img.minX + img.width * 0.48, y: img.minY + img.height * 0.45),
                    to: CGPoint(x: img.minX + img.width * 0.52, y: img.minY + img.height * 0.58),
                    time: time + 0.2
                )

            case .technomancer:
                floatCards(context: layer, region: technoCards.cgRect(in: img), time: time)
                bubbles(context: layer, in: technoGlass.cgRect(in: img), time: time)
                let sign = technoSign.cgRect(in: img)
                let pulse = 0.08 + 0.12 * abs(sin(time * 2.4))
                layer.fill(Path(ellipseIn: sign), with: .color(Color.pink.opacity(pulse)))

            case .spy:
                glyphColumns(context: layer, imageRect: img, time: time, avoidFaceX: 0.38...0.72)
            }
        }
    }

    static func drawMetatype(
        _ metatype: MetatypeID,
        context: GraphicsContext,
        viewSize: CGSize,
        time: Double
    ) {
        let img = PortraitLayout.imageRect(in: viewSize)
        context.drawLayer { layer in
            layer.clip(to: Path(img))
            switch metatype {
            case .human:
                for (i, mon) in humanMonitors.enumerated() {
                    screenPanel(
                        context: layer,
                        rect: mon.cgRect(in: img).insetBy(dx: 3, dy: 3),
                        time: time + Double(i) * 0.55,
                        color: i % 2 == 0 ? .cyan : .pink
                    )
                }
            case .elf:
                // Green rim light around subject (centered upper torso)
                let c = CGPoint(x: img.midX * 0.95, y: img.minY + img.height * 0.38)
                let pulse = 0.10 + 0.14 * abs(sin(time * 2.1))
                layer.fill(
                    Path(ellipseIn: CGRect(x: c.x - img.width * 0.35, y: c.y - img.width * 0.35, width: img.width * 0.7, height: img.width * 0.7)),
                    with: .radialGradient(
                        Gradient(colors: [Color.green.opacity(pulse), .clear]),
                        center: c,
                        startRadius: img.width * 0.05,
                        endRadius: img.width * 0.4
                    )
                )
                glow(context: layer, at: CGPoint(x: img.minX + img.width * 0.58, y: img.minY + img.height * 0.36), radius: 11, time: time, color: .green)

            case .dwarf:
                forge(context: layer, imageRect: img, time: time)

            case .ork:
                orkSigns(context: layer, imageRect: img, time: time)

            case .troll:
                trollTubes(context: layer, imageRect: img, time: time)
            }
        }
    }

    // MARK: - Drawing primitives (image-space)

    private static func rain(context: GraphicsContext, imageRect: CGRect, time: Double) {
        for i in 0..<30 {
            let seed = Double(i) * 7.13
            let x = imageRect.minX + imageRect.width * CGFloat(0.02 + 0.96 * fract(sin(seed) * 43758.5453))
            let speed = 48.0 + Double(i % 6) * 14
            let y = imageRect.minY + imageRect.height * CGFloat(fract(time * speed * 0.012 + seed))
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 1.5, y: y + 16))
            context.stroke(path, with: .color(Color.white.opacity(0.35 + 0.15 * abs(sin(time + seed)))), lineWidth: 1.2)
        }
    }

    /// Content updates only inside `rect` (billboard / monitor).
    private static func screenPanel(context: GraphicsContext, rect: CGRect, time: Double, color: Color) {
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: rect, cornerRadius: 2))
            let base = 0.06 + 0.10 * abs(sin(time * 2.6))
            layer.fill(Path(rect), with: .color(color.opacity(base)))
            // scanline
            let sy = rect.minY + rect.height * CGFloat(fract(time * 0.4))
            layer.fill(Path(CGRect(x: rect.minX, y: sy, width: rect.width, height: 2)), with: .color(Color.white.opacity(0.3)))
            // UI blocks
            let cols = 2, rows = 4
            let cw = rect.width / CGFloat(cols)
            let rh = rect.height / CGFloat(rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    let on = sin(time * 1.9 + Double(r * 3 + c) * 0.7) > 0.15
                    guard on else { continue }
                    let cell = CGRect(
                        x: rect.minX + CGFloat(c) * cw + 3,
                        y: rect.minY + CGFloat(r) * rh + 3,
                        width: cw - 6,
                        height: rh - 6
                    )
                    layer.fill(Path(cell), with: .color(color.opacity(0.35)))
                }
            }
        }
    }

    private static func glow(context: GraphicsContext, at center: CGPoint, radius: CGFloat, time: Double, color: Color) {
        let pulse = 0.3 + 0.4 * (0.5 + 0.5 * sin(time * 4.0))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(pulse), color.opacity(pulse * 0.25), .clear]),
                center: center,
                startRadius: 1,
                endRadius: radius
            )
        )
    }

    private static func cracklePath(context: GraphicsContext, points: [CGPoint], time: Double) {
        guard points.count >= 2 else { return }
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            let p = points[i]
            let jitter = CGFloat(sin(time * 20 + Double(i) * 2.4)) * 3.5
            path.addLine(to: CGPoint(x: p.x, y: p.y + jitter))
        }
        let flash = 0.55 + 0.4 * abs(sin(time * 10))
        context.stroke(path, with: .color(Color.purple.opacity(flash)), lineWidth: 3.2)
        context.stroke(path, with: .color(Color.white.opacity(flash * 0.7)), lineWidth: 1.3)
        // secondary fork
        var fork = Path()
        fork.move(to: points[0])
        for i in 1..<points.count {
            let p = points[i]
            let jitter = CGFloat(cos(time * 17 + Double(i) * 1.8)) * 5
            fork.addLine(to: CGPoint(x: p.x + jitter * 0.2, y: p.y + jitter * 0.6))
        }
        context.stroke(fork, with: .color(Color.purple.opacity(flash * 0.45)), lineWidth: 1.4)
    }

    private static func faceNeonFlicker(context: GraphicsContext, imageRect: CGRect, time: Double) {
        // Soft blooms matching neon bokeh — low opacity, clipped soft ellipses.
        struct Bloom { var n: NormRect; var color: Color; var phase: Double }
        let blooms: [Bloom] = [
            .init(n: .init(x: 0.02, y: 0.04, w: 0.28, h: 0.14), color: .pink, phase: 0),
            .init(n: .init(x: 0.55, y: 0.01, w: 0.4, h: 0.14), color: .yellow, phase: 0.8),
            .init(n: .init(x: 0.00, y: 0.32, w: 0.22, h: 0.12), color: .mint, phase: 1.4),
            .init(n: .init(x: 0.72, y: 0.26, w: 0.26, h: 0.12), color: .purple, phase: 2.1),
        ]
        for b in blooms {
            let on = sin(time * 2.8 + b.phase) > -0.2
            guard on else { continue }
            let rect = b.n.cgRect(in: imageRect)
            let a = 0.10 + 0.12 * abs(sin(time * 3.2 + b.phase))
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [b.color.opacity(a), .clear]),
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    startRadius: 2,
                    endRadius: max(rect.width, rect.height) * 0.55
                )
            )
        }
        // Jacket LEDs
        for i in 0..<5 {
            let lit = sin(time * 4.2 + Double(i) * 0.9) > 0.1
            guard lit else { continue }
            let pt = NormPoint(x: 0.42 + CGFloat(i) * 0.032, y: 0.58).cgPoint(in: imageRect)
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)), with: .color(Color.purple.opacity(0.75)))
        }
    }

    private static func matrixInRect(context: GraphicsContext, rect: CGRect, time: Double) {
        let cols = 8
        let colW = rect.width / CGFloat(cols)
        for c in 0..<cols {
            let x = rect.minX + CGFloat(c) * colW + colW * 0.25
            for row in 0..<9 {
                let phase = time * (1.5 + Double(c) * 0.11) + Double(row) * 0.25
                let y = rect.minY + rect.height * CGFloat(fract(phase * 0.2 + Double(c) * 0.04))
                guard y > rect.minY + 1 && y < rect.maxY - 5 else { continue }
                let g = CGRect(x: x, y: y, width: max(2.5, colW * 0.32), height: 5)
                let alpha = 0.45 + 0.4 * abs(sin(phase * 2))
                context.fill(Path(g), with: .color(Color.green.opacity(alpha)))
            }
        }
    }

    private static func beam(context: GraphicsContext, from: CGPoint, to: CGPoint, time: Double) {
        var path = Path()
        path.move(to: from)
        let mid = CGPoint(
            x: (from.x + to.x) / 2 + CGFloat(sin(time * 2.2)) * 5,
            y: (from.y + to.y) / 2
        )
        path.addQuadCurve(to: to, control: mid)
        let glow = 0.45 + 0.4 * abs(sin(time * 3.6))
        context.stroke(path, with: .color(Color.cyan.opacity(glow)), lineWidth: 2.2)
        context.stroke(path, with: .color(Color.white.opacity(glow * 0.4)), lineWidth: 0.9)
        let t = CGFloat(fract(time * 0.55))
        let bead = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        context.fill(Path(ellipseIn: CGRect(x: bead.x - 2, y: bead.y - 2, width: 4, height: 4)), with: .color(.white))
    }

    private static func floatCards(context: GraphicsContext, region: CGRect, time: Double) {
        for i in 0..<5 {
            let seed = Double(i) * 1.35
            let x = region.minX + region.width * CGFloat(0.1 + 0.7 * fract(sin(seed) * 3.2))
            let y = region.minY + region.height * CGFloat(0.15 + 0.6 * fract(cos(seed) * 2.8))
            let ox = CGFloat(sin(time * 0.8 + seed)) * 6
            let oy = CGFloat(cos(time * 0.9 + seed)) * 5
            let rect = CGRect(x: x + ox, y: y + oy, width: region.width * 0.28, height: region.height * 0.18)
            let a = 0.4 + 0.25 * abs(sin(time + seed))
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.yellow.opacity(a)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.white.opacity(a * 0.5)), lineWidth: 0.8)
        }
    }

    private static func bubbles(context: GraphicsContext, in rect: CGRect, time: Double) {
        for i in 0..<14 {
            let seed = Double(i) * 0.71
            let x = rect.minX + rect.width * CGFloat(0.15 + 0.7 * fract(sin(seed) * 4.1))
            let rise = fract(time * 0.3 + seed * 0.12)
            let y = rect.minY + rect.height * (1 - CGFloat(rise))
            let r: CGFloat = 1.1 + CGFloat(i % 3) * 0.55
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(Color.white.opacity(0.5 + 0.3 * abs(sin(time + seed))))
            )
        }
    }

    private static func glyphColumns(
        context: GraphicsContext,
        imageRect: CGRect,
        time: Double,
        avoidFaceX: ClosedRange<CGFloat>
    ) {
        let cols = 8
        for c in 0..<cols {
            let nx = 0.06 + 0.88 * CGFloat(c) / CGFloat(max(cols - 1, 1))
            if avoidFaceX.contains(nx) { continue }
            let x = imageRect.minX + imageRect.width * nx
            for row in 0..<11 {
                let phase = time * 0.9 + Double(c) * 0.4 + Double(row) * 0.15
                let y = imageRect.minY + imageRect.height * CGFloat(fract(phase * 0.13))
                let rect = CGRect(x: x, y: y, width: 5, height: 9)
                let alpha = 0.35 + 0.4 * abs(sin(phase * 2))
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color.green.opacity(alpha)))
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 2),
                    with: .color(Color.mint.opacity(alpha * 0.45)),
                    lineWidth: 1.1
                )
            }
        }
    }

    private static func forge(context: GraphicsContext, imageRect: CGRect, time: Double) {
        let anchors = [NormPoint(x: 0.12, y: 0.80), .init(x: 0.88, y: 0.74), .init(x: 0.15, y: 0.90)]
        for (i, a) in anchors.enumerated() {
            let base = a.cgPoint(in: imageRect)
            for j in 0..<5 {
                let seed = Double(i * 5 + j)
                let h = 16 + 24 * abs(sin(time * 5.5 + seed))
                let x = base.x + CGFloat(sin(time * 3 + seed)) * 5
                var path = Path()
                path.move(to: CGPoint(x: x, y: base.y))
                path.addQuadCurve(
                    to: CGPoint(x: x, y: base.y - h),
                    control: CGPoint(x: x + CGFloat(cos(time * 6 + seed)) * 7, y: base.y - h * 0.5)
                )
                path.addQuadCurve(
                    to: CGPoint(x: x, y: base.y),
                    control: CGPoint(x: x - CGFloat(sin(time * 5 + seed)) * 5, y: base.y - h * 0.4)
                )
                context.fill(path, with: .color(Color.orange.opacity(0.3 + 0.2 * abs(sin(time * 4 + seed)))))
            }
        }
        for i in 0..<16 {
            let seed = Double(i) * 1.7
            let x = imageRect.minX + imageRect.width * CGFloat(fract(sin(seed) * 8.1))
            let y = imageRect.minY + imageRect.height * CGFloat(0.95 - 0.45 * fract(time * 0.22 + seed * 0.1))
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                with: .color(Color.yellow.opacity(0.55))
            )
        }
    }

    private static func orkSigns(context: GraphicsContext, imageRect: CGRect, time: Double) {
        // Measured-ish neon sign bands in market scene.
        let signs: [(NormRect, Color, Double)] = [
            (.init(x: 0.02, y: 0.28, w: 0.30, h: 0.08), .orange, 3.0),  // SCRAP MEAT
            (.init(x: 0.18, y: 0.12, w: 0.32, h: 0.07), .yellow, 2.3), // CHROME & BURN
            (.init(x: 0.66, y: 0.20, w: 0.30, h: 0.09), .green, 3.8),   // OPEN 24
        ]
        for (i, s) in signs.enumerated() {
            let rect = s.0.cgRect(in: imageRect)
            let pulse = 0.12 + 0.22 * abs(sin(time * s.2))
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(s.1.opacity(pulse)))
            // Letter drop on right third
            let dropOn = sin(time * s.2 * 1.6 + Double(i)) > 0.2
            let drop = CGRect(x: rect.maxX - rect.width * 0.3, y: rect.minY, width: rect.width * 0.28, height: rect.height)
            context.fill(Path(drop), with: .color(s.1.opacity(dropOn ? 0.55 : 0.04)))
        }
    }

    private static func trollTubes(context: GraphicsContext, imageRect: CGRect, time: Double) {
        let tubes: [(NormPoint, NormPoint, Color)] = [
            (.init(x: 0.05, y: 0.35), .init(x: 0.45, y: 0.15), .blue),
            (.init(x: 0.55, y: 0.12), .init(x: 0.95, y: 0.40), .purple),
            (.init(x: 0.08, y: 0.70), .init(x: 0.48, y: 0.55), .cyan),
            (.init(x: 0.58, y: 0.75), .init(x: 0.95, y: 0.55), .purple),
        ]
        for (i, t) in tubes.enumerated() {
            var path = Path()
            path.move(to: t.0.cgPoint(in: imageRect))
            path.addLine(to: t.1.cgPoint(in: imageRect))
            let glow = 0.4 + 0.4 * abs(sin(time * 2.6 + Double(i)))
            context.stroke(path, with: .color(t.2.opacity(glow)), lineWidth: 5)
            context.stroke(path, with: .color(Color.white.opacity(glow * 0.3)), lineWidth: 1.4)
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
