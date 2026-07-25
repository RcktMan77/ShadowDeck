//
//  ChargenArtViews.swift
//  ShadowDeck
//
//  Painted portraits with animated environmental overlays (character stays still).
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
        // Source-tree fallback for debug runs before copy-bundle settles.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Generation
            .deletingLastPathComponent() // UI
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

/// Full painted portrait + subtle animated FX (rain, glyphs, glow) — subject not warped.
struct PaintedPortraitView: View {
    enum Kind {
        case archetype(RunnerArchetype)
        case metatype(MetatypeID)
        case custom(NSImage)
    }

    let kind: Kind
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

                // Animated environmental overlay only (does not move the painted figure).
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                    Canvas { ctx, size in
                        let t = context.date.timeIntervalSinceReferenceDate
                        drawOverlay(context: ctx, size: size, time: t)
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
        case .custom(let img):
            return img
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

    private func drawOverlay(context: GraphicsContext, size: CGSize, time: Double) {
        // Soft vignette
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.25)]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.4),
                startRadius: 20,
                endRadius: max(size.width, size.height) * 0.7
            )
        )

        // Animated scanlines / rain / matrix ticks at edges so the figure stays readable
        for i in 0..<18 {
            let seed = Double(i) * 7.13
            let x = size.width * (0.05 + 0.9 * fract(sin(seed) * 43758.5453))
            let speed = 35.0 + Double(i % 5) * 12
            let y = size.height * fract(time * speed * 0.01 + seed)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + 10 + CGFloat(i % 4) * 4))
            let opacity = 0.12 + 0.1 * sin(time + seed)
            context.stroke(path, with: .color(Color.cyan.opacity(opacity)), lineWidth: 1)

            // Glyph ticks
            if i % 3 == 0 {
                let glyphY = size.height * fract(time * 0.08 + seed * 0.1)
                let rect = CGRect(x: x, y: glyphY, width: 2, height: 6)
                context.fill(Path(rect), with: .color(Color.green.opacity(0.2)))
            }
        }

        // Gentle light pulse on lower third (screen glow metaphor)
        let pulse = 0.08 + 0.06 * sin(time * 1.7)
        context.fill(
            Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45)),
            with: .color(Color.cyan.opacity(pulse))
        )
    }

    private func fract(_ x: Double) -> Double { x - floor(x) }
}

/// Compact portrait for wizard chrome after role is chosen.
struct ProfileArtChrome: View {
    let draft: GenerationDraft
    var height: CGFloat = 96

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = draft.avatarData, let img = NSImage(data: data) {
                    PaintedPortraitView(kind: .custom(img), cornerRadius: 10, showLabel: false)
                } else {
                    PaintedPortraitView(kind: .archetype(draft.archetype), cornerRadius: 10, showLabel: false)
                }
            }
            .frame(width: height * 0.75, height: height)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.archetype.displayName)
                    .font(.headline)
                Text(draft.metatype.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(draft.edition.shortName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Sticky priority balance banner.
struct PriorityBalanceBanner: View {
    let draft: GenerationDraft

    private var modeLabel: String {
        if draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen) {
            return "Sum-to-Ten"
        }
        return "Priority (unique A–E)"
    }

    private var assignedCount: Int {
        PriorityColumn.allCases.filter { draft.priority[$0] != nil }.count
    }

    private var sum: Int { draft.priority.sumToTenTotal }

    private var remainingUnique: Int {
        // For unique mode: 5 columns must be filled with distinct letters.
        max(0, 5 - assignedCount)
    }

    private var sumRemainingToTen: Int { 10 - sum }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(modeLabel, systemImage: "scale.3d")
                    .font(.headline)
                Spacer()
                if draft.priorityValid && draft.priority.isComplete {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Label("In progress", systemImage: "circle.dotted")
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.semibold))
                }
            }

            if draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    metric(title: "Points used", value: "\(sum)")
                    metric(title: "Target", value: "10")
                    metric(
                        title: sumRemainingToTen >= 0 ? "Remaining to 10" : "Over by",
                        value: "\(abs(sumRemainingToTen))",
                        emphasize: sumRemainingToTen == 0 && draft.priority.isComplete
                    )
                    metric(title: "Columns set", value: "\(assignedCount)/5")
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    metric(title: "Columns set", value: "\(assignedCount)/5")
                    metric(title: "Letters left to place", value: "\(remainingUnique)")
                    metric(title: "Unique letters", value: draft.priority.usesUniqueLetters && draft.priority.isComplete ? "Yes" : "Not yet")
                }
            }

            // Letter chips
            HStack(spacing: 6) {
                ForEach(PriorityColumn.allCases, id: \.self) { col in
                    let letter = draft.priority[col]?.rawValue ?? "—"
                    VStack(spacing: 2) {
                        Text(String(col.displayName.prefix(4)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(letter)
                            .font(.title3.monospacedDigit().weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5)
        }
    }

    private func metric(title: String, value: String, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(emphasize ? Color.green : Color.primary)
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
