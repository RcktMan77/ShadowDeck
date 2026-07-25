//
//  PortraitFX.swift
//  ShadowDeck
//
//  Landmark-anchored glows. Image-space coords (0…1, top-left) mapped through
//  the same scaledToFill crop as the painted art.
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

struct NormDot: Sendable {
    var x: CGFloat
    var y: CGFloat
    /// Radius as fraction of image width.
    var r: CGFloat
}

enum PortraitLayout {
    static let imageAspect: CGFloat = 864.0 / 1152.0

    static func filledImageRect(in viewSize: CGSize) -> CGRect {
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        if viewAspect > imageAspect {
            let drawnHeight = viewSize.width / imageAspect
            return CGRect(x: 0, y: (viewSize.height - drawnHeight) / 2, width: viewSize.width, height: drawnHeight)
        } else {
            let drawnWidth = viewSize.height * imageAspect
            return CGRect(x: (viewSize.width - drawnWidth) / 2, y: 0, width: drawnWidth, height: viewSize.height)
        }
    }

    static func point(_ n: NormPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(x: imageRect.minX + n.x * imageRect.width, y: imageRect.minY + n.y * imageRect.height)
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
    // Adept fists (painted energy cores)
    private static let adeptFistLower = NormPoint(x: 0.36, y: 0.58)
    private static let adeptFistUpper = NormPoint(x: 0.62, y: 0.30)

    // Combat mage: path along painted lightning
    private static let mageArc: [NormPoint] = [
        .init(x: 0.22, y: 0.45),
        .init(x: 0.28, y: 0.50),
        .init(x: 0.34, y: 0.58),
        .init(x: 0.40, y: 0.64),
        .init(x: 0.46, y: 0.67),
        .init(x: 0.52, y: 0.68),
        .init(x: 0.60, y: 0.72),
        .init(x: 0.68, y: 0.74),
        .init(x: 0.74, y: 0.70),
        .init(x: 0.78, y: 0.64),
    ]

    // Face: purple LEDs on mesh top + shoulder (small painted dots)
    private static let faceLEDs: [NormDot] = [
        .init(x: 0.435, y: 0.578, r: 0.0055),
        .init(x: 0.455, y: 0.578, r: 0.0055),
        .init(x: 0.475, y: 0.578, r: 0.0055),
        .init(x: 0.545, y: 0.578, r: 0.0055),
        .init(x: 0.565, y: 0.578, r: 0.0055),
        .init(x: 0.585, y: 0.578, r: 0.0055),
        .init(x: 0.605, y: 0.578, r: 0.0055),
        .init(x: 0.72, y: 0.548, r: 0.008),
        .init(x: 0.48, y: 0.615, r: 0.005),
        .init(x: 0.56, y: 0.615, r: 0.005),
    ]

    // Decker: small central screen core only (angled; head clips lower-right)
    private static let deckerScreenCore = NormRect(x: 0.22, y: 0.47, w: 0.16, h: 0.09)

    // Rigger eyes (bright cores on face; head tilted up so y is mid-face)
    private static let riggerEyeL = NormPoint(x: 0.40, y: 0.46)
    private static let riggerEyeR = NormPoint(x: 0.49, y: 0.46)

    // Champagne yellow liquid only (tight)
    private static let technoLiquid = NormRect(x: 0.845, y: 0.68, w: 0.045, h: 0.09)

    // Infiltrator purple irises
    private static let spyEyeL = NormPoint(x: 0.47, y: 0.36)
    private static let spyEyeR = NormPoint(x: 0.59, y: 0.355)

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
                softGlow(context: layer, at: PortraitLayout.point(adeptFistLower, in: img), radius: img.width * 0.11, time: time, color: .cyan, strength: 0.9)
                softGlow(context: layer, at: PortraitLayout.point(adeptFistUpper, in: img), radius: img.width * 0.12, time: time + 0.55, color: .mint, strength: 0.95)

            case .combatMage:
                arcPulse(context: layer, points: mageArc.map { PortraitLayout.point($0, in: img) }, time: time)

            case .face:
                faceNeonBokeh(context: layer, imageRect: img, time: time)
                syncedDots(context: layer, dots: faceLEDs, imageRect: img, time: time, color: Color(red: 0.65, green: 0.35, blue: 0.95))

            case .decker:
                screenBorderGlow(context: layer, rect: PortraitLayout.rect(deckerScreenCore, in: img), time: time, color: .cyan)

            case .rigger:
                softGlow(context: layer, at: PortraitLayout.point(riggerEyeL, in: img), radius: 12, time: time, color: .cyan, strength: 1.0)
                softGlow(context: layer, at: PortraitLayout.point(riggerEyeR, in: img), radius: 12, time: time + 0.3, color: .cyan, strength: 1.0)

            case .technomancer:
                champagneBubbles(context: layer, liquid: PortraitLayout.rect(technoLiquid, in: img), time: time)

            case .spy:
                softGlow(context: layer, at: PortraitLayout.point(spyEyeL, in: img), radius: 9, time: time, color: .purple, strength: 0.95)
                softGlow(context: layer, at: PortraitLayout.point(spyEyeR, in: img), radius: 9, time: time + 0.35, color: .purple, strength: 0.95)
            }
        }
    }

    static func drawMetatype(
        _ metatype: MetatypeID,
        context: GraphicsContext,
        viewSize: CGSize,
        time: Double
    ) {}

    // MARK: Primitives

    private static func rain(context: GraphicsContext, imageRect: CGRect, viewSize: CGSize, time: Double) {
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
            context.stroke(path, with: .color(Color.white.opacity(0.35 + 0.15 * abs(sin(time + seed)))), lineWidth: 1.2)
        }
    }

    /// Traveling pulse beads + soft wash along the static lightning.
    private static func arcPulse(context: GraphicsContext, points: [CGPoint], time: Double) {
        guard points.count >= 2 else { return }
        var wash = Path()
        wash.move(to: points[0])
        for p in points.dropFirst() { wash.addLine(to: p) }
        context.stroke(wash, with: .color(Color.purple.opacity(0.16 + 0.1 * abs(sin(time * 2)))), lineWidth: 12)
        context.stroke(wash, with: .color(Color.purple.opacity(0.28 + 0.12 * abs(sin(time * 3)))), lineWidth: 4.5)

        for offset in [0.0, 0.45] {
            let t = fract(time * 0.5 + offset)
            let pos = pointAlong(points, t: CGFloat(t))
            let pulse = 0.75 + 0.25 * abs(sin(time * 9 + offset * 5))
            context.fill(
                Path(ellipseIn: CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(pulse),
                        Color.purple.opacity(pulse * 0.65),
                        .clear,
                    ]),
                    center: pos,
                    startRadius: 1,
                    endRadius: 14
                )
            )
        }
    }

    private static func pointAlong(_ points: [CGPoint], t: CGFloat) -> CGPoint {
        let clamped = min(1, max(0, t))
        let segs = points.count - 1
        let f = clamped * CGFloat(segs)
        let i = min(segs - 1, max(0, Int(f)))
        let local = f - CGFloat(i)
        let a = points[i], b = points[i + 1]
        return CGPoint(x: a.x + (b.x - a.x) * local, y: a.y + (b.y - a.y) * local)
    }

    private static func syncedDots(
        context: GraphicsContext,
        dots: [NormDot],
        imageRect: CGRect,
        time: Double,
        color: Color
    ) {
        let phase = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 3.5))
        for d in dots {
            let c = PortraitLayout.point(NormPoint(x: d.x, y: d.y), in: imageRect)
            let r = max(1.5, d.r * imageRect.width)
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(color.opacity(0.5 + 0.5 * phase))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r * 2.4, y: c.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.4 * phase), .clear]),
                    center: c,
                    startRadius: r * 0.4,
                    endRadius: r * 2.6
                )
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
        let pulse = strength * (0.5 + 0.5 * (0.5 + 0.5 * sin(time * 3.4)))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(pulse), color.opacity(pulse * 0.28), .clear]),
                center: center,
                startRadius: 1,
                endRadius: radius
            )
        )
    }

    private static func faceNeonBokeh(context: GraphicsContext, imageRect: CGRect, time: Double) {
        struct Bloom { var p: NormPoint; var radius: CGFloat; var color: Color; var phase: Double }
        let blooms: [Bloom] = [
            .init(p: .init(x: 0.12, y: 0.12), radius: 0.12, color: .pink, phase: 0),
            .init(p: .init(x: 0.78, y: 0.10), radius: 0.14, color: .yellow, phase: 0.9),
            .init(p: .init(x: 0.10, y: 0.40), radius: 0.10, color: .mint, phase: 1.6),
            .init(p: .init(x: 0.88, y: 0.32), radius: 0.11, color: .purple, phase: 2.2),
        ]
        for b in blooms {
            guard sin(time * 2.6 + b.phase) > -0.35 else { continue }
            let c = PortraitLayout.point(b.p, in: imageRect)
            let r = imageRect.width * b.radius
            let a = 0.10 + 0.12 * abs(sin(time * 3 + b.phase))
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(Gradient(colors: [b.color.opacity(a), .clear]), center: c, startRadius: 2, endRadius: r)
            )
        }
    }

    private static func screenBorderGlow(context: GraphicsContext, rect: CGRect, time: Double, color: Color) {
        let pulse = 0.4 + 0.5 * (0.5 + 0.5 * sin(time * 3.0))
        context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 2), with: .color(color.opacity(0.08 * pulse)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.65 * pulse)), lineWidth: 2)
        context.fill(Path(rect), with: .color(color.opacity(0.06 * pulse)))
    }

    private static func champagneBubbles(context: GraphicsContext, liquid: CGRect, time: Double) {
        let bowl = liquid.insetBy(dx: liquid.width * 0.12, dy: liquid.height * 0.1)
        guard bowl.width > 2, bowl.height > 2 else { return }
        for i in 0..<9 {
            let seed = Double(i) * 0.73
            let x = bowl.minX + bowl.width * CGFloat(0.25 + 0.5 * fract(sin(seed) * 4.2))
            let rise = fract(time * 0.24 + seed * 0.13)
            let y = bowl.minY + bowl.height * (1 - CGFloat(rise))
            let r: CGFloat = 1.0 + CGFloat(i % 3) * 0.35
            let pt = CGPoint(x: x, y: y)
            guard bowl.insetBy(dx: r + 0.5, dy: r + 0.5).contains(pt) else { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                with: .color(Color.white.opacity(0.55 + 0.3 * abs(sin(time + seed))))
            )
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
