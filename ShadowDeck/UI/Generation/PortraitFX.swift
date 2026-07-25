//
//  PortraitFX.swift
//  ShadowDeck
//
//  Animated overlays calibrated to landmarks in each painted portrait.
//  Coordinates are normalized 0…1 in portrait space (width × height),
//  assuming scaledToFill on a 3:4 image. The painted figure is never warped—
//  only light, rain, glyphs, and sparkle layers animate.
//

import SwiftUI

enum PortraitFX {
    // MARK: - Archetypes (landmarks from art audit)

    static func drawArchetype(_ archetype: RunnerArchetype, context: GraphicsContext, size: CGSize, time: Double) {
        switch archetype {
        case .streetSamurai:
            // Rainy alley — enhance existing rain only.
            rain(context: context, size: size, time: time, density: 28, color: .white.opacity(0.4))

        case .adept:
            // Billboards/screens L & R mid-background; fist glows at lower-left & upper-right of figure.
            billboardScreens(context: context, size: size, time: time)
            // Lower fist (viewer's left of center)
            fistGlow(context: context, at: p(0.38, 0.58, size), radius: size.width * 0.09, time: time, color: .cyan)
            // Raised fist (viewer's right / upper)
            fistGlow(context: context, at: p(0.62, 0.32, size), radius: size.width * 0.11, time: time + 0.8, color: .mint)

        case .combatMage:
            // Arc from outstretched left hand (~0.22, 0.48) to lower right hand (~0.72, 0.62)
            cracklingArc(
                context: context,
                from: p(0.24, 0.48, size),
                to: p(0.74, 0.62, size),
                time: time,
                color: .purple
            )
            fistGlow(context: context, at: p(0.24, 0.48, size), radius: size.width * 0.08, time: time, color: .purple)
            fistGlow(context: context, at: p(0.74, 0.62, size), radius: size.width * 0.07, time: time + 0.5, color: .purple)

        case .face:
            // Neon signs in upper half / sides — flicker those light sources.
            neonSignRegions(context: context, size: size, time: time, faceStyle: true)

        case .decker:
            // Laptop screen only (lower-left/center of frame).
            let screen = CGRect(
                x: size.width * 0.12,
                y: size.height * 0.42,
                width: size.width * 0.42,
                height: size.height * 0.22
            )
            context.drawLayer { layer in
                layer.clip(to: Path(roundedRect: screen, cornerRadius: 3))
                matrixColumns(context: layer, in: screen, time: time)
                let glow = 0.10 + 0.12 * abs(sin(time * 3.4))
                layer.fill(Path(screen), with: .color(Color.cyan.opacity(glow)))
            }
            // Subtle spill on keyboard/desk immediately below screen
            let spill = CGRect(x: screen.minX, y: screen.maxY, width: screen.width, height: size.height * 0.06)
            context.fill(Path(spill), with: .color(Color.cyan.opacity(0.05 + 0.04 * abs(sin(time * 2.5)))))

        case .rigger:
            // Eyes glowing; data tendrils from eyes upward/outward.
            let leftEye = p(0.42, 0.38, size)
            let rightEye = p(0.52, 0.37, size)
            eyeBeam(context: context, from: leftEye, to: p(0.18, 0.12, size), time: time)
            eyeBeam(context: context, from: rightEye, to: p(0.78, 0.10, size), time: time + 0.4)
            eyeBeam(context: context, from: leftEye, to: p(0.30, 0.08, size), time: time + 0.9)
            eyeBeam(context: context, from: rightEye, to: p(0.70, 0.15, size), time: time + 1.3)
            fistGlow(context: context, at: leftEye, radius: 10, time: time, color: .cyan)
            fistGlow(context: context, at: rightEye, radius: 10, time: time + 0.3, color: .cyan)
            // Neck circuit glow
            neckStrand(context: context, size: size, time: time)

        case .technomancer:
            // Champagne glass lower-right; floating gold cards mid-right; neon “Velvet Vault” upper-right.
            champagneBubblesInGlass(context: context, size: size, time: time)
            floatingCreditCards(context: context, size: size, time: time)
            // Sign glow upper-right
            context.fill(
                Path(CGRect(x: size.width * 0.45, y: size.height * 0.08, width: size.width * 0.5, height: size.height * 0.18)),
                with: .color(Color.pink.opacity(0.08 + 0.1 * abs(sin(time * 2.2))))
            )

        case .spy:
            // Green matrix glyphs already in background — scroll & glow them.
            verticalGlyphRain(context: context, size: size, time: time, color: .green)
        }
    }

