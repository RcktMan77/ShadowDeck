//
//  DiceRollerPanel.swift
//  ShadowDeck
//
//  Trailing inspector panel for edition-aware dice rolls.
//

import SwiftUI

struct DiceRollerPanel: View {
    @ObservedObject var controller: DiceRollerController
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceSection
                    diceRulesBanner
                    poolSection
                    edgePreRollSection
                    rollButton
                    if let result = controller.lastResult {
                        resultSection(result)
                        secondChanceSection
                    }
                    historySection
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "dice.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dice Roller")
                    .font(.headline)
                Text(controller.edition.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                var ctx = RulesReferenceSession.shared.controller.calcContext
                ctx.edition = controller.edition
                ctx.diceRules = controller.diceRules
                // Approximate skill+attr pool for glitch calculator prefill.
                if controller.effectivePool > 0 {
                    ctx.sampleSkillRating = max(0, controller.effectivePool - ctx.agility)
                }
                RulesReferenceOpener.request(query: "dice", edition: controller.edition)
                RulesReferenceSession.shared.controller.calcContext = ctx
            } label: {
                Label("Look up", systemImage: "book.pages")
            }
            .controlSize(.small)
            .help("Open Rules Reference for hits, glitches, Edge, and house rules")
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Source / pool

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(controller.sourceLabel.isEmpty ? "Manual" : controller.sourceLabel)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var diceRulesBanner: some View {
        let lines = controller.diceRules.activeSummaryLines
        let glitch = controller.diceRules.resolvedGlitchThreshold(for: controller.edition)
        VStack(alignment: .leading, spacing: 4) {
            Text("Dice rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Glitch: \(glitch.displayName) · Hits on \(controller.diceRules.hitMinimum)+")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !lines.isEmpty {
                Text(lines.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
        .help("From this character’s House Rules. Change them on the sheet’s House Rules browser.")
    }

    private var pushTheLimitSubtitle: String {
        if controller.diceRules.ruleOfSix == .always {
            return "Spend 1 Edge · +\(controller.edgeRating) dice (6s already explode)"
        }
        return "Spend 1 Edge · +\(controller.edgeRating) dice · Rule of Six"
    }

    private var nextRollExplodeCaption: String {
        if controller.ruleOfSixActiveForNextRoll {
            return "Will roll \(controller.effectivePool) dice (6s explode)."
        }
        return "Will roll \(controller.effectivePool) dice."
    }

    private var poolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pool")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Effective \(controller.effectivePool)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Stepper(value: $controller.pool, in: 0...40) {
                    TextField("Pool", value: $controller.pool, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                }
                Text("±")
                    .foregroundStyle(.secondary)
                TextField("Mod", value: $controller.modifier, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .help("Situational modifier applied before the roll")
            }
        }
    }

    // MARK: - Pre-roll Edge (Push the Limit)

    private var edgePreRollSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.edgeRemaining) / \(controller.edgeRating) remaining")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Visually distinct card for pre-roll spend
            VStack(alignment: .leading, spacing: 6) {
                Text("Before the roll")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Toggle(isOn: $controller.pushTheLimit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push the Limit")
                            .font(.body.weight(.medium))
                        Text(pushTheLimitSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!controller.canPushTheLimit)
                if controller.pushTheLimit || controller.diceRules.ruleOfSix == .always {
                    Text(nextRollExplodeCaption)
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
            }

            Button("Refresh Edge") {
                controller.refreshEdge()
            }
            .controlSize(.small)
            .help("Restore session Edge to the character’s Edge rating")
        }
    }

    private var rollButton: some View {
        Button {
            controller.roll()
        } label: {
            Text("Roll")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Result

    private func resultSection(_ result: DiceResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(result.hits)")
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                Text(result.hits == 1 ? "hit" : "hits")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    controller.copyLastResult()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                if result.criticalGlitch {
                    outcomeChip("Critical glitch", tone: .critical)
                } else if result.glitch {
                    outcomeChip("Glitch", tone: .warning)
                } else {
                    outcomeChip("Clean", tone: .ok)
                }
                if result.edgeMode != .none {
                    outcomeChip(result.edgeMode.displayName, tone: .neutral)
                }
            }

            // Individual dice (default visible)
            diceFaceRow(result.dice)

            Text(result.copyText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func diceFaceRow(_ dice: [Int]) -> some View {
        Group {
            if dice.isEmpty {
                Text("No dice rolled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(Array(dice.enumerated()), id: \.offset) { _, face in
                        Text("\(face)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 22, height: 22)
                            .background(
                                faceBackground(face),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                            .foregroundStyle(faceForeground(face))
                    }
                }
            }
        }
    }

    private func faceBackground(_ face: Int) -> Color {
        if face >= 5 { return Color.accentColor.opacity(0.2) }
        if face == 1 { return Color.orange.opacity(0.18) }
        return Color.secondary.opacity(0.12)
    }

    private func faceForeground(_ face: Int) -> Color {
        if face >= 5 { return .accentColor }
        if face == 1 { return .orange }
        return .primary
    }

    // MARK: - Post-roll Edge (Second Chance)

    @ViewBuilder
    private var secondChanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("After the roll")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Second Chance")
                    .font(.body.weight(.medium))
                Text("Spend 1 Edge to re-roll all non-hits. Preview before committing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let preview = controller.secondChancePreview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview: \(preview.hits) hit\(preview.hits == 1 ? "" : "s")")
                            .font(.callout.weight(.semibold))
                        if preview.criticalGlitch {
                            outcomeChip("Critical glitch", tone: .critical)
                        } else if preview.glitch {
                            outcomeChip("Glitch", tone: .warning)
                        }
                        diceFaceRow(preview.dice)
                        HStack {
                            Button("Cancel") {
                                controller.cancelSecondChancePreview()
                            }
                            .controlSize(.small)
                            Button("Commit Edge") {
                                controller.commitSecondChance()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Button("Preview Second Chance…") {
                        controller.previewSecondChance()
                    }
                    .controlSize(.small)
                    .disabled(!controller.canSecondChance)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent (session)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if controller.history.isEmpty {
                Text("No rolls yet this session.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(controller.history) { item in
                    Button {
                        controller.loadFromHistory(item)
                    } label: {
                        HStack {
                            Text(item.sourceLabel ?? "Roll")
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.hits)h")
                                .font(.caption.monospacedDigit().weight(.semibold))
                            if item.criticalGlitch {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(.red)
                                    .imageScale(.small)
                            } else if item.glitch {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .imageScale(.small)
                            }
                        }
                        .font(.caption)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chips

    private enum ChipTone {
        case ok, warning, critical, neutral
    }

    private func outcomeChip(_ title: String, tone: ChipTone) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(chipBackground(tone), in: Capsule())
            .foregroundStyle(chipForeground(tone))
    }

    private func chipBackground(_ tone: ChipTone) -> Color {
        switch tone {
        case .ok: Color.green.opacity(0.16)
        case .warning: Color.orange.opacity(0.18)
        case .critical: Color.red.opacity(0.18)
        case .neutral: Color.secondary.opacity(0.14)
        }
    }

    private func chipForeground(_ tone: ChipTone) -> Color {
        switch tone {
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        case .neutral: .secondary
        }
    }
}
