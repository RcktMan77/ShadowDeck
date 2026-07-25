//
//  PortraitFX.swift
//  ShadowDeck
//
//  Minimal, landmark-anchored glows. Prefer subtle enhancement of what is
//  already painted over elaborate overlays that fight the art.
//
//  Coordinates are normalized (0…1) in full image space, mapped through the
//  same scaledToFill crop rect used by SwiftUI Image.
//

import SwiftUI

struct NormPoint: Sendable {
    var x: CGFloat
    var y: CGFloat
}

struct NormRect: Sendable {
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
}

enum PortraitLayout {
    /// ChargenArt portraits are 864×1152.
    static let imageAspect: CGFloat = 864.0 / 1152.0

    /// Visible rect of a scaledToFill image inside the view (may extend past view bounds).
    static func filledImageRect(in viewSize: CGSize) -> CGRect {
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        if viewAspect > imageAspect {
            // View wider than image → fill width, crop top/bottom.
            let drawnHeight = viewSize.width / imageAspect
            return CGRect(
                x: 0,
                y: (viewSize.height - drawnHeight) / 2,
                width: viewSize.width,
                height: drawnHeight
            )
        } else {
            // View taller → fill height, crop sides.
            let drawnWidth = viewSize.height * imageAspect
            return CGRect(
                x: (viewSize.width - drawnWidth) / 2,
                y: 0,
                width: drawnWidth,
                height: viewSize.height
            )
        }
    }

    static func point(_ n: NormPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + n.x * imageRect.width,
            y: imageRect.minY + n.y * imageRect.height
        )
    }

    static func rect(_ n: NormRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + n.x * imageRect.width,
            y: imageRect.minY + n.y * imageRect.height,
            width: n.w * imageRect.width,
            height: n.h * imageRect.height
        )
    }
}

enum PortraitFX {
    // Measured / visually tuned landmarks (image space, top-left origin).
    private static let adeptFistLower = NormPoint(x: 0.36, y: 0.58)
    private static let adeptFistUpper = NormPoint(x: 0.62, y: 0.30)

    private static let mageBoltCenter = NormPoint(x: 0.48, y: 0.58)
    private static let mageHandL = NormPoint(x: 0.22, y: 0.48)
    private static let mageHandR = NormPoint(x: 0.74, y: 0.62)

    private static let faceNecklace = NormPoint(x: 0.52, y: 0.62)

    private static let deckerScreen = NormRect(x: 0.12, y: 0.41, w: 0.40, h: 0.19)

    private static let riggerEyeL = NormPoint(x: 0.33, y: 0.31)
    private static let riggerEyeR = NormPoint(x: 0.53, y: 0.38)

    private static let technoGlass = NormRect(x: 0.78, y: 0.60, w: 0.12, h: 0.18)

    private static let spyEyeL = NormPoint(x: 0.48, y: 0.42)
    private static let spyEyeR = NormPoint(x: 0.62, y: 0.43)

