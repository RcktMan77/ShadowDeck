import SwiftUI

extension AdvancementPlannerView {
    var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Suggested for You")
            Text("Hints only — based on metatype bias, concept role keywords when recognized, and cheap next raises. Full lists stay below.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            let groups = suggestionGroups
            if groups.isEmpty {
                Text("No raiseable skills or attributes right now (at maxima or empty sheet).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        suggestionGroupBlock(title: group.title, items: group.items)
                    }
                }
            }
        }
    }

    func suggestionGroupBlock(title: String, items: [AdvancementRaisePreview]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(items) { preview in
                    raiseRow(preview)
                    if preview.id != items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Attributes

    var attributesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Attributes")
            VStack(spacing: 0) {
                ForEach(attributePreviews) { preview in
                    raiseRow(preview)
                    if preview.id != attributePreviews.last?.id {
                        Divider()
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Skills

    var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Skills")
                Spacer()
                Picker("Filter", selection: $skillFilter) {
                    ForEach(AdvancementSkillListFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Picker("Sort", selection: $skillSort) {
                    ForEach(AdvancementSkillListSort.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .frame(maxWidth: 140)
            }

            if skillPreviews.isEmpty {
                Text("No skills match this filter. Add skills on the Skills tab or New Skill…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(skillPreviews) { preview in
                        raiseRow(preview)
                        if preview.id != skillPreviews.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // MARK: - Ledger

    var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recent Advances")
            let entries = Array(character.advancementLedgerEntries.prefix(20))
            if entries.isEmpty {
                Text("Applied purchases will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.summary)
                                    .font(.caption)
                                HStack(spacing: 6) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    if entry.kind == .runAward {
                                        Text("Run award")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.green.opacity(0.9))
                                    }
                                }
                            }
                            Spacer()
                            Text(ledgerKarmaLabel(entry.karmaSpent))
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(entry.karmaSpent < 0 ? .green : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    /// Formats ledger karma: positive = spent (−N), negative = gained (+N).
    func ledgerKarmaLabel(_ karmaSpent: Int) -> String {
        if karmaSpent > 0 { return "−\(karmaSpent)" }
        if karmaSpent < 0 { return "+\(-karmaSpent)" }
        return "—"
    }

    // MARK: - Rows

    func raiseRow(_ preview: AdvancementRaisePreview) -> some View {
        let inCart = cartTargetKeys.contains(preview.targetKey)
        let impact = AdvancementGuidance.impact(for: preview, character: character, rules: rules)
        let highlightID = "skill-\(preview.targetKey)"
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preview.displayName)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text("\(preview.fromRating) → \(preview.toRating)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if preview.canRaise {
                        Text("\(preview.karmaCost) karma")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    } else {
                        Text("At max")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("max \(preview.maxRating)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                // Compact progress indicator
                progressBar(current: preview.fromRating, maximum: preview.maxRating)
                if let impact {
                    Text(impact.headline)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if preview.canRaise {
                let canAddToPlan = AdvancementEngine.canAffordPlanAdd(
                    karmaAvailable: character.karmaAvailable,
                    currentPlanTotal: planTotal,
                    itemCost: preview.karmaCost
                )
                Button(inCart ? "In Plan" : "Add") {
                    addPreviewToCart(preview)
                }
                .disabled(inCart || !canAddToPlan)
                .controlSize(.small)
                .help(
                    inCart
                        ? "Already in plan"
                        : (canAddToPlan ? "Add to plan" : "Not enough karma for plan")
                )
                .modifier(MarketingHighlightPulse(active: marketingHighlight == highlightID && !inCart))

                Button("Buy") {
                    if let item = planItem(from: preview) {
                        errorMessage = nil
                        pendingBuy = item
                    }
                }
                .controlSize(.small)
                .disabled(preview.karmaCost > character.karmaAvailable)
                .help(preview.karmaCost > character.karmaAvailable ? "Not enough karma" : "Buy this raise now")
            }
        }
        .padding(.vertical, 6)
        .opacity(preview.canRaise ? 1 : 0.55)
        .help(impact?.detail ?? "")
        .accessibilityHint(impact?.detail ?? "")
        .id(highlightID)
        .modifier(MarketingHighlightPulse(active: marketingHighlight == highlightID))
    }

    func progressBar(current: Int, maximum: Int) -> some View {
        let clampedMax = Swift.max(1, maximum)
        let fraction = min(1, CGFloat(current) / CGFloat(clampedMax))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: Swift.max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .frame(maxWidth: 160)
        .accessibilityLabel("Rating \(current) of \(maximum)")
    }

    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    // MARK: - Cart helpers (persisted on character)

    func setCart(_ items: [AdvancementPlanItem], persist: Bool = true) {
        character.advancementPlanItems = items
        if persist { onPersist() }
    }

    func removeFromCart(id: UUID) {
        setCart(cart.filter { $0.id != id })
    }

    func planItem(from preview: AdvancementRaisePreview) -> AdvancementPlanItem? {
        switch preview.kind {
        case .skillRaise:
            return AdvancementEngine.makeSkillRaiseItem(
                character: character,
                catalogKey: preview.targetKey,
                rules: rules
            )
        case .attributeRaise:
            guard let attr = AttributeID(rawValue: preview.targetKey) else { return nil }
            return AdvancementEngine.makeAttributeRaiseItem(
                character: character,
                attribute: attr,
                rules: rules
            )
        case .newSkill, .other, .runAward:
            return nil
        }
    }

    func addPreviewToCart(_ preview: AdvancementRaisePreview) {
        errorMessage = nil
        guard preview.canRaise else { return }
        guard !cartTargetKeys.contains(preview.targetKey) else { return }
        guard let item = planItem(from: preview) else { return }
        guard AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: character.karmaAvailable,
            currentPlanTotal: planTotal,
            itemCost: item.karmaCost
        ) else {
            errorMessage = "Not enough karma to add \(item.displayName) to the plan (need \(item.karmaCost), available after plan \(max(0, remainingAfterPlan)))."
            return
        }
        setCart(cart + [item])
    }

    func addNewSkillToCart(_ entry: CatalogEntry) {
        errorMessage = nil
        let key = ManagementSupport.catalogKey(from: entry.name)
        if character.skills.contains(where: {
            $0.catalogKey == key
                || $0.displayName.caseInsensitiveCompare(entry.name) == .orderedSame
        }) {
            errorMessage = "\(entry.name) is already on the character — raise it from the list."
            return
        }
        if cartTargetKeys.contains(key) {
            errorMessage = "\(entry.name) is already in the plan."
            return
        }
        let category = skillCategory(from: entry)
        let item = AdvancementEngine.makeNewSkillItem(
            catalogKey: key,
            displayName: entry.name,
            category: category,
            rules: rules
        )
        guard AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: character.karmaAvailable,
            currentPlanTotal: planTotal,
            itemCost: item.karmaCost
        ) else {
            errorMessage = "Not enough karma to add \(entry.name) to the plan."
            return
        }
        setCart(cart + [item])
    }

    func addCustomNewSkillToCart() {
        errorMessage = nil
        let name = "Custom Skill"
        let key = ManagementSupport.catalogKey(from: name) + "_\(UUID().uuidString.prefix(6))"
        let item = AdvancementEngine.makeNewSkillItem(
            catalogKey: key,
            displayName: name,
            category: .active,
            rules: rules
        )
        guard AdvancementEngine.canAffordPlanAdd(
            karmaAvailable: character.karmaAvailable,
            currentPlanTotal: planTotal,
            itemCost: item.karmaCost
        ) else {
            errorMessage = "Not enough karma to add a new skill to the plan."
            return
        }
        setCart(cart + [item])
        onStatus?("Added custom skill placeholder to plan (rename after apply via Skills tab if needed).")
    }

    func skillCategory(from entry: CatalogEntry) -> SkillCategory {
        let cat = entry.category.lowercased()
        let notes = entry.notes.lowercased()
        if cat.contains("language") {
            return .language
        }
        if notes == "knowledge" || cat.contains("knowledge")
            || ["academic", "interest", "professional", "street"].contains(cat) {
            return .knowledge
        }
        return .active
    }

    // MARK: - Stale cart

    /// Drop or rebuild cart lines whose fromRating / cost no longer match the character.
}
