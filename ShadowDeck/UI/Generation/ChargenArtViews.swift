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
    /// Resolve a bundled ChargenArt JPEG URL (app bundle or dev tree).
    static func resourceURL(named name: String) -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: name, withExtension: "jpg", subdirectory: "ChargenArt")
            ?? bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/ChargenArt")
            ?? bundle.url(forResource: name, withExtension: "jpg")
        {
            return url
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/ChargenArt/\(name).jpg")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static func nsImage(named name: String) -> NSImage? {
        guard let url = resourceURL(named: name) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Raw JPEG bytes for seeding avatars / thumbnails.
    static func jpegData(named name: String) -> Data? {
        guard let url = resourceURL(named: name) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func archetypeImageName(_ archetype: RunnerArchetype) -> String {
        "archetype_\(archetype.rawValue)"
    }

    static func metatypeImageName(_ metatype: MetatypeID) -> String {
        "metatype_\(metatype.rawValue)"
    }

    /// Default library/sheet portrait when the character has no custom avatar.
    static func metatypeNSImage(for metatype: MetatypeID) -> NSImage? {
        nsImage(named: metatypeImageName(metatype))
    }

    /// Prefer an explicit sample resource, then role art, then metatype.
    static func preferredPortraitData(
        resourceName: String? = nil,
        archetype: RunnerArchetype? = nil,
        metatype: MetatypeID
    ) -> Data? {
        if let resourceName, let data = jpegData(named: resourceName) {
            return data
        }
        if let archetype, let data = jpegData(named: archetypeImageName(archetype)) {
            return data
        }
        return jpegData(named: metatypeImageName(metatype))
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

                // Archetype FX only — metatypes stay fully static.
                if drawsFX {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                        Canvas { ctx, size in
                            let t = context.date.timeIntervalSinceReferenceDate
                            drawFX(context: ctx, viewSize: size, time: t)
                        }
                    }
                    .allowsHitTesting(false)
                }

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

    private var drawsFX: Bool {
        switch kind {
        case .archetype: true
        case .metatype, .custom: false
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

    private func drawFX(context: GraphicsContext, viewSize: CGSize, time: Double) {
        switch kind {
        case .archetype(let a):
            PortraitFX.drawArchetype(a, context: context, viewSize: viewSize, time: time)
        case .metatype(let m):
            PortraitFX.drawMetatype(m, context: context, viewSize: viewSize, time: time)
        case .custom:
            break
        }
    }
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
