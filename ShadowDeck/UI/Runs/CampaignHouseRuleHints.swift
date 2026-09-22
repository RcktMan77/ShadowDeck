//
//  CampaignsListView.swift
//  ShadowDeck
//
//  Campaign library list + campaign detail (runs under a campaign).
//

import SwiftUI
// MARK: - House-rule hints catalog + codec

/// Catalog of house-rule reminder labels (app-supported chargen rules + common dice notes).
enum CampaignHouseRuleHintCatalog {
    /// Chargen / table toggles ShadowDeck already models.
    static var houseRuleLabels: [String] {
        HouseRuleID.allCases.map(\.displayName)
    }

    /// Dice notes GMs often want on a campaign card (not full DiceHouseRules config).
    static let diceLabels: [String] = [
        "Hits on 4+",
        "Rule of Six always",
        "Glitch: half or more ones",
        "Glitch: more than half ones"
    ]

    static var allLabels: [String] {
        houseRuleLabels + diceLabels
    }

    static func summary(for label: String) -> String {
        if let rule = HouseRuleID.allCases.first(where: { $0.displayName == label }) {
            return rule.summary
        }
        switch label {
        case "Hits on 4+":
            return "Hits count on 4–6 instead of 5–6."
        case "Rule of Six always":
            return "Every 6 explodes on every test (not only with Edge)."
        case "Glitch: half or more ones":
            return "Glitch when ones ≥ half the pool (SR4-style / common table)."
        case "Glitch: more than half ones":
            return "Glitch when ones > half the pool (SR5 core-style)."
        default:
            return ""
        }
    }
}

/// Persist selected catalog labels + free text in `Campaign.houseRuleHints`.
enum CampaignHouseRuleHintsCodec {
    private static let freeTextSeparator = "\n---\n"

    static func encode(selectedLabels: [String], freeText: String) -> String {
        let labels = selectedLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let free = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if labels.isEmpty { return free }
        let head = labels.joined(separator: " · ")
        if free.isEmpty { return head }
        return head + freeTextSeparator + free
    }

    static func decode(_ stored: String) -> (selectedLabels: [String], freeText: String) {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], "") }

        let parts = trimmed.components(separatedBy: freeTextSeparator)
        let catalog = Set(CampaignHouseRuleHintCatalog.allLabels)
        let head = parts[0]
        var free = parts
            .dropFirst()
            .joined(separator: freeTextSeparator)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split head on " · " into catalog hits vs leftover free text.
        let tokens = head.components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var selected: [String] = []
        var leftovers: [String] = []
        for token in tokens {
            if catalog.contains(token) {
                if !selected.contains(token) { selected.append(token) }
            } else {
                leftovers.append(token)
            }
        }
        if !leftovers.isEmpty {
            let joined = leftovers.joined(separator: " · ")
            free = free.isEmpty ? joined : joined + "\n" + free
        }
        // Legacy payloads with no separator: entire string free text if no catalog hits.
        if selected.isEmpty, free.isEmpty, !head.isEmpty {
            free = head
        }
        return (selected, free)
    }
}

/// Simple wrapping chip row (no FlowLayout dependency).
struct FlowHouseRuleChips: View {
    let labels: [String]
    var onRemove: (String) -> Void

    var body: some View {
        // LazyVGrid keeps chips readable without a custom flow layout.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(labels, id: \.self) { label in
                HStack(spacing: 4) {
                    Text(label)
                        .font(.caption)
                        .lineLimit(1)
                    Button {
                        onRemove(label)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(label)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

/// Multi-select supported house-rule reminders (like Add from Run Library).
struct HouseRuleHintsPickerSheet: View {
    @Binding var selectedLabels: [String]
    var onDone: () -> Void

    @State private var draft: Set<String> = []
    @State private var query = ""

    private var filteredHouseRules: [HouseRuleID] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = HouseRuleID.allCases
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.displayName.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
        }
    }

    private var filteredDice: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return CampaignHouseRuleHintCatalog.diceLabels }
        return CampaignHouseRuleHintCatalog.diceLabels.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("House-rule hints")
                        .font(.headline)
                    Text("Select reminders for this campaign. Free-text notes stay on the campaign form.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    onDone()
                }
                Button("Apply") {
                    selectedLabels = CampaignHouseRuleHintCatalog.allLabels.filter { draft.contains($0) }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search rules…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding()

            List {
                Section("Chargen & table (ShadowDeck)") {
                    ForEach(filteredHouseRules, id: \.self) { rule in
                        Toggle(isOn: binding(for: rule.displayName)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.displayName)
                                Text(rule.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                Section("Dice notes") {
                    ForEach(filteredDice, id: \.self) { label in
                        Toggle(isOn: binding(for: label)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label)
                                Text(CampaignHouseRuleHintCatalog.summary(for: label))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 480, minHeight: 480)
        .onAppear {
            draft = Set(selectedLabels)
        }
    }

    private func binding(for label: String) -> Binding<Bool> {
        Binding(
            get: { draft.contains(label) },
            set: { on in
                if on { draft.insert(label) } else { draft.remove(label) }
            }
        )
    }
}
