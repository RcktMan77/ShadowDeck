import SwiftUI

extension GenerationWizardView {
    var editionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Edition")
                .font(.title3.weight(.semibold))
            HelpCallout(text: """
                ShadowDeck treats 4th, 5th, and 6th edition as equal peers. \
                Generation rules (priority tables, limits, Edge) adapt to your choice.
                """)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(Edition.allCases) { edition in
                    editionCard(edition)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("House Rules")
                            .font(.headline)
                        Text(houseRulesSummaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    AppChromeButton.title(
                        "Configure…",
                        help: "Open the house rules catalog",
                        style: .prominent
                    ) {
                        showHouseRulesBrowser = true
                    }
                }

                if !draft.houseRules.enabled.isEmpty {
                    houseRuleChips
                } else {
                    Text("Core book only. Open the catalog to enable Sum-to-Ten, free knowledge, prime runner packages, and more—rules stack.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .sheet(isPresented: $showHouseRulesBrowser) {
            HouseRulesBrowserView(
                houseRules: $draft.houseRules,
                editionBaselineKarma: draft.rules.standardPriorityKarma,
                onApply: {
                    draft.applyHouseRulesSelection()
                    showHouseRulesBrowser = false
                    statusMessage = draft.houseRules.enabled.isEmpty
                        ? "Core book rules."
                        : "House rules applied (\(draft.houseRules.enabled.count) active)."
                },
                onCancel: { showHouseRulesBrowser = false }
            )
        }
    }

    var houseRulesSummaryLine: String {
        if draft.houseRules.enabled.isEmpty {
            return "No house rules — strict core book."
        }
        let names = HouseRuleID.allCases
            .filter { draft.houseRules.isEnabled($0) }
            .map(\.displayName)
        if names.count <= 3 {
            return names.joined(separator: " · ")
        }
        return names.prefix(3).joined(separator: " · ") + " +\(names.count - 3) more"
    }

    var houseRuleChips: some View {
        HStack(spacing: 6) {
            ForEach(
                HouseRuleID.allCases.filter { draft.houseRules.isEnabled($0) },
                id: \.self
            ) { rule in
                Text(rule.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }

    func editionCard(_ edition: Edition) -> some View {
        let selected = draft.edition == edition
        return Button {
            draft.selectEdition(edition)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(edition.shortName).font(.title2.weight(.bold))
                Text(edition.displayName).font(.caption).foregroundStyle(.secondary)
                Text(edition.usesPriorityGenerationByDefault ? "Priority generation" : "Build Points generation")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding()
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Concept

}
