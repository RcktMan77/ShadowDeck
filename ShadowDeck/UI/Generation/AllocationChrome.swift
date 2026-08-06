//
//  AllocationChrome.swift
//  ShadowDeck
//
//  Live budget counters and steppers that grey out when empty/maxed.
//

import SwiftUI

struct AllocationCounterBar: View {
    let draft: GenerationDraft

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if draft.generationSystem == .buildPoints {
                    // Real SR4 BP: single pool + cash bought with BP. No fake Attr/Skill pools.
                    chip(
                        "BP",
                        remaining: draft.budget.buildPointsRemaining,
                        total: draft.budget.buildPointsTotal,
                        emphasizeOverspend: true
                    )
                    chip("Cash", remaining: draft.nuyen, total: max(draft.nuyen, 1), isCurrency: true)
                    // Contacts in BP mode cost Connection+Loyalty BP (no free CHA×3 pool).
                    // Show count + BP spent so the chip tracks adds; do not show a fake "3 free" pool.
                    let contactBP = draft.buildPointLedger.contacts
                    valueChip(
                        "Contacts",
                        value: draft.contacts.isEmpty
                            ? "0 · 0 BP"
                            : "\(draft.contacts.count) · \(contactBP) BP"
                    )
                    if draft.budget.karmaTotal > 0 {
                        chip("Karma", remaining: draft.budget.karmaRemaining, total: draft.budget.karmaTotal)
                    }
                } else {
                    chip("Attributes", remaining: draft.budget.attributePointsRemaining, total: draft.budget.attributePointsTotal)
                    if draft.budget.specialPointsTotal > 0 {
                        chip("Special", remaining: draft.budget.specialPointsRemaining, total: draft.budget.specialPointsTotal)
                    }
                    chip("Skills", remaining: draft.budget.skillPointsRemaining, total: draft.budget.skillPointsTotal)
                    if draft.budget.skillGroupPointsTotal > 0 {
                        chip("Groups", remaining: draft.budget.skillGroupPointsRemaining, total: draft.budget.skillGroupPointsTotal)
                    }
                    // Priority: cash is always the full Resources grant (wizard does not underspend).
                    chip(
                        "Cash",
                        remaining: draft.nuyen,
                        total: max(draft.budget.nuyenTotal, draft.nuyen, 1),
                        isCurrency: true
                    )
                    chip("Karma", remaining: draft.budget.karmaRemaining, total: draft.budget.karmaTotal)
                    // No Contacts chip for priority (SR5/SR6): the wizard does not buy contacts
                    // during chargen. Free CHA×3 contact points are a book rule for post-gen /
                    // future UI, not a live allocation counter here.
                }
                if draft.freeKnowledgePool > 0 {
                    chip("Knowledge", remaining: draft.freeKnowledgePool, total: draft.freeKnowledgePool)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(
        _ title: String,
        remaining: Int,
        total: Int,
        isCurrency: Bool = false,
        emphasizeOverspend: Bool = false
    ) -> some View {
        let overspent = emphasizeOverspend && remaining < 0
        let exhausted = remaining <= 0 && total > 0 && !overspent
        let valueText: String = {
            if isCurrency {
                // remaining = cash on hand; total = grant/max when it differs (priority Resources).
                if total > remaining {
                    return "¥\(remaining.formatted()) / \(total.formatted())"
                }
                return "¥\(remaining.formatted())"
            }
            return "\(remaining) left · \(total)"
        }()
        return chipChrome(
            title: title,
            valueText: valueText,
            overspent: overspent,
            exhausted: exhausted,
            dimmed: total == 0 && !overspent
        )
    }

    /// Freeform value chip (e.g. SR4 "2 · 14 BP" for contacts).
    private func valueChip(_ title: String, value: String) -> some View {
        chipChrome(title: title, valueText: value, overspent: false, exhausted: false, dimmed: false)
    }

    private func chipChrome(
        title: String,
        valueText: String,
        overspent: Bool,
        exhausted: Bool,
        dimmed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(overspent ? Color.red : (exhausted ? Color.secondary : Color.primary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    overspent
                        ? Color.red.opacity(0.12)
                        : (exhausted ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.12))
                )
        )
        .opacity(dimmed ? 0.45 : 1)
    }
}

struct PointStepperRow: View {
    let title: String
    let value: Int
    let subtitle: String?
    let canIncrease: Bool
    let canDecrease: Bool
    let onIncrease: () -> Void
    let onDecrease: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    onDecrease()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!canDecrease)
                .opacity(canDecrease ? 1 : 0.35)

                Text("\(value)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 28)

                Button {
                    onIncrease()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!canIncrease)
                .opacity(canIncrease ? 1 : 0.35)
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
    }
}
