//
//  CharacterGlanceColumns.swift
//  ShadowDeck
//
//  Extracted Summary dashboard columns (portrait, attributes, identity, condition).
//  Mutations stay in CharacterAtAGlanceView via callbacks — no behavior change.
//

import AppKit
import SwiftUI

// MARK: - Metrics

enum CharacterGlancePortraitMetrics {
    static let width: CGFloat = 280
    static let height: CGFloat = 350
    static let cornerRadius: CGFloat = 16
    static let attributesMaxWidth: CGFloat = 440
}

// MARK: - Portrait

struct CharacterGlancePortraitColumn: View {
    let character: Character
    var onChangePortrait: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            portraitView
                .frame(
                    width: CharacterGlancePortraitMetrics.width,
                    height: CharacterGlancePortraitMetrics.height
                )
                .clipped()
                .clipShape(RoundedRectangle(
                    cornerRadius: CharacterGlancePortraitMetrics.cornerRadius,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CharacterGlancePortraitMetrics.cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                .contentShape(RoundedRectangle(
                    cornerRadius: CharacterGlancePortraitMetrics.cornerRadius,
                    style: .continuous
                ))
                .onTapGesture(perform: onChangePortrait)
                .help("Click to change portrait")
                .accessibilityLabel(
                    character.avatar.hasImage ? "Character portrait" : "Portrait placeholder"
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double-click to change portrait")

            Button(action: onChangePortrait) {
                Label(
                    character.avatar.hasImage ? "Change Portrait…" : "Add Portrait…",
                    systemImage: "photo"
                )
            }
            .controlSize(.small)

            Text(character.avatar.hasImage
                 ? (character.avatar.isAnimated ? "Animated portrait" : "Custom portrait")
                 : "No custom portrait — showing placeholder")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: CharacterGlancePortraitMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: CharacterGlancePortraitMetrics.width, alignment: .bottom)
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var portraitView: some View {
        if let data = character.avatar.inlineData, !data.isEmpty {
            if character.avatar.isAnimated || GIFDecoder.isAnimatedImageData(data) {
                AnimatedImageView(data: data, contentMode: .fill)
            } else if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                portraitPlaceholder
            }
        } else if let meta = ChargenArtLoader.nsImage(
            named: ChargenArtLoader.metatypeImageName(character.metatype)
        ) {
            Image(nsImage: meta)
                .resizable()
                .scaledToFill()
        } else {
            portraitPlaceholder
        }
    }

    private var portraitPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.secondary.opacity(0.2), .secondary.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Identity header

struct CharacterGlanceIdentityHeader: View {
    let character: Character
    var houseRulesLabel: String
    var onOpenHouseRules: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(character.displayTitle)
                .font(.largeTitle.weight(.bold))
                .textSelection(.enabled)

            HStack(alignment: .center, spacing: 12) {
                FlowChips(items: [
                    character.edition.shortName,
                    character.metatype.displayName,
                    character.awakened == .mundane ? "Mundane" : character.awakened.displayName,
                    character.generation.system.displayName
                ])

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if character.houseRules.enabled.isEmpty {
                        Text(houseRulesLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(houseRulesLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                    Button("House Rules…", action: onOpenHouseRules)
                        .controlSize(.small)
                        .accessibilityLabel("Edit house rules")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Condition monitors

struct CharacterGlanceConditionCard: View {
    let physicalDamage: Int
    let physicalBoxes: Int
    let stunDamage: Int
    let stunBoxes: Int
    let overflowBoxes: Int
    var onPhysicalSelect: (Int) -> Void
    var onPhysicalClear: () -> Void
    var onStunSelect: (Int) -> Void
    var onStunClear: () -> Void

    var body: some View {
        CharacterGlanceSectionCard(title: "Condition Monitors") {
            VStack(alignment: .leading, spacing: 12) {
                CharacterGlanceMonitorRow(
                    title: "Physical",
                    damage: physicalDamage,
                    boxes: physicalBoxes,
                    color: .green,
                    onSelect: onPhysicalSelect,
                    onClear: onPhysicalClear
                )
                CharacterGlanceMonitorRow(
                    title: "Stun",
                    damage: stunDamage,
                    boxes: stunBoxes,
                    color: .green,
                    onSelect: onStunSelect,
                    onClear: onStunClear
                )
                Text("Click a box to fill through that mark (damage). Click Clear for healthy. Overflow capacity: \(overflowBoxes).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CharacterGlanceMonitorRow: View {
    let title: String
    let damage: Int
    let boxes: Int
    let color: Color
    var onSelect: (Int) -> Void
    var onClear: () -> Void

    /// Shared label width so Physical / Stun box rows start on the same x.
    private static let titleColumnWidth: CGFloat = 64
    private static let boxWidth: CGFloat = 16
    private static let boxHeight: CGFloat = 20
    private static let boxSpacing: CGFloat = 3

    var body: some View {
        let remaining = max(0, boxes - damage)
        let status: String = {
            if boxes <= 0 { return "—" }
            if damage <= 0 { return "Healthy" }
            if remaining <= 0 { return "Filled" }
            return "\(remaining) open"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: Self.titleColumnWidth, alignment: .leading)
                Text("\(damage) damage / \(boxes) boxes · \(status)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(damage > 0 ? color : .secondary)
                Spacer(minLength: 0)
                Button("Clear") { onClear() }
                    .controlSize(.mini)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear \(title.lowercased()) damage")
            }
            // Fixed-size boxes in a leading HStack so every track shares the same origin
            // and column pitch (Stun has fewer boxes; empties simply stop earlier).
            HStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(width: Self.titleColumnWidth)
                HStack(spacing: Self.boxSpacing) {
                    ForEach(0..<max(boxes, 0), id: \.self) { i in
                        monitorBox(index: i)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func monitorBox(index i: Int) -> some View {
        let filled = i < damage
        return Button {
            if damage == i + 1 {
                if i == 0 {
                    onClear()
                } else {
                    onSelect(i - 1)
                }
            } else {
                onSelect(i)
            }
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? color.opacity(0.9) : Color.secondary.opacity(0.15))
                .frame(width: Self.boxWidth, height: Self.boxHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .help("Set damage through box \(i + 1)")
        .accessibilityLabel("\(title) box \(i + 1)\(filled ? ", filled" : "")")
    }
}

// MARK: - Shared section chrome

struct CharacterGlanceSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }
}
