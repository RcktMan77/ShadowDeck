import SwiftUI

extension GenerationWizardView {
    var prioritiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if draft.generationSystem == .buildPoints {
                Text("Build Points overview")
                    .font(.title3.weight(.semibold))
                Text("You do not assign BP here — later steps spend it. This page is your live ledger.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                buildPointsOverview
            } else {
                Text("Priorities")
                    .font(.title3.weight(.semibold))
                HelpCallout(text: {
                    if draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen) {
                        return """
                            Assign priority letters so their values sum to 10 (A=4, B=3, C=2, D=1, E=0). \
                            Duplicates are allowed. Watch the balance banner above as you click.
                            """
                    }
                    return """
                        Assign each of A–E exactly once across the five columns. \
                        The balance banner above updates as you choose.
                        """
                }())

                RecommendButton(
                    title: "Apply Recommended Priorities",
                    subtitle: ChargenRecommendations.priorities(archetype: draft.archetype, metatype: draft.metatype).rationale
                ) {
                    draft.applyRecommendedPriorities()
                }

                ForEach(PriorityColumn.allCases, id: \.self) { column in
                    priorityRow(column)
                }
            }
        }
    }

    /// Live SR4A BP category breakdown (real accounting — not placeholder pools).
    var buildPointsOverview: some View {
        let ledger = draft.buildPointLedger
        let remaining = draft.budget.buildPointsRemaining
        let total = draft.budget.buildPointsTotal
        let rows: [(label: String, rate: String, bp: Int)] = [
            ("Metatype", "Fixed cost (Human 0 · Ork 20 · Dwarf 25 · Elf 30 · Troll 40)", ledger.metatype),
            ("Attributes", "10 BP per point above racial/path min (incl. Edge, Magic, Resonance)", ledger.attributes),
            ("Skills", "4 BP per active rank · 2 BP per knowledge/language rank", ledger.skills),
            ("Skill groups", "10 BP per rating (max 4 at chargen)", ledger.skillGroups),
            ("Spells", "3 BP each (max 2× higher of Spellcasting / Ritual Spellcasting)", ledger.spells),
            ("Contacts", "Connection + Loyalty (each 1–6)", ledger.contacts),
            ("Qualities", "Positive cost BP · negative refund · ±35 BP caps", ledger.qualities),
            ("Resources", "1 BP = ¥5,000 starting nuyen", ledger.resources)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            // Compact wallet strip (no multi-line cost essay).
            HStack(spacing: 20) {
                bpWalletStat(title: "Budget", value: "\(total) BP")
                bpWalletStat(title: "Spent", value: "\(ledger.total) BP")
                bpWalletStat(
                    title: "Remaining",
                    value: "\(remaining) BP",
                    valueColor: remaining < 0 ? .red : .primary
                )
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if remaining < 0 {
                Text("Over budget — reduce spends on later steps before finishing.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox {
                VStack(spacing: 0) {
                    // Column headers
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Category")
                            .frame(width: 110, alignment: .leading)
                        Text("How you spend")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Spent")
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                    Divider()

                    ForEach(rows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label)
                                .font(.body.weight(.medium))
                                .frame(width: 110, alignment: .leading)
                            Text(row.rate)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(row.bp) BP")
                                .font(.body.monospacedDigit().weight(row.bp > 0 ? .semibold : .regular))
                                .foregroundStyle(row.bp > 0 ? Color.primary : Color.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        if row.label != rows.last?.label {
                            Divider()
                        }
                    }
                }
            } label: {
                Text("Category ledger")
                    .font(.headline)
            }

            Text("""
                Continue to spend on later steps; this ledger updates live. Metatype is already applied. \
                Out of wizard scope: complex forms as full BP UI, initiate grades, and gear shopping \
                (buy nuyen with BP, then equip on the sheet).
                """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func bpWalletStat(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }

    func priorityRow(_ column: PriorityColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.displayName)
                .font(.title3.weight(.semibold))
            Text(ChargenHelpCatalog.priorityColumnDescription(column))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(PriorityLetter.allCases, id: \.self) { letter in
                    let selected = draft.priority[column] == letter
                    let summary = PrioritySummaryBuilder.summaries(
                        for: draft.edition,
                        metatype: draft.metatype,
                        rules: draft.rules
                    )
                    .first { $0.column == column && $0.letter == letter }

                    Button {
                        draft.assignPriority(letter, to: column)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(letter.rawValue)
                                .font(.title2.weight(.bold))
                            if let summary {
                                ForEach(summary.detailLines.prefix(3), id: \.self) { line in
                                    Text(line)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(summary?.detailLines.joined(separator: "\n") ?? letter.rawValue)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Attributes

}