    static func drawArchetype(
        _ archetype: RunnerArchetype,
        context: GraphicsContext,
        viewSize: CGSize,
        time: Double
    ) {
        let img = PortraitLayout.filledImageRect(in: viewSize)
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(origin: .zero, size: viewSize)))
            switch archetype {
            case .streetSamurai:
                rain(context: layer, imageRect: img, viewSize: viewSize, time: time)

            case .adept:
                // No billboard FX — only clear fist glows on the painted energy.
                softGlow(context: layer, at: PortraitLayout.point(adeptFistLower, in: img), radius: img.width * 0.11, time: time, color: .cyan, strength: 0.85)
                softGlow(context: layer, at: PortraitLayout.point(adeptFistUpper, in: img), radius: img.width * 0.12, time: time + 0.6, color: .mint, strength: 0.9)

            case .combatMage:
                // Pulse the existing painted bolt (center + hands) — no new lightning path.
                softGlow(context: layer, at: PortraitLayout.point(mageBoltCenter, in: img), radius: img.width * 0.20, time: time, color: .purple, strength: 0.55)
                softGlow(context: layer, at: PortraitLayout.point(mageHandL, in: img), radius: img.width * 0.10, time: time + 0.3, color: .purple, strength: 0.7)
                softGlow(context: layer, at: PortraitLayout.point(mageHandR, in: img), radius: img.width * 0.09, time: time + 0.7, color: .purple, strength: 0.7)

            case .face:
                // Background neon bokeh only + necklace pulse (no free-floating neck lights).
                faceNeonBokeh(context: layer, imageRect: img, time: time)
                softGlow(context: layer, at: PortraitLayout.point(faceNecklace, in: img), radius: img.width * 0.07, time: time, color: .red, strength: 0.75)

            case .decker:
                // Border glow on laptop screen only (no scrolling code — screen is angled).
                screenBorderGlow(context: layer, rect: PortraitLayout.rect(deckerScreen, in: img), time: time, color: .cyan)

            case .rigger:
                // Concentrated eye glows only — no forehead beams.
                softGlow(context: layer, at: PortraitLayout.point(riggerEyeL, in: img), radius: 14, time: time, color: .cyan, strength: 0.95)
                softGlow(context: layer, at: PortraitLayout.point(riggerEyeR, in: img), radius: 14, time: time + 0.35, color: .cyan, strength: 0.95)

            case .technomancer:
                // Champagne bubbles only, centered in glass; no floating cards.
                champagneBubbles(context: layer, glass: PortraitLayout.rect(technoGlass, in: img), time: time)

            case .spy:
                // Purple eye glow only (no glyph bars).
                softGlow(context: layer, at: PortraitLayout.point(spyEyeL, in: img), radius: 12, time: time, color: .purple, strength: 0.9)
                softGlow(context: layer, at: PortraitLayout.point(spyEyeR, in: img), radius: 12, time: time + 0.4, color: .purple, strength: 0.9)
            }
        }
    }

    /// Metatypes are static — intentionally no FX.
    static func drawMetatype(
        _ metatype: MetatypeID,
        context: GraphicsContext,
        viewSize: CGSize,
        time: Double
    ) {
        // no-op
    }

    // MARK: - Primitives

    private static func rain(
        context: GraphicsContext,
        imageRect: CGRect,
        viewSize: CGSize,
        time: Double
    ) {
        let bounds = CGRect(origin: .zero, size: viewSize)
        for i in 0..<28 {
            let seed = Double(i) * 7.13
            let x = imageRect.minX + imageRect.width * CGFloat(0.02 + 0.96 * fract(sin(seed) * 43758.5453))
            let speed = 48.0 + Double(i % 6) * 14
            let y = imageRect.minY + imageRect.height * CGFloat(fract(time * speed * 0.012 + seed))
            guard bounds.contains(CGPoint(x: x, y: y)) else { continue }
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 1.5, y: y + 16))
            context.stroke(
                path,
                with: .color(Color.white.opacity(0.35 + 0.15 * abs(sin(time + seed)))),
                lineWidth: 1.2
            )
        }
    }

    private static func softGlow(
        context: GraphicsContext,
        at center: CGPoint,
        radius: CGFloat,
        time: Double,
        color: Color,
        strength: Double
    ) {
        let pulse = strength * (0.45 + 0.55 * (0.5 + 0.5 * sin(time * 3.4)))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    color.opacity(pulse),
                    color.opacity(pulse * 0.35),
                    .clear,
                ]),
                center: center,
                startRadius: 1,
                endRadius: radius
            )
        )
    }

    private static func faceNeonBokeh(context: GraphicsContext, imageRect: CGRect, time: Double) {
        struct Bloom {
            var p: NormPoint
            var radius: CGFloat
            var color: Color
            var phase: Double
        }
        // Soft neon lights in upper / side bokeh — not hard rectangles.
        let blooms: [Bloom] = [
            .init(p: .init(x: 0.12, y: 0.12), radius: 0.12, color: .pink, phase: 0),
            .init(p: .init(x: 0.78, y: 0.10), radius: 0.14, color: .yellow, phase: 0.9),
            .init(p: .init(x: 0.10, y: 0.40), radius: 0.10, color: .mint, phase: 1.6),
            .init(p: .init(x: 0.88, y: 0.32), radius: 0.11, color: .purple, phase: 2.2),
        ]
        for b in blooms {
            let on = sin(time * 2.6 + b.phase) > -0.35
            guard on else { continue }
            let c = PortraitLayout.point(b.p, in: imageRect)
            let r = imageRect.width * b.radius
            let a = 0.12 + 0.14 * abs(sin(time * 3 + b.phase))
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [b.color.opacity(a), .clear]),
                    center: c,
                    startRadius: 2,
                    endRadius: r
                )
            )
        }
    }

    private static func screenBorderGlow(
        context: GraphicsContext,
        rect: CGRect,
        time: Double,
        color: Color
    ) {
        let pulse = 0.35 + 0.45 * (0.5 + 0.5 * sin(time * 3.0))
        // Outer soft fill
        context.fill(
            Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 4),
            with: .color(color.opacity(0.08 * pulse))
        )
        // Bright rim
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 3),
            with: .color(color.opacity(0.55 * pulse)),
            lineWidth: 2.5
        )
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 2),
            with: .color(Color.white.opacity(0.25 * pulse)),
            lineWidth: 1
        )
        // Gentle interior wash (not scrolling lines)
        context.fill(Path(rect), with: .color(color.opacity(0.06 * pulse)))
    }

    private static func champagneBubbles(context: GraphicsContext, glass: CGRect, time: Double) {
        // Keep bubbles strictly inside the glass bowl (inset).
        let inset = glass.insetBy(dx: glass.width * 0.22, dy: glass.height * 0.12)
        guard inset.width > 2, inset.height > 2 else { return }
        for i in 0..<12 {
            let seed = Double(i) * 0.73
            let x = inset.minX + inset.width * CGFloat(0.15 + 0.7 * fract(sin(seed) * 4.2))
            let rise = fract(time * 0.28 + seed * 0.13)
            let y = inset.minY + inset.height * (1 - CGFloat(rise))
            let r: CGFloat = 1.2 + CGFloat(i % 3) * 0.5
            // Skip if outside inset (safety)
            let pt = CGPoint(x: x, y: y)
            guard inset.insetBy(dx: -1, dy: -1).contains(pt) else { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                with: .color(Color.white.opacity(0.55 + 0.3 * abs(sin(time + seed))))
            )
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
