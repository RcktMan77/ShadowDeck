//
//  CharacterGlanceDashboardSections.swift
//  ShadowDeck
//
//  Extracted Summary dashboard sections: attributes, vitals, lifestyle, story.
//

import SwiftUI

// MARK: - Attributes

struct CharacterGlanceAttributesColumn: View {
    let character: Character
    let essenceDisplay: String
    var onAdjust: (AttributeID, Int) -> Void
    var onRoll: (AttributeID) -> Void

    private var effects: CharacterEffects { character.effects }

    private let columns = [
        GridItem(.flexible(minimum: 96), spacing: 6),
        GridItem(.flexible(minimum: 96), spacing: 6),
        GridItem(.flexible(minimum: 96), spacing: 6)
    ]

    var body: some View {
        CharacterGlanceSectionCard(title: "Attributes") {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AttributeID.standardGenerationAttributes, id: \.self) { id in
                    editableTile(
                        id,
                        base: character.attributes[id],
                        bonus: effects.attributeBonus(for: id)
                    )
                }
                editableTile(
                    .edge,
                    base: character.attributes.edge,
                    bonus: effects.attributeBonus(for: .edge)
                )
                if character.awakened.usesMagic {
                    editableTile(
                        .magic,
                        base: character.attributes.magic,
                        bonus: effects.attributeBonus(for: .magic)
                    )
                }
                if character.awakened.usesResonance {
                    editableTile(
                        .resonance,
                        base: character.attributes.resonance,
                        bonus: effects.attributeBonus(for: .resonance)
                    )
                }
                essenceTile
            }
            Text("± edits base rating. Bonuses from equipped gear, augs, qualities, and powers show as +N.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !effects.applied.isEmpty {
                DisclosureGroup("Active modifiers (\(effects.applied.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(effects.applied) { mod in
                            Text(mod.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
    }

    private var essenceTile: some View {
        VStack(spacing: 3) {
            Text("Essence")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(essenceDisplay)
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func editableTile(_ id: AttributeID, base: Int, bonus: Int) -> some View {
        let effective = base + bonus
        return VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(id.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if id != .essence {
                    Button {
                        onRoll(id)
                    } label: {
                        Image(systemName: "dice")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Roll \(id.displayName) (pool \(effective))")
                }
            }
            HStack(spacing: 4) {
                Button {
                    onAdjust(id, -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    Text("\(effective)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 22)
                    if bonus != 0 {
                        Text(bonus > 0 ? "\(base)+\(bonus)" : "\(base)\(bonus)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                }

                Button {
                    onAdjust(id, 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            (bonus != 0 ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .help(bonus != 0 ? "Base \(base), modifiers \(bonus >= 0 ? "+" : "")\(bonus)" : "Base \(base)")
    }
}

// MARK: - Lifestyle banner

struct CharacterGlanceLifestyleBanner: View {
    let character: Character

    var body: some View {
        let burn = LifestyleTracker.burnSummary(for: character)
        if burn.activeCount > 0 {
            let status = burn.overallStatus
            let icon: String = {
                switch status {
                case .covered: "checkmark.seal.fill"
                case .due: "calendar.badge.exclamationmark"
                case .underfunded: "exclamationmark.triangle.fill"
                case .inactive: "house"
                }
            }()
            let color: Color = {
                switch status {
                case .covered: .green
                case .due: .orange
                case .underfunded: .red
                case .inactive: .secondary
                }
            }()
            let message: String = {
                switch status {
                case .covered:
                    return "Lifestyle covered — min \(burn.minimumPrepaidMonths) prepaid month(s). Burn ¥\(formatInt(burn.monthlyBurn))/mo."
                case .due:
                    return "Lifestyle due — ¥\(formatInt(burn.cashDue)) cash this process (reserve used first). Open the Lifestyle tab."
                case .underfunded:
                    return "Lifestyle underfunded — need ¥\(formatInt(burn.cashDue)), have ¥\(formatInt(burn.liquidity)) (nuyen + reserve)."
                case .inactive:
                    return "Lifestyle inactive."
                }
            }()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Vitals grid

struct CharacterGlanceVitalsGrid: View {
    let character: Character
    let derived: DerivedStats
    var canUndoKarma: Bool
    var onAwardKarma: () -> Void
    var onAwardKarmaFive: () -> Void
    var onUndoKarma: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                vital("Edge", "\(character.attributes.edge)", "bolt.fill")
                karmaAwardVital(
                    title: "Karma Available",
                    value: character.karmaAvailable,
                    systemImage: "sparkles",
                    canUndo: canUndoKarma,
                    onAward: onAwardKarma,
                    onAwardFive: onAwardKarmaFive,
                    onUndo: onUndoKarma
                )
                vital("Karma Total", "\(character.karmaTotal)", "chart.line.uptrend.xyaxis")
                vital("Nuyen", "¥\(formatInt(character.nuyen))", "yensign.circle.fill")
                vital(
                    "Lifestyle /mo",
                    "¥\(formatInt(LifestyleTracker.burnSummary(for: character).monthlyBurn))",
                    "house"
                )
                vital(
                    "Life. Reserve",
                    "¥\(formatInt(character.lifestyleNuyenReserve))",
                    "building.columns"
                )
                vital("Essence", essenceString, "heart.fill")
                vital("Armor", "\(derived.armor)", "shield.lefthalf.filled")
                vital("Initiative", initiativeString, "gauge.with.dots.needle.67percent")
                if let phys = derived.physicalLimit {
                    vital("Phys. Limit", "\(phys)", "shield")
                }
                vital("Contacts", "\(character.contacts.count)", "person.2")
                vital("Augmentations", "\(character.augmentations.count)", "cpu")
                if !character.adeptPowers.isEmpty {
                    vital("Adept Powers", "\(character.adeptPowers.count)", "bolt.heart")
                }
                if !character.spells.isEmpty {
                    vital("Spells", "\(character.spells.count)", "wand.and.stars")
                }
            }
            Text("Karma + awards 1 (available & total). Right‑click + to Award 5. Undo reverts the last manual award. Plan spends on the Advance tab.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var essenceString: String {
        let ess = derived.currentEssence
        let n = NSDecimalNumber(decimal: ess)
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "\(ess)"
    }

    private var initiativeString: String {
        "\(derived.initiativeBase) + \(derived.initiativeDice)D6"
    }

    private func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func vital(_ title: String, _ value: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func karmaAwardVital(
        title: String,
        value: Int,
        systemImage: String,
        canUndo: Bool,
        onAward: @escaping () -> Void,
        onAwardFive: @escaping () -> Void,
        onUndo: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(value)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 24)

                    Button(action: onAward) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Award 1 Karma (available + total). Right-click for Award 5.")
                    .contextMenu {
                        Button("Award 1 Karma") { onAward() }
                        Button("Award 5 Karma") { onAwardFive() }
                        if canUndo {
                            Divider()
                            Button("Undo Last Award") { onUndo() }
                        }
                    }

                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canUndo ? .secondary : Color.secondary.opacity(0.35))
                    .disabled(!canUndo)
                    .help(
                        canUndo
                            ? "Undo last manual karma award (available + total)."
                            : "No manual karma award to undo this session."
                    )
                    .accessibilityLabel("Undo last karma award")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Story / background

struct CharacterGlanceStorySection: View {
    let character: Character
    @Binding var isEditing: Bool
    @Binding var conceptDraft: String
    @Binding var backgroundDraft: String
    var onBeginEdit: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        CharacterGlanceSectionCard(title: "Concept & Background") {
            if isEditing {
                editor
            } else {
                display
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBeginEdit)
                    .help("Click to edit concept and background")
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Concept")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Short tagline (e.g. Ex-Renraku coder adept)", text: $conceptDraft)
                .textFieldStyle(.roundedBorder)

            Text("Background")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $backgroundDraft)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save Story", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var display: some View {
        let concept = character.concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let background = resolvedBackground

        return VStack(alignment: .leading, spacing: 10) {
            if concept.isEmpty && background.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No concept or background yet")
                            .font(.callout.weight(.medium))
                        Text("Click to add a tagline and story blurb for this runner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                if !concept.isEmpty {
                    Text(concept)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if !background.isEmpty {
                    Text(background)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Text("Click to edit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedBackground: String {
        if let bg = character.background?.trimmingCharacters(in: .whitespacesAndNewlines), !bg.isEmpty {
            return bg
        }
        return Self.extractLegacyBackground(from: character.notes) ?? ""
    }

    static func extractLegacyBackground(from notes: String) -> String? {
        let plain = ChummerParsingHelpers.cleanRichText(notes)
        guard let range = plain.range(of: "Background", options: [.caseInsensitive, .anchored])
                ?? plain.range(of: "\nBackground\n", options: .caseInsensitive)
                ?? plain.range(of: "Background\n", options: .caseInsensitive)
        else {
            return nil
        }
        var rest = String(plain[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("\n") { rest = String(rest.dropFirst()) }
        let cutMarkers = ["\nImported from Chummer", "\nPlayer:", "\nSRM ", "\nMale,", "\nFemale,"]
        var end = rest.endIndex
        for marker in cutMarkers {
            if let r = rest.range(of: marker) {
                end = min(end, r.lowerBound)
            }
        }
        let extracted = String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }
}
