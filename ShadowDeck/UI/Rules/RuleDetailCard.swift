//
//  RuleDetailCard.swift
//  ShadowDeck
//
//  Detail pane for a structured rules reference entry.
//

import SwiftUI

struct RuleDetailCard: View {
    let entry: RuleEntry
    /// Edition for calculators (character context or default SR5).
    var edition: Edition = .sr5
    var houseRules: HouseRules = .coreBook
    var diceRules: DiceHouseRules = .coreBook
    /// Optional character snapshot for calculator prefills.
    var calcContext: RulesCalcContext = .neutral
    /// Prefer this edition’s page chip first (open character).
    var preferPageEdition: Edition? = nil
    /// Resolve related entry titles (id → title).
    var relatedTitle: ((String) -> String?)? = nil
    /// When set, page chips jump into the bound PDF (if present).
    var onPageRefTap: ((PageRef) -> Void)?
    /// Whether a book key is bound to a library PDF.
    var bookKeyIsBound: ((String) -> Bool)?
    /// Tap a related card id.
    var onRelatedTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryBlock
            if let formula = entry.formula, !formula.isEmpty {
                formulaBlock(formula)
            }
            if let calc = entry.calculator {
                RulesCalculatorHost(
                    calculator: calc,
                    edition: edition,
                    houseRules: houseRules,
                    diceRules: diceRules,
                    calcContext: calcContext
                )
            }
            if !entry.pageRefs.isEmpty {
                pageRefsBlock
            }
            if !entry.relatedIDs.isEmpty {
                relatedBlock
            }
            footerNote
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                categoryChip
                if entry.appliesToAllEditions {
                    Text("All editions")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.editions, id: \.self) { ed in
                        Text(ed.shortName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
            }
            if !entry.tags.isEmpty {
                Text(entry.tags.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }

    private var categoryChip: some View {
        Text(entry.category.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formulaBlock(_ formula: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Formula")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formula)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var pageRefsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Page references")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowPageRefChips(
                refs: entry.pageRefsForDisplay(preferEdition: preferPageEdition),
                onTap: onPageRefTap,
                isBound: bookKeyIsBound
            )
        }
    }

    private var relatedBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Related")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.relatedIDs, id: \.self) { relatedID in
                    let title = relatedTitle?(relatedID) ?? relatedID
                    if let onRelatedTap {
                        Button {
                            onRelatedTap(relatedID)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.tint)
                                Text(title)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Open related card: \(relatedID)")
                    } else {
                        Text(title)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var footerNote: some View {
        Text("Original concise aid for table play — not a substitute for your core books.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

// MARK: - Page ref chips

/// Full-label chips (no mid-word truncation). Stacks vertically so long titles stay readable
/// in a narrow Rules detail column.
private struct FlowPageRefChips: View {
    let refs: [PageRef]
    var onTap: ((PageRef) -> Void)?
    var isBound: ((String) -> Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(refs) { ref in
                let bound = isBound?(ref.bookKey) ?? false
                Button {
                    onTap?(ref)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: bound ? "book.closed.fill" : "book.closed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bound ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ref.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(bound ? Color.accentColor : Color.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(ref.bookKey) · p. \(ref.page)\(bound ? "  ·  Open →" : "  ·  bind PDF in Library")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (bound ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .help(
                    bound
                        ? "Open in Library → \(ref.bookKey) p.\(ref.page)"
                        : "\(ref.bookKey) p.\(ref.page) — bind a PDF in Library mode first"
                )
                .disabled(onTap == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
