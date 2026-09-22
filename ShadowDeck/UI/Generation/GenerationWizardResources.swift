import SwiftUI

extension GenerationWizardView {
    var resourcesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resources")
                .font(.title3.weight(.semibold))

            if draft.generationSystem == .buildPoints {
                HelpCallout(text: """
                    Buy starting nuyen with Build Points: **1 BP** equals **¥5,000**. \
                    Use the slider or type a BP amount — better than stepping ¥5,000 at a time when you have a large remainder. \
                    Contacts for SR4 are purchased below (same **400 BP** pool).
                    """)
                sr4NuyenBPControls
                sr4ContactsSection
            } else {
                // Priority Resources: the letter grants a fixed nuyen budget. ShadowDeck does not
                // run gear shopping in this wizard, so there is no benefit to taking less than
                // the full grant — cash is always set to the priority total.
                priorityResourcesSummary
            }
        }
        .onAppear {
            if draft.generationSystem == .buildPoints {
                catalog.ensureLoaded(for: draft.edition)
                syncResourceBPText()
            } else {
                ensurePriorityNuyenIsFullGrant()
            }
        }
        .onChange(of: draft.nuyen) { _, _ in
            if draft.generationSystem == .buildPoints {
                syncResourceBPText()
            }
        }
        .onChange(of: draft.budget.nuyenTotal) { _, _ in
            if draft.generationSystem != .buildPoints {
                ensurePriorityNuyenIsFullGrant()
            }
        }
    }

    /// Max BP that can currently sit in Resources (spent resource BP + free remaining).
    var maxResourceBPAffordable: Int {
        draft.buildPointLedger.resources + max(0, draft.budget.buildPointsRemaining)
    }

    var currentResourceBP: Int {
        SR4BuildPointEngine.resourceCost(nuyen: draft.nuyen)
    }

    func setResourceBP(_ bp: Int) {
        let clamped = max(0, min(bp, maxResourceBPAffordable))
        draft.setNuyenForBuildPoints(SR4BuildPointEngine.nuyenForBuildPoints(clamped))
        syncResourceBPText()
    }

    func syncResourceBPText() {
        resourceBPText = "\(currentResourceBP)"
    }

    var sr4NuyenBPControls: some View {
        let maxBP = max(maxResourceBPAffordable, currentResourceBP)
        return GroupBox("Starting nuyen (Build Points)") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    LabeledContent("Cash on hand", value: "¥\(draft.nuyen.formatted())")
                    Spacer(minLength: 12)
                    LabeledContent("Resource BP", value: "\(currentResourceBP) BP")
                    LabeledContent("Pool remaining", value: "\(draft.budget.buildPointsRemaining) BP")
                }
                .font(.callout)

                // Primary control: BP slider (1 BP steps → ¥5,000).
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spend Build Points on nuyen")
                        .font(.subheadline.weight(.semibold))
                    if maxBP > 0 {
                        Slider(
                            value: Binding(
                                get: { Double(currentResourceBP) },
                                set: { setResourceBP(Int($0.rounded())) }
                            ),
                            in: 0...Double(maxBP),
                            step: 1
                        )
                    } else {
                        Text("No BP available for resources (pool is empty).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("0 BP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(maxBP) BP max · ¥\(SR4BuildPointEngine.nuyenForBuildPoints(maxBP).formatted())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Direct entry + coarse presets for large remainders.
                HStack(spacing: 10) {
                    Text("BP amount")
                        .font(.callout)
                    TextField("0", text: $resourceBPText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onSubmit { commitResourceBPText() }
                    AppChromeButton.title("Apply", help: "Set resource BP from the field") {
                        commitResourceBPText()
                    }
                    Text("= ¥\((Int(resourceBPText) ?? currentResourceBP) * SR4BuildPointEngine.nuyenPerBuildPoint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    resourceBPPresetButton("None", bp: 0)
                    resourceBPPresetButton("+10 BP", bp: currentResourceBP + 10)
                    resourceBPPresetButton("+25 BP", bp: currentResourceBP + 25)
                    resourceBPPresetButton("+50 BP", bp: currentResourceBP + 50)
                    resourceBPPresetButton("Spend all remaining", bp: maxResourceBPAffordable)
                }
            }
        }
    }

    func resourceBPPresetButton(_ title: String, bp: Int) -> some View {
        AppChromeButton.title(title, help: "Set resource spend to \(bp) BP") {
            setResourceBP(bp)
        }
    }

    func commitResourceBPText() {
        let trimmed = resourceBPText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            syncResourceBPText()
            return
        }
        setResourceBP(value)
    }

    // MARK: Priority (SR5/SR6) resources summary

    /// Keep cash on hand equal to the full Resources priority grant (no voluntary underspend).
    func ensurePriorityNuyenIsFullGrant() {
        guard draft.generationSystem != .buildPoints else { return }
        let grant = draft.budget.nuyenTotal
        if draft.nuyen != grant {
            draft.nuyen = grant
        }
        draft.budget.nuyenRemaining = 0
    }

    var priorityResourcesSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpCallout(text: """
                \(ChargenHelpCatalog.resourcesHelp) \
                Your **Resources** priority letter sets starting nuyen (**¥\(draft.budget.nuyenTotal.formatted())**). \
                In the book you’d spend that pool on gear during chargen; leftovers stay as cash. \
                ShadowDeck’s wizard does not run gear shopping here, so you receive the **full grant** as cash — \
                buy gear later on the character sheet. Change the Resources priority letter if you want more or less nuyen.
                """)

            GroupBox("Starting nuyen (Resources priority)") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Resources priority grant", value: "¥\(draft.budget.nuyenTotal.formatted())")
                    LabeledContent("Cash on hand", value: "¥\(draft.nuyen.formatted())")
                    if draft.budget.nuyenTotal == 0 {
                        Text("Resources is E (or unset) — raise that priority letter for a starting nuyen budget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Cash matches the full grant. Spend it after creation (Gear / lifestyle), not by lowering this number.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Contact roles from the edition catalog (fallback list if catalog empty).
    var contactRoleOptions: [String] {
        let fromCatalog = catalog
            .entries(kinds: [.contactRole], query: "", edition: draft.edition)
            .map { Self.displayContactRoleName($0.name) }
            .filter { !$0.isEmpty }
        let unique = Array(Set(fromCatalog)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        if unique.isEmpty {
            return [
                "Fixer", "Johnson", "Talismonger", "Street Doc", "Fence", "Smuggler",
                "Bartender", "Beat Cop", "Detective", "Armorer", "Decker", "Landlord"
            ]
        }
        return unique
    }

    private static func displayContactRoleName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" Contact Role", " contact role"] {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return name
    }

    // MARK: - Finish

}
