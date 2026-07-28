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
                    chip("BP", remaining: draft.budget.buildPointsRemaining, total: draft.budget.buildPointsTotal)
                }
                chip("Attributes", remaining: draft.budget.attributePointsRemaining, total: draft.budget.attributePointsTotal)
                if draft.budget.specialPointsTotal > 0 {
                    chip("Special", remaining: draft.budget.specialPointsRemaining, total: draft.budget.specialPointsTotal)
                }
                chip("Skills", remaining: draft.budget.skillPointsRemaining, total: draft.budget.skillPointsTotal)
                if draft.budget.skillGroupPointsTotal > 0 {
                    chip("Groups", remaining: draft.budget.skillGroupPointsRemaining, total: draft.budget.skillGroupPointsTotal)
                }
                chip("¥", remaining: draft.budget.nuyenRemaining, total: draft.budget.nuyenTotal, isCurrency: true)
                chip("Karma", remaining: draft.budget.karmaRemaining, total: draft.budget.karmaTotal)
                if draft.freeKnowledgePool > 0 {
                    chip("Knowledge", remaining: draft.freeKnowledgePool, total: draft.freeKnowledgePool)
                }
                if draft.houseRules.isEnabled(.expandedContacts) || draft.contactPointPool > 0 {
                    chip("Contacts", remaining: draft.contactPointPool, total: draft.contactPointPool)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(_ title: String, remaining: Int, total: Int, isCurrency: Bool = false) -> some View {
        let exhausted = remaining <= 0 && total > 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(isCurrency ? "\(remaining) / \(total)" : "\(remaining) left · \(total)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(exhausted ? Color.secondary : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(exhausted ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.12))
        )
        .opacity(total == 0 ? 0.45 : 1)
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