    // MARK: - Metatypes

    static func drawMetatype(_ metatype: MetatypeID, context: GraphicsContext, size: CGSize, time: Double) {
        switch metatype {
        case .human:
            // Cockpit monitors around subject — update screen tiles in those bezel regions.
            humanCockpitScreens(context: context, size: size, time: time)

        case .elf:
            // Green rim light behind hooded figure — pulse that green halo.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.green.opacity(0.12 + 0.14 * abs(sin(time * 2.0))),
                        .clear,
                    ]),
                    center: p(0.45, 0.4, size),
                    startRadius: size.width * 0.08,
                    endRadius: size.width * 0.55
                )
            )
            // Monocle glow
            fistGlow(context: context, at: p(0.58, 0.36, size), radius: 12, time: time, color: .green)

        case .dwarf:
            // Forge fire lower-left & right — flickering flames/embers.
            forgeFlames(context: context, size: size, time: time)
            // Embers rising
            embers(context: context, size: size, time: time)

        case .ork:
            // Neon signs: SCRAP MEAT (left), CHROME & BURN (upper), OPEN 24 (right).
            orkMarketSigns(context: context, size: size, time: time)

        case .troll:
            // Blue/purple neon tubes behind shoulders — pulse those tubes.
            trollNeonTubes(context: context, size: size, time: time)
        }
    }

    // MARK: - Landmark-specific helpers

    private static func p(_ x: CGFloat, _ y: CGFloat, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * x, y: size.height * y)
    }

    private static func rain(context: GraphicsContext, size: CGSize, time: Double, density: Int, color: Color) {
        for i in 0..<density {
            let seed = Double(i) * 7.13
            let x = size.width * (0.02 + 0.96 * fract(sin(seed) * 43758.5453))
            let speed = 45.0 + Double(i % 6) * 16
            let y = size.height * fract(time * speed * 0.012 + seed)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 1.5, y: y + 14 + CGFloat(i % 4) * 3))
            context.stroke(
                path,
                with: .color(color.opacity(0.3 + 0.2 * abs(sin(time + seed)))),
                lineWidth: 1.2
            )
        }
    }

    /// Adept: vertical billboard panels mid-left and mid-right background.
    private static func billboardScreens(context: GraphicsContext, size: CGSize, time: Double) {
        let panels: [CGRect] = [
            CGRect(x: size.width * 0.02, y: size.height * 0.18, width: size.width * 0.16, height: size.height * 0.28),
            CGRect(x: size.width * 0.02, y: size.height * 0.48, width: size.width * 0.14, height: size.height * 0.18),
            CGRect(x: size.width * 0.78, y: size.height * 0.42, width: size.width * 0.18, height: size.height * 0.16),
            CGRect(x: size.width * 0.82, y: size.height * 0.22, width: size.width * 0.14, height: size.height * 0.14),
        ]
        for (i, panel) in panels.enumerated() {
            animateScreenContent(context: context, in: panel, time: time + Double(i) * 0.7, hue: i % 2 == 0 ? .cyan : .pink)
        }
    }

    private static func animateScreenContent(context: GraphicsContext, in rect: CGRect, time: Double, hue: Color) {
        let flicker = 0.08 + 0.18 * abs(sin(time * 2.8))
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(hue.opacity(flicker)))
        // Horizontal scan bar
        let sy = rect.minY + rect.height * CGFloat(fract(time * 0.35))
        var scan = Path()
        scan.addRect(CGRect(x: rect.minX, y: sy, width: rect.width, height: 2))
        context.fill(scan, with: .color(Color.white.opacity(0.25)))
        // Pseudo “UI blocks”
        for r in 0..<3 {
            for c in 0..<2 {
                let cell = CGRect(
                    x: rect.minX + 3 + CGFloat(c) * (rect.width / 2),
                    y: rect.minY + 4 + CGFloat(r) * (rect.height / 3.5),
                    width: rect.width / 2.4,
                    height: rect.height / 5
                )
                let on = sin(time * 1.7 + Double(r * 3 + c)) > 0
                if on {
                    context.fill(Path(cell), with: .color(hue.opacity(0.35)))
                }
            }
        }
    }

    private static func fistGlow(context: GraphicsContext, at center: CGPoint, radius: CGFloat, time: Double, color: Color) {
        let pulse = 0.25 + 0.35 * (0.5 + 0.5 * sin(time * 4.2))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(pulse), color.opacity(pulse * 0.3), .clear]),
                center: center,
                startRadius: 1,
                endRadius: radius
            )
        )
    }

    /// Combat mage: multi-segment crackling arc along the painted lightning path.
    private static func cracklingArc(
        context: GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        time: Double,
        color: Color
    ) {
        let segs = 10
        var path = Path()
        path.move(to: from)
        for i in 1...segs {
            let t = CGFloat(i) / CGFloat(segs)
            // Slight bow upward like the painted arc
            let base = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t - sin(t * .pi) * 28
            )
            let jitter = CGFloat(sin(time * 22 + Double(i) * 2.7)) * (4 + CGFloat(i % 3) * 2)
            path.addLine(to: CGPoint(x: base.x, y: base.y + jitter))
        }
        let flash = 0.55 + 0.4 * abs(sin(time * 11))
        context.stroke(path, with: .color(color.opacity(flash)), lineWidth: 3.5)
        context.stroke(path, with: .color(Color.white.opacity(flash * 0.75)), lineWidth: 1.4)
        // Secondary thinner fork
        var fork = Path()
        fork.move(to: from)
        for i in 1...segs {
            let t = CGFloat(i) / CGFloat(segs)
            let base = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t - sin(t * .pi) * 18
            )
            let jitter = CGFloat(cos(time * 19 + Double(i) * 1.9)) * 5
            fork.addLine(to: CGPoint(x: base.x + jitter * 0.3, y: base.y + jitter))
        }
        context.stroke(fork, with: .color(color.opacity(flash * 0.5)), lineWidth: 1.5)
    }

    private static func neonSignRegions(context: GraphicsContext, size: CGSize, time: Double, faceStyle: Bool) {
        // Face portrait: bokeh neon upper background — pulse soft light plates.
        let regions: [CGRect] = [
            CGRect(x: size.width * 0.05, y: size.height * 0.05, width: size.width * 0.25, height: size.height * 0.12),
            CGRect(x: size.width * 0.55, y: size.height * 0.02, width: size.width * 0.4, height: size.height * 0.15),
            CGRect(x: size.width * 0.02, y: size.height * 0.35, width: size.width * 0.22, height: size.height * 0.12),
            CGRect(x: size.width * 0.75, y: size.height * 0.28, width: size.width * 0.22, height: size.height * 0.1),
        ]
        let colors: [Color] = [.pink, .yellow, .mint, .purple]
        for (i, rect) in regions.enumerated() {
            let on = sin(time * (2.2 + Double(i) * 0.5) + Double(i)) > -0.25
            guard on else { continue }
            let a = 0.12 + 0.18 * abs(sin(time * 3 + Double(i)))
            context.fill(Path(ellipseIn: rect), with: .color(colors[i % colors.count].opacity(a)))
        }
        // Jacket LED row subtle blink (mid torso)
        if faceStyle {
            for i in 0..<5 {
                let x = size.width * (0.42 + CGFloat(i) * 0.035)
                let y = size.height * 0.58
                let lit = sin(time * 4 + Double(i) * 0.8) > 0
                if lit {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)),
                        with: .color(Color.purple.opacity(0.7))
                    )
                }
            }
        }
    }

    private static func matrixColumns(context: GraphicsContext, in rect: CGRect, time: Double) {
        let cols = 9
        let colW = rect.width / CGFloat(cols)
        for c in 0..<cols {
            let x = rect.minX + CGFloat(c) * colW + colW * 0.25
            for row in 0..<10 {
                let phase = time * (1.4 + Double(c) * 0.12) + Double(row) * 0.28
                let y = rect.minY + rect.height * fract(phase * 0.18 + Double(c) * 0.05)
                guard y > rect.minY + 2 && y < rect.maxY - 6 else { continue }
                let gRect = CGRect(x: x, y: y, width: max(3, colW * 0.35), height: 6)
                let alpha = 0.4 + 0.4 * abs(sin(phase * 2))
                context.fill(Path(gRect), with: .color(Color.green.opacity(alpha)))
            }
        }
    }

    private static func eyeBeam(context: GraphicsContext, from: CGPoint, to: CGPoint, time: Double) {
        var path = Path()
        path.move(to: from)
        let mid = CGPoint(
            x: (from.x + to.x) / 2 + CGFloat(sin(time * 2.5)) * 6,
            y: (from.y + to.y) / 2
        )
        path.addQuadCurve(to: to, control: mid)
        let glow = 0.4 + 0.4 * abs(sin(time * 3.5))
        context.stroke(path, with: .color(Color.cyan.opacity(glow)), lineWidth: 2.5)
        context.stroke(path, with: .color(Color.white.opacity(glow * 0.45)), lineWidth: 1)
        let t = CGFloat(fract(time * 0.55))
        let bead = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        context.fill(
            Path(ellipseIn: CGRect(x: bead.x - 2.5, y: bead.y - 2.5, width: 5, height: 5)),
            with: .color(Color.white.opacity(0.9))
        )
    }

    private static func neckStrand(context: GraphicsContext, size: CGSize, time: Double) {
        var path = Path()
        let start = p(0.48, 0.48, size)
        let end = p(0.52, 0.62, size)
        path.move(to: start)
        path.addQuadCurve(to: end, control: p(0.55, 0.55, size))
        let glow = 0.35 + 0.4 * abs(sin(time * 3.8))
        context.stroke(path, with: .color(Color.cyan.opacity(glow)), lineWidth: 3)
    }

    private static func champagneBubblesInGlass(context: GraphicsContext, size: CGSize, time: Double) {
        // Glass bowl approx: x 0.72–0.88, y 0.58–0.78
        let gx = size.width * 0.74
        let gy = size.height * 0.58
        let gw = size.width * 0.12
        let gh = size.height * 0.18
        for i in 0..<12 {
            let seed = Double(i) * 0.73
            let x = gx + gw * CGFloat(0.2 + 0.6 * fract(sin(seed) * 4.2))
            let rise = fract(time * 0.28 + seed * 0.15)
            let y = gy + gh * (1 - CGFloat(rise))
            let r: CGFloat = 1.2 + CGFloat(i % 3) * 0.6
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(Color.white.opacity(0.45 + 0.3 * abs(sin(time + seed))))
            )
        }
    }

    private static func floatingCreditCards(context: GraphicsContext, size: CGSize, time: Double) {
        // Cards already float mid-right of technomancer art — drift near 0.7–0.9 x, 0.45–0.7 y
        for i in 0..<5 {
            let seed = Double(i) * 1.4
            let baseX = 0.68 + 0.08 * fract(sin(seed) * 3.1)
            let baseY = 0.48 + 0.12 * fract(cos(seed) * 2.7)
            let x = size.width * (baseX + 0.02 * sin(time * 0.7 + seed))
            let y = size.height * (baseY + 0.025 * cos(time * 0.9 + seed))
            let w = size.width * 0.08
            let h = size.height * 0.035
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let a = 0.35 + 0.25 * abs(sin(time + seed))
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.yellow.opacity(a)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.white.opacity(a * 0.6)), lineWidth: 0.8)
        }
    }

    private static func verticalGlyphRain(context: GraphicsContext, size: CGSize, time: Double, color: Color) {
        let cols = 7
        for c in 0..<cols {
            let x = size.width * (0.08 + 0.84 * CGFloat(c) / CGFloat(max(cols - 1, 1)))
            // Avoid covering the face column (~0.45–0.7)
            if x > size.width * 0.38 && x < size.width * 0.72 { continue }
            for row in 0..<10 {
                let phase = time * 0.85 + Double(c) * 0.35 + Double(row) * 0.18
                let y = size.height * fract(phase * 0.14)
                let rect = CGRect(x: x, y: y, width: 5, height: 10)
                let alpha = 0.3 + 0.4 * abs(sin(phase * 2))
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(alpha)))
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 2),
                    with: .color(color.opacity(alpha * 0.45)),
                    lineWidth: 1.2
                )
            }
        }
    }

    private static func humanCockpitScreens(context: GraphicsContext, size: CGSize, time: Double) {
        // Monitor bezels around the operator (subject lower-right).
        let monitors: [CGRect] = [
            CGRect(x: size.width * 0.05, y: size.height * 0.05, width: size.width * 0.28, height: size.height * 0.2),
            CGRect(x: size.width * 0.36, y: size.height * 0.02, width: size.width * 0.28, height: size.height * 0.18),
            CGRect(x: size.width * 0.68, y: size.height * 0.06, width: size.width * 0.28, height: size.height * 0.2),
            CGRect(x: size.width * 0.04, y: size.height * 0.28, width: size.width * 0.22, height: size.height * 0.16),
            CGRect(x: size.width * 0.28, y: size.height * 0.26, width: size.width * 0.22, height: size.height * 0.14),
            CGRect(x: size.width * 0.04, y: size.height * 0.48, width: size.width * 0.2, height: size.height * 0.14),
        ]
        for (i, m) in monitors.enumerated() {
            animateScreenContent(context: context, in: m.insetBy(dx: 4, dy: 4), time: time + Double(i), hue: i % 2 == 0 ? .cyan : .pink)
        }
    }

    private static func forgeFlames(context: GraphicsContext, size: CGSize, time: Double) {
        // Lower-left and lower-right fire regions in dwarf portrait.
        let anchors: [CGPoint] = [p(0.12, 0.78, size), p(0.88, 0.72, size), p(0.18, 0.88, size)]
        for (i, base) in anchors.enumerated() {
            for j in 0..<5 {
                let seed = Double(i * 5 + j)
                let h = 14 + 22 * abs(sin(time * 5.5 + seed))
                let x = base.x + CGFloat(sin(time * 3 + seed)) * 6
                var path = Path()
                path.move(to: CGPoint(x: x, y: base.y))
                path.addQuadCurve(
                    to: CGPoint(x: x, y: base.y - h),
                    control: CGPoint(x: x + CGFloat(cos(time * 6 + seed)) * 8, y: base.y - h * 0.5)
                )
                path.addQuadCurve(
                    to: CGPoint(x: x, y: base.y),
                    control: CGPoint(x: x - CGFloat(sin(time * 5 + seed)) * 6, y: base.y - h * 0.4)
                )
                context.fill(path, with: .color(Color.orange.opacity(0.28 + 0.2 * abs(sin(time * 4 + seed)))))
            }
        }
    }

    private static func embers(context: GraphicsContext, size: CGSize, time: Double) {
        for i in 0..<14 {
            let seed = Double(i) * 1.9
            let x = size.width * fract(sin(seed) * 8.1)
            let y = size.height * (0.95 - 0.5 * fract(time * 0.2 + seed * 0.1))
            let r: CGFloat = 1 + CGFloat(i % 3)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(Color.yellow.opacity(0.5 + 0.3 * abs(sin(time + seed))))
            )
        }
    }

    private static func orkMarketSigns(context: GraphicsContext, size: CGSize, time: Double) {
        // SCRAP MEAT left mid, CHROME upper-left, OPEN 24 right.
        struct Sign {
            var rect: CGRect
            var color: Color
            var speed: Double
        }
        let signs = [
            Sign(rect: CGRect(x: size.width * 0.02, y: size.height * 0.28, width: size.width * 0.28, height: size.height * 0.08), color: .orange, speed: 3.1),
            Sign(rect: CGRect(x: size.width * 0.18, y: size.height * 0.12, width: size.width * 0.3, height: size.height * 0.07), color: .yellow, speed: 2.4),
            Sign(rect: CGRect(x: size.width * 0.68, y: size.height * 0.22, width: size.width * 0.28, height: size.height * 0.08), color: .green, speed: 4.0),
        ]
        for (i, sign) in signs.enumerated() {
            // Whole-sign pulse
            let pulse = 0.1 + 0.2 * abs(sin(time * sign.speed))
            context.fill(Path(roundedRect: sign.rect, cornerRadius: 2), with: .color(sign.color.opacity(pulse)))
            // Letter-drop: occasionally dim a segment
            if sin(time * sign.speed * 1.7 + Double(i)) > 0.3 {
                let drop = CGRect(
                    x: sign.rect.maxX - sign.rect.width * 0.28,
                    y: sign.rect.minY,
                    width: sign.rect.width * 0.25,
                    height: sign.rect.height
                )
                let lit = sin(time * 6 + Double(i)) > 0
                context.fill(Path(drop), with: .color(sign.color.opacity(lit ? 0.55 : 0.05)))
            }
        }
    }

    private static func trollNeonTubes(context: GraphicsContext, size: CGSize, time: Double) {
        // Diagonal blue/purple tubes behind the troll.
        let tubes: [(CGPoint, CGPoint, Color)] = [
            (p(0.05, 0.35, size), p(0.45, 0.15, size), .blue),
            (p(0.55, 0.12, size), p(0.95, 0.4, size), .purple),
            (p(0.1, 0.7, size), p(0.5, 0.55, size), .cyan),
            (p(0.6, 0.75, size), p(0.95, 0.55, size), .purple),
        ]
        for (i, tube) in tubes.enumerated() {
            var path = Path()
            path.move(to: tube.0)
            path.addLine(to: tube.1)
            let glow = 0.35 + 0.4 * abs(sin(time * 2.5 + Double(i)))
            context.stroke(path, with: .color(tube.2.opacity(glow)), lineWidth: 5)
            context.stroke(path, with: .color(Color.white.opacity(glow * 0.35)), lineWidth: 1.5)
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
