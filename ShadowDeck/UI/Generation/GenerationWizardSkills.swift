import SwiftUI

extension GenerationWizardView {
    var skillsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skills")
                .font(.title3.weight(.semibold))
            if draft.generationSystem == .buildPoints {
                HelpCallout(text: "Active skills cost **4 BP** per rank (max 6 at chargen). Skill groups cost **10 BP** per rating (max 4).")
            } else {
                HelpCallout(text: "Skills plus linked attributes form dice pools. Recommendations match your role; adjust any rank afterward.")
            }
            if draft.freeKnowledgePool > 0 {
                HelpCallout(text: "House rule: \(draft.freeKnowledgePool) free Knowledge/Language ranks (not spent from the active skill pool above). Track them on the Skills tab after creation if needed.")
            }

            RecommendButton(
                title: "Apply Recommended Skills",
                subtitle: {
                    ChargenRecommendations.skills(
                        archetype: draft.archetype,
                        pointBudget: draft.recommendedSkillPointBudget
                    ).rationale
                }()
            ) {
                draft.applyRecommendedSkills()
            }

            if draft.generationSystem == .buildPoints || draft.budget.skillGroupPointsTotal > 0 {
                GroupBox(
                    draft.generationSystem == .buildPoints
                        ? "Skill groups (10 BP × rating, max 4)"
                        : "Skill groups (\(draft.budget.skillGroupPointsTotal) points from Skills priority)"
                ) {
                    Text(
                        draft.generationSystem == .buildPoints
                            ? "Buying a group is cheaper than raising every member skill separately. Groups cannot take specializations at chargen."
                            : "Spend skill-group points 1:1 on group ratings (chargen max 6). The Groups chip tracks remaining points."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    ForEach(SR4BuildPointEngine.chargenSkillGroups, id: \.self) { group in
                        PointStepperRow(
                            title: group.displayName,
                            value: draft.skillGroupRating(group),
                            subtitle: draft.generationSystem == .buildPoints
                                ? "\(SR4BuildPointEngine.skillGroupRankCost) BP per rating"
                                : "1 group point per rating",
                            canIncrease: draft.canIncreaseSkillGroup(group),
                            canDecrease: draft.canDecreaseSkillGroup(group),
                            onIncrease: {
                                draft.setSkillGroupRating(group, rating: draft.skillGroupRating(group) + 1)
                            },
                            onDecrease: {
                                draft.setSkillGroupRating(group, rating: draft.skillGroupRating(group) - 1)
                            }
                        )
                        Divider()
                    }
                    if draft.generationSystem == .buildPoints {
                        LabeledContent("Skill group BP", value: "\(draft.buildPointLedger.skillGroups) BP")
                    } else {
                        LabeledContent(
                            "Group points",
                            value: "\(draft.budget.skillGroupPointsRemaining) left · \(draft.budget.skillGroupPointsTotal)"
                        )
                    }
                }
            }

            GroupBox {
                ForEach(ChargenSkillCatalog.active, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        PointStepperRow(
                            title: item.name,
                            value: draft.skillRanks[item.key] ?? 0,
                            subtitle: nil,
                            canIncrease: draft.canIncreaseSkill(catalogKey: item.key),
                            canDecrease: draft.canDecreaseSkill(catalogKey: item.key),
                            onIncrease: {
                                draft.setSkillRank(
                                    catalogKey: item.key,
                                    displayName: item.name,
                                    rank: (draft.skillRanks[item.key] ?? 0) + 1
                                )
                            },
                            onDecrease: {
                                draft.setSkillRank(
                                    catalogKey: item.key,
                                    displayName: item.name,
                                    rank: (draft.skillRanks[item.key] ?? 0) - 1
                                )
                            }
                        )
                        Text(ChargenHelpCatalog.skillDescription(catalogKey: item.key))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 88) // keep clear of stepper control column
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Qualities

}
