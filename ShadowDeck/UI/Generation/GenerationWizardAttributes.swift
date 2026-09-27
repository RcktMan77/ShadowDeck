import SwiftUI

extension GenerationWizardView {
    var attributesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Attributes")
                .font(.title3.weight(.semibold))

            if draft.generationSystem == .buildPoints {
                HelpCallout(text: "Each point above racial/path minimum costs **10 BP**. **Edge**, **Magic**, and **Resonance** use the same rate.")
            }

            RecommendButton(
                title: "Apply Recommended Attributes",
                subtitle: {
                    ChargenRecommendations.attributes(
                        archetype: draft.archetype,
                        metatype: draft.metatype,
                        edition: draft.edition,
                        pointBudget: draft.recommendedAttributePointBudget
                    ).rationale
                }()
            ) {
                draft.applyRecommendedAttributes()
            }

            sectionCard(title: "Physical & Mental") {
                ForEach(AttributeID.standardGenerationAttributes, id: \.self) { id in
                    attributeRow(id)
                }
            }

            // BP mode always exposes Edge; Magic/Resonance when path requires. Priority mode uses special pool.
            if draft.generationSystem == .buildPoints
                || draft.budget.specialPointsTotal > 0
                || draft.awakened != .mundane {
                sectionCard(title: "Special (Edge, Magic, Resonance)") {
                    if draft.generationSystem != .buildPoints {
                        Text(ChargenHelpCatalog.specialAdjustmentPointsHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Edge starts at metatype minimum. Raising Edge, Magic, or Resonance costs 10 BP per point.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let specialIDs: [AttributeID] = {
                        var ids: [AttributeID] = [.edge]
                        if draft.awakened.usesMagic { ids.append(.magic) }
                        if draft.awakened.usesResonance { ids.append(.resonance) }
                        return ids
                    }()
                    ForEach(specialIDs, id: \.self) { id in
                        attributeRow(id)
                    }
                }
            }
        }
    }

    func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.bottom, 2)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.04))
                )
        )
    }

    func attributeRow(_ id: AttributeID) -> some View {
        let bounds = MetatypeCatalog.profile(for: draft.metatype, edition: draft.edition).bounds(for: id)
        return VStack(alignment: .leading, spacing: 6) {
            PointStepperRow(
                title: id.displayName,
                value: draft.attributes[id],
                subtitle: "Natural range \(bounds.minimum)–\(bounds.maximum) · \(ChargenHelpCatalog.attributeInfluences(id))",
                canIncrease: draft.canIncreaseAttribute(id),
                canDecrease: draft.canDecreaseAttribute(id),
                onIncrease: { draft.increaseAttribute(id) },
                onDecrease: { draft.decreaseAttribute(id) }
            )
            Text(ChargenHelpCatalog.attributeDescription(id))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
        }
    }

    // MARK: - Magic

}
