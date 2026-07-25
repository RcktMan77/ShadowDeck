//
//  ChargenArtViews.swift
//  ShadowDeck
//
//  Painted portraits with per-role / per-metatype animated environmental FX.
//  The painted figure stays still; only environment/glow layers animate.
//

import SwiftUI
import AppKit

enum ChargenArtLoader {
    static func nsImage(named name: String) -> NSImage? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: name, withExtension: "jpg", subdirectory: "ChargenArt")
            ?? bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/ChargenArt")
            ?? bundle.url(forResource: name, withExtension: "jpg")
        {
            return NSImage(contentsOf: url)
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/ChargenArt/\(name).jpg")
        return NSImage(contentsOf: dev)
    }

    static func archetypeImageName(_ archetype: RunnerArchetype) -> String {
        "archetype_\(archetype.rawValue)"
    }

    static func metatypeImageName(_ metatype: MetatypeID) -> String {
        "metatype_\(metatype.rawValue)"
    }
}

// MARK: - Portrait

struct PaintedPortraitView: View {
    enum Kind: Equatable {
        case archetype(RunnerArchetype)
        case metatype(MetatypeID)
        case custom // NSImage not Equatable; pass via external binding — use customImage
    }

    let kind: Kind
    var customImage: NSImage? = nil
    var cornerRadius: CGFloat = 14
    var showLabel: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = resolvedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: fallbackColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    Canvas { ctx, size in
                        let t = context.date.timeIntervalSinceReferenceDate
                        drawFX(context: ctx, size: size, time: t)
                    }
                }
                .allowsHitTesting(false)

                if showLabel {
                    VStack {
                        Spacer()
                        HStack {
                            Text(label)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                                .padding(10)
                            Spacer()
                        }
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var resolvedImage: NSImage? {
        switch kind {
        case .archetype(let a):
            return ChargenArtLoader.nsImage(named: ChargenArtLoader.archetypeImageName(a))
        case .metatype(let m):
            return ChargenArtLoader.nsImage(named: ChargenArtLoader.metatypeImageName(m))
        case .custom:
            return customImage
        }
    }

    private var label: String {
        switch kind {
        case .archetype(let a): a.displayName
        case .metatype(let m): m.displayName
        case .custom: "Portrait"
        }
    }

    private var fallbackColors: [Color] {
        switch kind {
        case .archetype(let a): a.backdropColors
        case .metatype: [.black, .gray]
        case .custom: [.black, .gray]
        }
    }

    private func drawFX(context: GraphicsContext, size: CGSize, time: Double) {
        switch kind {
        case .archetype(let a):
            PortraitFX.drawArchetype(a, context: context, size: size, time: time)
        case .metatype(let m):
            PortraitFX.drawMetatype(m, context: context, size: size, time: time)
        case .custom:
            break
        }
    }
}

// MARK: - Per-subject FX

enum PortraitFX {
    static func drawArchetype(_ archetype: RunnerArchetype, context: GraphicsContext, size: CGSize, time: Double) {
        switch archetype {
        case .streetSamurai:
            rain(context: context, size: size, time: time, color: .white.opacity(0.35), density: 22)
            softVignette(context: context, size: size, opacity: 0.2)
        case .adept:
            // Urban screens flicker in upper background + fist glow lower-center
            screenTiles(context: context, size: size, time: time, region: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.42))
            radialPulse(context: context, center: CGPoint(x: size.width * 0.42, y: size.height * 0.62), radius: size.width * 0.18, time: time, color: .cyan)
            radialPulse(context: context, center: CGPoint(x: size.width * 0.58, y: size.height * 0.64), radius: size.width * 0.16, time: time + 0.7, color: .mint)
        case .combatMage:
            lightningArc(context: context, size: size, time: time)
            radialPulse(context: context, center: CGPoint(x: size.width * 0.5, y: size.height * 0.48), radius: size.width * 0.22, time: time, color: .purple)
        case .face:
            neonFlickerBars(context: context, size: size, time: time, colors: [.yellow, .orange, .pink])
        case .decker:
            // Matrix glyphs only inside approximate laptop screen region (lower-center)
            let screen = CGRect(
                x: size.width * 0.28,
                y: size.height * 0.38,
                width: size.width * 0.44,
                height: size.height * 0.28
            )
            context.drawLayer { layer in
                layer.clip(to: Path(roundedRect: screen, cornerRadius: 4))
                matrixGlyphs(context: layer, in: screen, time: time, columns: 10)
                let glow = 0.12 + 0.1 * sin(time * 3.2)
                layer.fill(Path(screen), with: .color(Color.cyan.opacity(glow)))
            }
            // Soft screen spill on desk only (not full rain)
            let spill = CGRect(x: size.width * 0.2, y: size.height * 0.62, width: size.width * 0.6, height: size.height * 0.2)
            context.fill(Path(spill), with: .color(Color.cyan.opacity(0.04 + 0.03 * sin(time * 2))))
        case .rigger:
            // Eye / cable pulses — upper face region and neck strand
            radialPulse(context: context, center: CGPoint(x: size.width * 0.46, y: size.height * 0.36), radius: 14, time: time, color: .cyan)
            radialPulse(context: context, center: CGPoint(x: size.width * 0.54, y: size.height * 0.36), radius: 14, time: time + 0.4, color: .cyan)
            cablePulse(context: context, from: CGPoint(x: size.width * 0.5, y: size.height * 0.4), to: CGPoint(x: size.width * 0.62, y: size.height * 0.72), time: time)
            cablePulse(context: context, from: CGPoint(x: size.width * 0.48, y: size.height * 0.42), to: CGPoint(x: size.width * 0.35, y: size.height * 0.7), time: time + 1.1)
        case .technomancer:
            floatingCards(context: context, size: size, time: time)
            champagneBubbles(context: context, size: size, time: time)
            neonSignPulse(context: context, size: size, time: time, color: .pink)
        case .spy:
            backgroundGlyphsVertical(context: context, size: size, time: time)
        }
    }

    static func drawMetatype(_ metatype: MetatypeID, context: GraphicsContext, size: CGSize, time: Double) {
        switch metatype {
        case .human:
            screenTiles(context: context, size: size, time: time, region: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.55))
        case .elf:
            ambientPulse(context: context, size: size, time: time, color: .green)
        case .dwarf:
            ambientPulse(context: context, size: size, time: time, color: .blue)
            flameFlicker(context: context, size: size, time: time)
        case .ork:
            neonSignPulse(context: context, size: size, time: time, color: .orange)
            flickerSignText(context: context, size: size, time: time)
        case .troll:
            ambientPulse(context: context, size: size, time: time, color: .cyan)
            softVignette(context: context, size: size, opacity: 0.15)
        }
    }

    // MARK: Primitives

    private static func softVignette(context: GraphicsContext, size: CGSize, opacity: Double) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(opacity)]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.4),
                startRadius: 20,
                endRadius: max(size.width, size.height) * 0.75
            )
        )
    }

    private static func rain(context: GraphicsContext, size: CGSize, time: Double, color: Color, density: Int) {
        for i in 0..<density {
            let seed = Double(i) * 7.13
            let x = size.width * (0.02 + 0.96 * fract(sin(seed) * 43758.5453))
            let speed = 40.0 + Double(i % 6) * 14
            let y = size.height * fract(time * speed * 0.012 + seed)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 1, y: y + 12 + CGFloat(i % 5) * 3))
            context.stroke(path, with: .color(color.opacity(0.25 + 0.15 * sin(time + seed))), lineWidth: 1.2)
        }
    }

    private static func screenTiles(context: GraphicsContext, size: CGSize, time: Double, region: CGRect) {
        let cols = 5
        let rows = 3
        let tw = region.width / CGFloat(cols)
        let th = region.height / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let flicker = 0.05 + 0.12 * abs(sin(time * (1.5 + Double(c) * 0.3) + Double(r)))
                let rect = CGRect(
                    x: region.minX + CGFloat(c) * tw + 2,
                    y: region.minY + CGFloat(r) * th + 2,
                    width: tw - 4,
                    height: th - 4
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.cyan.opacity(flicker)))
                // Scanline
                let sy = rect.minY + rect.height * CGFloat(fract(time * 0.4 + Double(c) * 0.1))
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: sy))
                line.addLine(to: CGPoint(x: rect.maxX, y: sy))
                context.stroke(line, with: .color(Color.white.opacity(0.15)), lineWidth: 1)
            }
        }
    }

    private static func radialPulse(context: GraphicsContext, center: CGPoint, radius: CGFloat, time: Double, color: Color) {
        let pulse = 0.15 + 0.2 * (0.5 + 0.5 * sin(time * 3.5))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(pulse), .clear]),
                center: center,
                startRadius: 2,
                endRadius: radius
            )
        )
    }

    private static func lightningArc(context: GraphicsContext, size: CGSize, time: Double) {
        let left = CGPoint(x: size.width * 0.38, y: size.height * 0.5)
        let right = CGPoint(x: size.width * 0.62, y: size.height * 0.5)
        let midY = size.height * 0.5 + CGFloat(sin(time * 12)) * 8
        var path = Path()
        path.move(to: left)
        let segs = 6
        for i in 1...segs {
            let t = CGFloat(i) / CGFloat(segs)
            let x = left.x + (right.x - left.x) * t
            let jitter = CGFloat(sin(time * 18 + Double(i) * 2.3)) * (6 + CGFloat(i % 3) * 3)
            path.addLine(to: CGPoint(x: x, y: midY + jitter))
        }
        let flash = 0.45 + 0.45 * abs(sin(time * 9))
        context.stroke(path, with: .color(Color.purple.opacity(flash)), lineWidth: 2.5)
        context.stroke(path, with: .color(Color.white.opacity(flash * 0.7)), lineWidth: 1)
    }

    private static func neonFlickerBars(context: GraphicsContext, size: CGSize, time: Double, colors: [Color]) {
        for i in 0..<5 {
            let on = sin(time * (2.0 + Double(i)) + Double(i)) > -0.2
            guard on else { continue }
            let y = size.height * (0.12 + CGFloat(i) * 0.08)
            var path = Path()
            path.addRoundedRect(
                in: CGRect(x: size.width * 0.08, y: y, width: size.width * 0.35, height: 6),
                cornerSize: CGSize(width: 2, height: 2)
            )
            let c = colors[i % colors.count]
            context.fill(path, with: .color(c.opacity(0.35 + 0.25 * abs(sin(time * 4 + Double(i))))))
        }
    }

    private static func matrixGlyphs(context: GraphicsContext, in rect: CGRect, time: Double, columns: Int) {
        let colW = rect.width / CGFloat(columns)
        let glyphs = Array("01⌬◈▣≡≈λΨ¥§#@$")
        for c in 0..<columns {
            let x = rect.minX + CGFloat(c) * colW + colW * 0.3
            for row in 0..<8 {
                let phase = time * (1.2 + Double(c) * 0.15) + Double(row) * 0.35
                let y = rect.minY + rect.height * fract(phase * 0.15 + Double(c) * 0.07) + CGFloat(row) * 10
                guard y > rect.minY && y < rect.maxY - 4 else { continue }
                let ch = glyphs[(c + row + Int(time * 3)) % glyphs.count]
                let str = String(ch) as NSString
                // Canvas doesn't have text easily — draw as small rects approximating glyphs
                let gRect = CGRect(x: x, y: y, width: 4, height: 7)
                let alpha = 0.35 + 0.35 * abs(sin(phase))
                context.fill(Path(gRect), with: .color(Color.green.opacity(alpha)))
                if row % 2 == 0 {
                    context.stroke(Path(gRect), with: .color(Color.mint.opacity(alpha)), lineWidth: 0.5)
                }
                _ = str
            }
        }
    }

    private static func cablePulse(context: GraphicsContext, from: CGPoint, to: CGPoint, time: Double) {
        var path = Path()
        path.move(to: from)
        let mid = CGPoint(x: (from.x + to.x) / 2 + CGFloat(sin(time * 2)) * 4, y: (from.y + to.y) / 2)
        path.addQuadCurve(to: to, control: mid)
        let glow = 0.35 + 0.35 * abs(sin(time * 4))
        context.stroke(path, with: .color(Color.cyan.opacity(glow)), lineWidth: 3)
        context.stroke(path, with: .color(Color.white.opacity(glow * 0.5)), lineWidth: 1)
        // Traveling bead
        let t = CGFloat(fract(time * 0.6))
        let bead = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        context.fill(Path(ellipseIn: CGRect(x: bead.x - 3, y: bead.y - 3, width: 6, height: 6)), with: .color(Color.cyan.opacity(0.9)))
    }

    private static func floatingCards(context: GraphicsContext, size: CGSize, time: Double) {
        for i in 0..<6 {
            let seed = Double(i) * 1.7
            let x = size.width * (0.1 + 0.8 * fract(sin(seed) * 12.3 + time * 0.05))
            let y = size.height * (0.15 + 0.5 * fract(cos(seed) * 9.1 + time * 0.07))
            let rect = CGRect(x: x, y: y, width: 18, height: 12)
            let alpha = 0.25 + 0.2 * abs(sin(time + seed))
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.white.opacity(alpha)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.yellow.opacity(alpha)), lineWidth: 0.8)
        }
    }

    private static func champagneBubbles(context: GraphicsContext, size: CGSize, time: Double) {
        // Approximate glass region lower-right
        let gx = size.width * 0.62
        let gy = size.height * 0.55
        let gh = size.height * 0.25
        let gw = size.width * 0.12
        for i in 0..<10 {
            let seed = Double(i) * 0.9
            let x = gx + gw * CGFloat(fract(sin(seed) * 3.1))
            let y = gy + gh * (1 - fract(time * 0.25 + seed * 0.2))
            let r: CGFloat = 1.5 + CGFloat(i % 3)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                with: .color(Color.white.opacity(0.35 + 0.2 * abs(sin(time + seed))))
            )
        }
    }

    private static func neonSignPulse(context: GraphicsContext, size: CGSize, time: Double, color: Color) {
        let pulse = 0.12 + 0.18 * (0.5 + 0.5 * sin(time * 2.8))
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.35)),
            with: .color(color.opacity(pulse))
        )
    }

    private static func ambientPulse(context: GraphicsContext, size: CGSize, time: Double, color: Color) {
        let pulse = 0.08 + 0.14 * (0.5 + 0.5 * sin(time * 2.2))
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(pulse), .clear]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.35),
                startRadius: 10,
                endRadius: size.width * 0.7
            )
        )
    }

    private static func flameFlicker(context: GraphicsContext, size: CGSize, time: Double) {
        for i in 0..<8 {
            let seed = Double(i)
            let x = size.width * (0.15 + 0.7 * fract(sin(seed * 2.1)))
            let baseY = size.height * 0.75
            let h = 12 + 18 * abs(sin(time * 6 + seed))
            var path = Path()
            path.move(to: CGPoint(x: x, y: baseY))
            path.addQuadCurve(
                to: CGPoint(x: x, y: baseY - h),
                control: CGPoint(x: x + CGFloat(sin(time * 8 + seed)) * 6, y: baseY - h * 0.5)
            )
            path.addQuadCurve(
                to: CGPoint(x: x, y: baseY),
                control: CGPoint(x: x - CGFloat(cos(time * 7 + seed)) * 5, y: baseY - h * 0.4)
            )
            context.fill(path, with: .color(Color.orange.opacity(0.25 + 0.2 * abs(sin(time * 5 + seed)))))
        }
    }

    private static func flickerSignText(context: GraphicsContext, size: CGSize, time: Double) {
        // Stylized block "letters" for OPEN / SCRAP MEAT feel in upper region
        let flickerOn = sin(time * 5.5) > 0.15
        guard flickerOn else { return }
        let blocks = 4
        for i in 0..<blocks {
            let rect = CGRect(
                x: size.width * 0.12 + CGFloat(i) * 16,
                y: size.height * 0.12,
                width: 12,
                height: 10
            )
            context.fill(Path(rect), with: .color(Color.red.opacity(0.55)))
        }
        // Second sign occasionally drops a letter
        if sin(time * 3.1) > 0 {
            let rect = CGRect(x: size.width * 0.55, y: size.height * 0.18, width: 40, height: 8)
            context.fill(Path(rect), with: .color(Color.orange.opacity(0.5)))
        }
    }

    private static func backgroundGlyphsVertical(context: GraphicsContext, size: CGSize, time: Double) {
        let cols = 8
        for c in 0..<cols {
            let x = size.width * (0.05 + 0.9 * CGFloat(c) / CGFloat(cols))
            for row in 0..<12 {
                let phase = time * 0.9 + Double(c) * 0.4 + Double(row) * 0.2
                let y = size.height * fract(phase * 0.12)
                let rect = CGRect(x: x, y: y, width: 5, height: 9)
                let alpha = 0.25 + 0.35 * abs(sin(phase * 2))
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color.green.opacity(alpha)))
                // Glow
                context.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 2), with: .color(Color.mint.opacity(alpha * 0.5)), lineWidth: 1.5)
            }
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}

