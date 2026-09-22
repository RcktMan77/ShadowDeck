import SwiftUI

extension GenerationWizardView {
    var finishStep: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                Group {
                    if let data = draft.avatarData, let img = NSImage(data: data) {
                        PaintedPortraitView(kind: .custom, customImage: img, showLabel: false)
                    } else {
                        PaintedPortraitView(kind: .archetype(draft.archetype), showLabel: true)
                    }
                }
                .frame(width: 220, height: 280)

                AppChromeButton.title(
                    "Choose Portrait…",
                    help: "Choose a custom portrait image"
                ) {
                    pickAvatar()
                }
                if draft.avatarData != nil {
                    AppChromeButton.title(
                        "Use Role Art Instead",
                        help: "Clear the custom portrait and use role art",
                        style: .destructive
                    ) {
                        draft.avatarData = nil
                    }
                }
                if let avatarImportError {
                    Text(avatarImportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Optional. Your upload replaces the role portrait in the library and on this summary.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Finishing Touches")
                    .font(.title3.weight(.semibold))

                TextField("Legal / real name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Street name", text: $draft.streetName)
                    .textFieldStyle(.roundedBorder)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Edition", value: draft.edition.rawValue)
                        LabeledContent("Metatype", value: draft.metatype.displayName)
                        LabeledContent("Role", value: draft.archetype.displayName)
                        LabeledContent("Path", value: draft.awakened == .mundane ? ChargenHelpCatalog.mundanePathLabel : draft.awakened.displayName)
                        LabeledContent("Concept", value: draft.concept.isEmpty ? "—" : draft.concept)
                        if draft.generationSystem == .buildPoints {
                            let ledger = draft.buildPointLedger
                            LabeledContent("Build Points", value: "\(ledger.total) spent / \(draft.budget.buildPointsTotal) budget")
                            LabeledContent("BP remaining", value: "\(draft.budget.buildPointsRemaining)")
                            ForEach(ledger.lines.filter { $0.bp != 0 }, id: \.label) { line in
                                LabeledContent("  \(line.label)", value: "\(line.bp) BP")
                            }
                            if draft.isBuildPointsOverBudget {
                                Text("Cannot save while over BP budget.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            LabeledContent("Attributes spent", value: "\(draft.budget.attributePointsSpent) / \(draft.budget.attributePointsTotal)")
                            LabeledContent("Skills spent", value: "\(draft.budget.skillPointsSpent) / \(draft.budget.skillPointsTotal)")
                        }
                        LabeledContent("Nuyen", value: "¥\(draft.nuyen)")
                        LabeledContent("Karma", value: "\(draft.budget.karmaRemaining) avail / \(draft.budget.karmaTotal) total")
                        LabeledContent("Qualities", value: "\(draft.qualities.count)")
                        LabeledContent(
                            "House rules",
                            value: draft.houseRules.enabled.isEmpty
                                ? "Core book"
                                : "\(draft.houseRules.enabled.count) active"
                        )
                        if draft.freeKnowledgePool > 0 {
                            LabeledContent("Free knowledge", value: "\(draft.freeKnowledgePool) ranks")
                        }
                        if draft.generationSystem == .buildPoints {
                            LabeledContent(
                                "Contacts",
                                value: draft.contacts.isEmpty
                                    ? "None"
                                    : "\(draft.contacts.count) · \(draft.buildPointLedger.contacts) BP"
                            )
                        }
                    }
                } label: {
                    Text("Summary")
                        .font(.title3.weight(.semibold))
                }

                if didFinish {
                    Label("Character saved to library.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
