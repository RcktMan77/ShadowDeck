//
//  HouseRulesBrowserView.swift
//  ShadowDeck
//
//  Searchable multi-select house-rules catalog for chargen (and later play).
//  Design: individual rules stack; presets only seed the set. Karma-gen and
//  Sum-to-Ten are mutually exclusive.
//

import SwiftUI

struct HouseRulesBrowserView: View {
    @Binding var houseRules: HouseRules
    var editionBaselineKarma: Int
    var onApply: () -> Void
    var onCancel: () -> Void

    @State private var query = ""

    private var filtered: [HouseRuleID] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = HouseRuleID.allCases
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.displayName.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.detailDescription.lowercased().contains(q)
                || $0.categoryLabel.lowercased().contains(q)
        }
    }

    private var grouped: [(String, [HouseRuleID])] {
        let cats = Dictionary(grouping: filtered, by: \.categoryLabel)
        return cats.keys.sorted().map { ($0, cats[$0]!.sorted { $0.displayName < $1.displayName }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("House Rules")
                        .font(.title2.weight(.semibold))
                    Text("Select any combination. Presets fill a starting set—you can still tweak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
            }

            // Presets
            HStack(spacing: 8) {
                presetButton("Core Book", rules: .coreBook)
                presetButton("Popular Table", rules: .popularTable)
                presetButton("Prime Runner", rules: .primeRunner)
                Spacer()
                Text("\(houseRules.enabled.count) active")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search rules…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            List {
                ForEach(grouped, id: \.0) { category, rules in
                    Section(category) {
                        ForEach(rules, id: \.self) { rule in
                            ruleRow(rule)
                        }
                    }
                }

                Section("Dice & tests") {
                    diceRulesSection
                }

                if !houseRules.enabled.isEmpty {
                    Section("Live effects") {
                        ForEach(
                            HouseRulesEngine.effectSummary(
                                for: houseRules,
                                editionBaselineKarma: editionBaselineKarma
                            ),
                            id: \.self
                        ) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)

            // Parameters for enabled rules that need numbers
            if needsParameters {
                GroupBox("Rule parameters") {
                    VStack(alignment: .leading, spacing: 10) {
                        if houseRules.isEnabled(.bonusStartingKarma)
                            || houseRules.isEnabled(.primeRunnerPackage)
                        {
                            HStack {
                                Text("Bonus starting karma")
                                Spacer()
                                StepperControl(value: houseRules.bonusKarma, range: 0...200) {
                                    houseRules.bonusKarma = $0
                                }
                            }
                        }
                        if houseRules.isEnabled(.freeKnowledgeSkills) {
                            HStack {
                                Text("Free knowledge points (0 = auto LOG+INT×2)")
                                Spacer()
                                StepperControl(value: houseRules.freeKnowledgePoints, range: 0...40) {
                                    houseRules.freeKnowledgePoints = $0
                                }
                            }
                        }
                        if houseRules.isEnabled(.expandedContacts)
                            || houseRules.isEnabled(.primeRunnerPackage)
                        {
                            HStack {
                                Text("Extra contact points")
                                Spacer()
                                StepperControl(value: houseRules.extraContactPoints, range: 0...20) {
                                    houseRules.extraContactPoints = $0
                                }
                            }
                        }
                        if houseRules.isEnabled(.qualityBudgetAdjustment)
                            || houseRules.isEnabled(.primeRunnerPackage)
                        {
                            HStack {
                                Text("Positive quality karma cap")
                                Spacer()
                                StepperControl(
                                    value: houseRules.positiveQualityKarmaCap ?? 35,
                                    range: 15...60
                                ) {
                                    houseRules.positiveQualityKarmaCap = $0
                                }
                            }
                        }
                        if houseRules.isEnabled(.karmaGeneration) {
                            HStack {
                                Text("Karma-gen budget")
                                Spacer()
                                StepperControl(value: houseRules.karmaGenBudget, range: 400...1200) {
                                    houseRules.karmaGenBudget = $0
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Spacer()
                Button("Apply House Rules") {
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 560)
    }

    private var needsParameters: Bool {
        houseRules.isEnabled(.bonusStartingKarma)
            || houseRules.isEnabled(.primeRunnerPackage)
            || houseRules.isEnabled(.freeKnowledgeSkills)
            || houseRules.isEnabled(.expandedContacts)
            || houseRules.isEnabled(.qualityBudgetAdjustment)
            || houseRules.isEnabled(.karmaGeneration)
    }

    private func presetButton(_ title: String, rules: HouseRules) -> some View {
        Button(title) {
            houseRules = rules
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var diceRulesSection: some View {
        let diceBinding = Binding(
            get: { houseRules.dice ?? .coreBook },
            set: { houseRules.dice = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            Text("Applied by the character-sheet dice roller. Core Book uses edition defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Glitch threshold", selection: Binding(
                get: { diceBinding.wrappedValue.glitchThreshold },
                set: { v in
                    var d = diceBinding.wrappedValue
                    d.glitchThreshold = v
                    diceBinding.wrappedValue = d
                }
            )) {
                ForEach(DiceGlitchThresholdMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text(diceBinding.wrappedValue.glitchThreshold.summary)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Picker("Rule of Six", selection: Binding(
                get: { diceBinding.wrappedValue.ruleOfSix },
                set: { v in
                    var d = diceBinding.wrappedValue
                    d.ruleOfSix = v
                    diceBinding.wrappedValue = d
                }
            )) {
                ForEach(DiceRuleOfSixMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text(diceBinding.wrappedValue.ruleOfSix.summary)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Toggle(isOn: Binding(
                get: { diceBinding.wrappedValue.countExplodedDiceForGlitch },
                set: { v in
                    var d = diceBinding.wrappedValue
                    d.countExplodedDiceForGlitch = v
                    diceBinding.wrappedValue = d
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count exploded dice for glitch")
                    Text("Off = only the original pool size is used for the glitch check.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { diceBinding.wrappedValue.hitsOn4 },
                set: { v in
                    var d = diceBinding.wrappedValue
                    d.hitsOn4 = v
                    diceBinding.wrappedValue = d
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hits on 4+")
                    Text("4, 5, and 6 count as hits. Ones still trigger glitches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { diceBinding.wrappedValue.simplifiedSR6Edge },
                set: { v in
                    var d = diceBinding.wrappedValue
                    d.simplifiedSR6Edge = v
                    diceBinding.wrappedValue = d
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simplified SR6 Edge")
                    Text("Push the Limit + Second Chance style (SR5-like). Recommended for SR6 tables.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Button("Reset dice rules to core book") {
                houseRules.dice = .coreBook
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func ruleRow(_ rule: HouseRuleID) -> some View {
        let on = houseRules.isEnabled(rule)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { houseRules.isEnabled(rule) },
                set: { enabled in
                    if enabled {
                        HouseRulesEngine.enabling(rule, into: &houseRules)
                    } else {
                        HouseRulesEngine.disabling(rule, into: &houseRules)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.displayName)
                        .font(.body.weight(.semibold))
                    Text(rule.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if on {
                Text(rule.detailDescription.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rule.mechanicalEffect(houseRules))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}