// MARK: - Emphasized text with term help

struct EmphasizedHelpText: View {
    /// Source text using **Term** markers for emphasis.
    let text: String

    var body: some View {
        segments.reduce(Text("")) { partial, segment in
            if segment.emphasized {
                return partial + Text(segment.value)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            } else {
                return partial + Text(segment.value)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .help(helpSummary)
    }

    private var helpSummary: String {
        segments.filter(\.emphasized).compactMap { term -> String? in
            let key = term.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = AttributeID.allCases.first(where: { $0.displayName.caseInsensitiveCompare(key) == .orderedSame || $0.rawValue.caseInsensitiveCompare(key) == .orderedSame }) {
                return "\(id.displayName): \(ChargenHelpCatalog.attributeDescription(id))"
            }
            // Skill-ish keys
            let skillKeys = ChargenSkillCatalog.active
            if let skill = skillKeys.first(where: { $0.name.localizedCaseInsensitiveContains(key) || key.localizedCaseInsensitiveContains($0.key) }) {
                return "\(skill.name): \(ChargenHelpCatalog.skillDescription(catalogKey: skill.key))"
            }
            switch key.lowercased() {
            case "resources": return ChargenHelpCatalog.resourcesHelp
            case "magic", "resonance", "magic/resonance": return ChargenHelpCatalog.magicResonancePriorityHelp
            case "edge": return ChargenHelpCatalog.attributeDescription(.edge)
            case "essence": return ChargenHelpCatalog.attributeDescription(.essence)
            case "stealth", "sneaking": return ChargenHelpCatalog.skillDescription(catalogKey: "sneaking")
            case "perception": return ChargenHelpCatalog.skillDescription(catalogKey: "perception")
            case "piloting": return ChargenHelpCatalog.skillDescription(catalogKey: "piloting")
            case "influence", "negotiation": return ChargenHelpCatalog.skillDescription(catalogKey: "negotiation")
            case "sorcery", "spellcasting": return ChargenHelpCatalog.skillDescription(catalogKey: "spellcasting")
            case "tasking", "hacking", "cracking": return ChargenHelpCatalog.skillDescription(catalogKey: "hacking")
            default: return nil
            }
        }
        .joined(separator: "\n\n")
    }

    private struct Segment {
        var value: String
        var emphasized: Bool
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var remaining = text[...]
        while let start = remaining.range(of: "**") {
            let before = String(remaining[..<start.lowerBound])
            if !before.isEmpty { result.append(Segment(value: before, emphasized: false)) }
            remaining = remaining[start.upperBound...]
            if let end = remaining.range(of: "**") {
                let mid = String(remaining[..<end.lowerBound])
                result.append(Segment(value: mid, emphasized: true))
                remaining = remaining[end.upperBound...]
            } else {
                result.append(Segment(value: String(remaining), emphasized: false))
                remaining = ""
            }
        }
        if !remaining.isEmpty {
            result.append(Segment(value: String(remaining), emphasized: false))
        }
        return result
    }
}

// MARK: - Profile chrome (progressive summary)

struct ProfileArtChrome: View {
    let draft: GenerationDraft
    var height: CGFloat = 108

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = draft.avatarData, let img = NSImage(data: data) {
                    PaintedPortraitView(kind: .custom, customImage: img, cornerRadius: 10, showLabel: false)
                } else {
                    PaintedPortraitView(kind: .archetype(draft.archetype), cornerRadius: 10, showLabel: false)
                }
            }
            .frame(width: height * 0.78, height: height)

            VStack(alignment: .leading, spacing: 4) {
                summaryLine("Role", draft.archetype.displayName)
                summaryLine("Metatype", draft.metatype.displayName)
                summaryLine("Edition", draft.edition.shortName)

                if draft.step >= .priorities, draft.priority.isComplete || draft.generationSystem == .buildPoints {
                    summaryLine("Priorities", prioritySummary)
                }
                if draft.step >= .attributes {
                    summaryLine("Attributes", attributeHighlights)
                }
                if draft.step >= .magic {
                    let path = draft.awakened == .mundane
                        ? ChargenHelpCatalog.mundanePathLabel
                        : draft.awakened.displayName
                    summaryLine("Path", path)
                }
                if draft.step >= .skills, !draft.skills.isEmpty {
                    let top = draft.skills.sorted { $0.rating > $1.rating }.prefix(3)
                        .map { "\($0.displayName) \($0.rating)" }
                        .joined(separator: " · ")
                    summaryLine("Skills", top.isEmpty ? "—" : top)
                }
                if draft.step >= .qualities, !draft.qualities.isEmpty {
                    summaryLine("Qualities", "\(draft.qualities.count) selected")
                }
                if draft.step >= .resources {
                    summaryLine("Nuyen", "¥\(draft.nuyen)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private var prioritySummary: String {
        if draft.generationSystem == .buildPoints {
            return "Build Points"
        }
        return PriorityColumn.allCases.compactMap { col in
            guard let letter = draft.priority[col] else { return nil }
            return "\(shortCol(col)) \(letter.rawValue)"
        }.joined(separator: " · ")
    }

    private func shortCol(_ col: PriorityColumn) -> String {
        switch col {
        case .metatype: "Meta"
        case .attributes: "Attr"
        case .magicOrResonance: "Mag"
        case .skills: "Skl"
        case .resources: "Res"
        }
    }

    private var attributeHighlights: String {
        let ids: [AttributeID] = [.body, .agility, .reaction, .strength, .willpower, .logic, .intuition, .charisma]
        return ids.map { "\(String($0.displayName.prefix(3))) \(draft.attributes[$0])" }.joined(separator: " ")
    }
}

// MARK: - Priority banner (compact)

struct PriorityBalanceBanner: View {
    let draft: GenerationDraft

    private var assignedCount: Int {
        PriorityColumn.allCases.filter { draft.priority[$0] != nil }.count
    }

    private var sum: Int { draft.priority.sumToTenTotal }
    private var sumRemainingToTen: Int { 10 - sum }
    private var isSumToTen: Bool {
        draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isSumToTen ? "Sum-to-Ten" : "Priority A–E")
                    .font(.caption.weight(.semibold))
                if draft.priorityValid && draft.priority.isComplete {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("In progress")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Divider().frame(height: 28)

            if isSumToTen {
                compactMetric("Used", "\(sum)")
                compactMetric("Left", "\(sumRemainingToTen)")
                compactMetric("Target", "10")
            } else {
                compactMetric("Set", "\(assignedCount)/5")
                compactMetric("Left", "\(max(0, 5 - assignedCount))")
            }

            Divider().frame(height: 28)

            HStack(spacing: 4) {
                ForEach(PriorityColumn.allCases, id: \.self) { col in
                    let letter = draft.priority[col]?.rawValue ?? "·"
                    Text(letter)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .frame(width: 18, height: 22)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .help(col.displayName)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
        }
    }
}

struct RecommendButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                Label(title, systemImage: "sparkles.rectangle.stack")
            }
            .buttonStyle(.borderedProminent)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HelpCallout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
