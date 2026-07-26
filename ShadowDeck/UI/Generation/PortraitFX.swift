//
//  PortraitFX.swift
//  ShadowDeck
//
//  Minimal landmark FX. Prefer reliable effects over dense overlays.
//  Face, Rigger, and Infiltrator are intentionally static (landmarks too fragile).
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
    private static let adeptFistLower = NormPoint(x: 0.36, y: 0.58)
    private static let adeptFistUpper = NormPoint(x: 0.62, y: 0.30)

    /// Path along painted combat-mage lightning.
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

    private static let technoLiquid = NormRect(x: 0.845, y: 0.68, w: 0.045, h: 0.09)

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
                // One diffuse circular pulse travels the bolt; next starts only after it finishes.
                singleArcDischarge(context: layer, points: mageArc.map { PortraitLayout.point($0, in: img) }, time: time)

            case .face:
                // Static — LED landmarks too easy to misplace.
                break

            case .decker:
                // Static — angled screen glow was unreliable.
                break

            case .rigger:
                // Static — eye landmarks unreliable across crops.
                break

            case .technomancer:
                champagneBubbles(context: layer, liquid: PortraitLayout.rect(technoLiquid, in: img), time: time)

            case .spy:
                // Static — eye landmarks unreliable.
                break
            }
        }
    }

    static func drawMetatype(
        _ metatype: MetatypeID,
        context: GraphicsContext,
        viewSize: CGSize,
        time: Double
    ) {}

    // MARK: - Effects

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

    /// One soft, diffuse circular discharge travels the full arc quickly, then restarts.
    private static func singleArcDischarge(context: GraphicsContext, points: [CGPoint], time: Double) {
        guard points.count >= 2 else { return }

        // Faint path wash so the bolt stays lightly energized.
        var wash = Path()
        wash.move(to: points[0])
        for p in points.dropFirst() { wash.addLine(to: p) }
        context.stroke(wash, with: .color(Color.purple.opacity(0.10)), lineWidth: 10)

        // Fast electrical travel: full path in ~0.55s, then brief gap before next.
        let travel: Double = 0.55
        let gap: Double = 0.12
        let cycle = travel + gap
        let phase = time.truncatingRemainder(dividingBy: cycle)
        guard phase <= travel else { return } // pause between discharges

        let t = phase / travel
        // Ease slightly so it snaps through the middle of the bolt.
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        let pos = pointAlong(points, t: CGFloat(eased))

        // Very diffuse circular bloom — soft edges, still readable as a round pulse.
        let breath = 0.9 + 0.1 * sin(time * 14)
        let outer: CGFloat = 32 * breath
        let mid: CGFloat = 20 * breath
        let core: CGFloat = 9 * breath
        // Fade in/out at ends of travel for a strike feel.
        let envelope = sin(t * .pi)

        context.fill(
            Path(ellipseIn: CGRect(x: pos.x - outer, y: pos.y - outer, width: outer * 2, height: outer * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Color.purple.opacity(0.18 * envelope),
                    Color.purple.opacity(0.06 * envelope),
                    .clear,
                ]),
                center: pos,
                startRadius: mid * 0.5,
                endRadius: outer
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: pos.x - mid, y: pos.y - mid, width: mid * 2, height: mid * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.78, green: 0.5, blue: 1.0).opacity(0.32 * envelope),
                    Color.purple.opacity(0.12 * envelope),
                    .clear,
                ]),
                center: pos,
                startRadius: 2,
                endRadius: mid
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: pos.x - core, y: pos.y - core, width: core * 2, height: core * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.45 * envelope),
                    Color(red: 0.9, green: 0.75, blue: 1.0).opacity(0.22 * envelope),
                    .clear,
                ]),
                center: pos,
                startRadius: 0.5,
                endRadius: core
            )
        )
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

    private static func champagneBubbles(context: GraphicsContext, liquid: CGRect, time: Double) {
        let bowl = liquid.insetBy(dx: liquid.width * 0.1, dy: liquid.height * 0.08)
        guard bowl.width > 2, bowl.height > 2 else { return }
        // More bubbles, slightly larger, mild horizontal wobble for turbulence.
        for i in 0..<16 {
            let seed = Double(i) * 0.67
            let wobble = 0.08 * sin(time * 3.2 + seed * 4)
            let xFrac = 0.2 + 0.6 * fract(sin(seed) * 4.2) + wobble
            let x = bowl.minX + bowl.width * CGFloat(min(0.85, max(0.15, xFrac)))
            let speed = 0.32 + 0.12 * fract(sin(seed * 2.1))
            let rise = fract(time * speed + seed * 0.15)
            let y = bowl.minY + bowl.height * (1 - CGFloat(rise))
            let r: CGFloat = 1.4 + CGFloat(i % 4) * 0.45
            let pt = CGPoint(x: x, y: y)
            guard bowl.insetBy(dx: r + 0.5, dy: r + 0.5).contains(pt) else { continue }
            let alpha = 0.65 + 0.3 * abs(sin(time * 2 + seed))
            context.fill(
                Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                with: .color(Color.white.opacity(alpha))
            )
            // Tiny highlight for readability
            context.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.15, y: y - r * 0.35, width: r * 0.35, height: r * 0.35)),
                with: .color(Color.white.opacity(0.9))
            )
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
