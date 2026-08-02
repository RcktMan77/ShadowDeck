//
//  ArchetypeBackdrop.swift
//  ShadowDeck
//
//  Unified art style: silhouette + animated cyberpunk backdrop per archetype.
//  Pure SwiftUI (no external art deps); can be swapped for asset packs later.
//

import SwiftUI

struct ArchetypeBackdrop: View {
    let archetype: RunnerArchetype
    var isSelected: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let colors = archetype.backdropColors
                // Base gradient fill
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [colors[0], colors[1]]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                // Sweeping neon bands
                for i in 0..<5 {
                    let phase = t * (0.15 + Double(i) * 0.04) + Double(i)
                    let y = size.height * (0.15 + 0.15 * CGFloat(i)) + CGFloat(sin(phase)) * 12
                    var band = Path()
                    band.move(to: CGPoint(x: 0, y: y))
                    band.addLine(to: CGPoint(x: size.width, y: y + CGFloat(cos(phase)) * 8))
                    context.stroke(
                        band,
                        with: .color(colors[2].opacity(0.25 + 0.1 * sin(phase))),
                        lineWidth: 2 + CGFloat(i)
                    )
                }

                // Floating particles / rain
                for i in 0..<24 {
                    let seed = Double(i) * 12.9898
                    let x = size.width * CGFloat(fract(sin(seed) * 43758.5453))
                    let speed = 20.0 + Double(i % 7) * 8.0
                    let y = size.height * CGFloat(fract((t * speed * 0.01) + seed))
                    let r: CGFloat = i.isMultiple(of: 3) ? 2.5 : 1.2
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r * 3))
                    context.fill(dot, with: .color(colors[2].opacity(0.55)))
                }

                // Soft vignette
                context.fill(
                    Path(rect),
                    with: .radialGradient(
                        Gradient(colors: [.clear, .black.opacity(0.55)]),
                        center: CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                        startRadius: size.width * 0.15,
                        endRadius: size.width * 0.75
                    )
                )
            }
        }
        .overlay {
            // Character stand-in: large symbol with glow
            VStack(spacing: 12) {
                Image(systemName: archetype.symbolName)
                    .font(.system(size: isSelected ? 64 : 48, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: archetype.backdropColors[2].opacity(0.9), radius: 16)
                    .shadow(color: archetype.backdropColors[2].opacity(0.5), radius: 32)
                Text(archetype.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .padding()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isSelected ? archetype.backdropColors[2] : Color.white.opacity(0.15),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
    }

    private func fract(_ x: Double) -> Double {
        x - floor(x)
    }
}

struct ArchetypeSummaryCard: View {
    let archetype: RunnerArchetype
    let edition: Edition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(archetype.tagline)
                .font(.headline)
            Text(LocalizedStringKey(archetype.summaryMarkdown))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Suggested focus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                ForEach(archetype.suggestedFocus, id: \.self) { focus in
                    Text(focus)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            LabeledContent("Default path", value: archetype.defaultAwakened.displayName)
            LabeledContent("Edition context", value: edition.shortName)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
