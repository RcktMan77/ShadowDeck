//
//  AdvancementPlannerView.swift
//  ShadowDeck
//
//  Character Advance tab — plan karma spends for skills and attributes.
//

import SwiftUI

struct AdvancementPlannerView: View {
    @Binding var character: Character
    var onPersist: () -> Void
    var onStatus: ((String) -> Void)?

    @State private var skillFilter: SkillFilter = .all
    @State private var skillSort: SkillSort = .name
    @State private var errorMessage: String?
    @State private var confirmApplyPlan = false
    @State private var pendingBuy: AdvancementPlanItem?
    @State private var showNewSkill = false
    /// Marketing GIF scroll / pulse targets.
    @State private var marketingAnchor: String?
    @State private var marketingHighlight: String?

    /// Draft plan is stored on the character so it survives tab switches and app restarts.
    private var cart: [AdvancementPlanItem] {
        character.advancementPlanItems
    }

    private enum SkillFilter: String, CaseIterable, Identifiable {
        case all, active, knowledge, language
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .active: "Active"
            case .knowledge: "Knowledge"
            case .language: "Language"
            }
        }
    }

    private enum SkillSort: String, CaseIterable, Identifiable {
        case name, cheapest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: "Name"
            case .cheapest: "Cheapest"
            }
        }
    }

    private var rules: any EditionRules {
        RulesRegistry.rules(for: character.edition)
    }

    private var planTotal: Int {
        cart.reduce(0) { $0 + $1.karmaCost }
    }

    private var remainingAfterPlan: Int {
        character.karmaAvailable - planTotal
    }

    private var cartTargetKeys: Set<String> {
        Set(cart.map(\.targetKey))
    }

    private var attributePreviews: [AdvancementRaisePreview] {
        AdvancementEngine.raiseableAttributes(for: character).map {
            AdvancementEngine.attributeRaisePreview(character: character, attribute: $0, rules: rules)
        }
    }

    private var skillPreviews: [AdvancementRaisePreview] {
        var list = character.skills.map {
            AdvancementEngine.skillRaisePreview(character: character, skill: $0, rules: rules)
        }
        switch skillFilter {
        case .all: break
        case .active: list = list.filter { $0.skillCategory == .active }
        case .knowledge: list = list.filter { $0.skillCategory == .knowledge }
        case .language: list = list.filter { $0.skillCategory == .language }
        }
        switch skillSort {
        case .name:
            list.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .cheapest:
            list.sort {
                if $0.canRaise != $1.canRaise { return $0.canRaise && !$1.canRaise }
                if $0.karmaCost != $1.karmaCost { return $0.karmaCost < $1.karmaCost }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        return list
    }

    var body: some View {
        ManagementListChrome(
            title: "Advancement Planner",
            subtitle: "Raise skills and attributes with edition karma costs. The Skills tab can still adjust ranks without cost for imports or house rulings.",
            onAdd: { showNewSkill = true },
            addLabel: "New Skill…",
            onLookUp: {
                RulesReferenceOpener.request(query: "karma", character: character)
            },
            lookUpLabel: "Look up"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                // Sticky metrics + plan side-by-side (do not scroll away).
                stickyPlannerChrome
                    .id("planHeader")
                    .modifier(MarketingHighlightPulse(active: marketingHighlight == "applyPlan"))

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            suggestionsSection
                            attributesSection
                            skillsSection
                                .id("skills")
                            ledgerSection
                                .id("ledger")
                        }
                    }
                    .onChange(of: marketingAnchor) { _, anchor in
                        guard let anchor else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(anchor, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { refreshStaleCart() }
            .onChange(of: character.karmaAvailable) { _, _ in refreshStaleCart() }
            .onChange(of: character.skills) { _, _ in refreshStaleCart() }
            .onChange(of: character.attributes) { _, _ in refreshStaleCart() }
            .onReceive(NotificationCenter.default.publisher(for: AppCommand.marketingFocus)) { note in
                marketingAnchor = note.userInfo?["anchor"] as? String
                marketingHighlight = note.userInfo?["highlight"] as? String
                // Skills list often needs an explicit scroll after reload.
                if marketingAnchor == "skills" {
                    skillFilter = .all
                    skillSort = .name
                }
            }
        }
        .sheet(isPresented: $showNewSkill) {
            CatalogBrowserView(
                title: "New Skill (rank 1)",
                kinds: [.skill],
                onPick: { entry in
                    addNewSkillToCart(entry)
                    showNewSkill = false
                },
                onCustom: {
                    showNewSkill = false
                    addCustomNewSkillToCart()
                },
                onCancel: { showNewSkill = false }
            )
        }
        .confirmationDialog(
            "Apply advancement plan?",
            isPresented: $confirmApplyPlan,
            titleVisibility: .visible
        ) {
            Button("Spend \(planTotal) Karma") {
                applyPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                cart.isEmpty
                    ? "Plan is empty."
                    : "Apply \(cart.count) raise\(cart.count == 1 ? "" : "s") for \(planTotal) karma. Available: \(character.karmaAvailable)."
            )
        }
        .confirmationDialog(
            "Buy now?",
            isPresented: Binding(
                get: { pendingBuy != nil },
                set: { if !$0 { pendingBuy = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingBuy {
                Button("Spend \(item.karmaCost) Karma") {
                    buyNow(item)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingBuy = nil
            }
        } message: {
            if let item = pendingBuy {
                Text(item.progressSummary)
            }
        }
    }

    // MARK: - Sticky chrome (metrics left, plan right)

    private var stickyPlannerChrome: some View {
        // Metrics sit left; Plan fills the rest. Trailing edge of the plan ScrollView
        // matches the main tab ScrollView (no extra trailing inset) so both scroll bars line up.
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    metric("Karma Available", "\(character.karmaAvailable)")
                    metric("Plan Total", "\(planTotal)")
                    metric("After Plan", "\(remainingAfterPlan)", emphasizeNegative: remainingAfterPlan < 0)
                }

                HStack(spacing: 10) {
                    AppChromeButton.title(
                        "Clear Plan",
                        help: "Remove all items from the plan",
                        isEnabled: !cart.isEmpty
                    ) {
                        setCart([])
                        errorMessage = nil
                    }

                    AppChromeButton.title(
                        "Apply Plan…",
                        help: remainingAfterPlan < 0
                            ? "Plan exceeds available karma — keep it as a goal, or remove items / earn more karma"
                            : "Apply all planned raises",
                        style: .prominent,
                        isEnabled: !cart.isEmpty && remainingAfterPlan >= 0,
                        keyEquivalent: "\r"
                    ) {
                        errorMessage = nil
                        confirmApplyPlan = true
                    }
                    .modifier(MarketingHighlightPulse(active: marketingHighlight == "applyPlan"))
                }

                if remainingAfterPlan < 0, !cart.isEmpty {
                    Text("Short by \(-remainingAfterPlan) karma — plan is saved as a goal.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 280, idealWidth: 360, maxWidth: 420, alignment: .topLeading)
            .padding(.leading, 10)
            .padding(.vertical, 10)

            planPanel
                .frame(maxWidth: .infinity, maxHeight: stickyChromeContentHeight, alignment: .topLeading)
                .padding(.top, 10)
                .padding(.bottom, 10)
                // No trailing padding — plan ScrollView indicator aligns with main list indicator.
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Caps overall sticky strip height so Suggested/full lists start higher.
    private var stickyChromeContentHeight: CGFloat { 108 }

    private func metric(_ title: String, _ value: String, emphasizeNegative: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(emphasizeNegative ? Color.red : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var planPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Plan")
                    .font(.subheadline.weight(.semibold))
                if !cart.isEmpty {
                    Text("\(cart.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 10)

            if cart.isEmpty {
                Text("Add raises below to build a plan. Saved with the character — nothing spends until Apply or Buy Now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 8)
                    .padding(.vertical, 8)
                    .padding(.trailing, 10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                // ScrollView extends to the trailing edge of the tab content (same as main ScrollView).
                // Content is padded; the indicator stays on the shared trailing edge.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(cart) { item in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(item.fromRating) → \(item.toRating)  ·  \(item.karmaCost) karma")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Button(role: .destructive) {
                                    removeFromCart(id: item.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from plan")
                            }
                            .padding(.vertical, 5)
                            if item.id != cart.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                // Keep a hair of corner radius inset without moving the indicator track.
                .padding(.trailing, 0)
            }
        }
    }

    // MARK: - Suggestions

    /// Grouped suggestion buckets for display (attributes, then skill categories).
    private var suggestionGroups: [(title: String, items: [AdvancementRaisePreview])] {
        // Pull a wider pool so each type can surface a few rows after grouping.
        let all = AdvancementEngine.suggestions(for: character, rules: rules, limit: 18)
        let perGroup = 4
        let attributes = Array(all.filter { $0.kind == .attributeRaise }.prefix(perGroup))
        let active = Array(all.filter { $0.kind == .skillRaise && $0.skillCategory == .active }.prefix(perGroup))
        let knowledge = Array(all.filter { $0.kind == .skillRaise && $0.skillCategory == .knowledge }.prefix(perGroup))
        let language = Array(all.filter { $0.kind == .skillRaise && $0.skillCategory == .language }.prefix(perGroup))
        // newSkill suggestions (from role/catalog) land under active if uncategorized.
        let newSkills = Array(all.filter { $0.kind == .newSkill }.prefix(perGroup))
        let activeCombined = Array((active + newSkills).prefix(perGroup))

        return [
            ("Attributes", attributes),
            ("Active Skills", activeCombined),
            ("Knowledge Skills", knowledge),
            ("Languages", language)
        ].filter { !$0.items.isEmpty }
    }

    private var suggestionsSection: some View {
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

    private func suggestionGroupBlock(title: String, items: [AdvancementRaisePreview]) -> some View {
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

    private var attributesSection: some View {
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

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Skills")
                Spacer()
                Picker("Filter", selection: $skillFilter) {
                    ForEach(SkillFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Picker("Sort", selection: $skillSort) {
                    ForEach(SkillSort.allCases) { s in
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

    private var ledgerSection: some View {
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
    private func ledgerKarmaLabel(_ karmaSpent: Int) -> String {
        if karmaSpent > 0 { return "−\(karmaSpent)" }
        if karmaSpent < 0 { return "+\(-karmaSpent)" }
        return "—"
    }

    // MARK: - Rows

    private func raiseRow(_ preview: AdvancementRaisePreview) -> some View {
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
                Button(inCart ? "In Plan" : "Add") {
                    addPreviewToCart(preview)
                }
                .disabled(inCart)
                .controlSize(.small)
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

    private func progressBar(current: Int, maximum: Int) -> some View {
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    // MARK: - Cart helpers (persisted on character)

    private func setCart(_ items: [AdvancementPlanItem], persist: Bool = true) {
        character.advancementPlanItems = items
        if persist { onPersist() }
    }

    private func removeFromCart(id: UUID) {
        setCart(cart.filter { $0.id != id })
    }

    private func planItem(from preview: AdvancementRaisePreview) -> AdvancementPlanItem? {
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

    private func addPreviewToCart(_ preview: AdvancementRaisePreview) {
        errorMessage = nil
        guard preview.canRaise else { return }
        guard !cartTargetKeys.contains(preview.targetKey) else { return }
        guard let item = planItem(from: preview) else { return }
        setCart(cart + [item])
    }

    private func addNewSkillToCart(_ entry: CatalogEntry) {
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
        setCart(cart + [item])
    }

    private func addCustomNewSkillToCart() {
        errorMessage = nil
        let name = "Custom Skill"
        let key = ManagementSupport.catalogKey(from: name) + "_\(UUID().uuidString.prefix(6))"
        let item = AdvancementEngine.makeNewSkillItem(
            catalogKey: key,
            displayName: name,
            category: .active,
            rules: rules
        )
        setCart(cart + [item])
        onStatus?("Added custom skill placeholder to plan (rename after apply via Skills tab if needed).")
    }

    private func skillCategory(from entry: CatalogEntry) -> SkillCategory {
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
    private func refreshStaleCart() {
        guard !cart.isEmpty else { return }
        var refreshed: [AdvancementPlanItem] = []
        var dropped = false
        var changed = false
        for item in cart {
            switch item.kind {
            case .skillRaise:
                if let live = AdvancementEngine.makeSkillRaiseItem(
                    character: character,
                    catalogKey: item.targetKey,
                    rules: rules
                ) {
                    if live.fromRating != item.fromRating || live.karmaCost != item.karmaCost {
                        changed = true
                    }
                    refreshed.append(live)
                } else {
                    dropped = true
                    changed = true
                }
            case .attributeRaise:
                if let attr = AttributeID(rawValue: item.targetKey),
                   let live = AdvancementEngine.makeAttributeRaiseItem(
                       character: character,
                       attribute: attr,
                       rules: rules
                   ) {
                    if live.fromRating != item.fromRating || live.karmaCost != item.karmaCost {
                        changed = true
                    }
                    refreshed.append(live)
                } else {
                    dropped = true
                    changed = true
                }
            case .newSkill:
                if character.skills.contains(where: { $0.catalogKey == item.targetKey }) {
                    dropped = true
                    changed = true
                } else {
                    let category = item.skillCategory ?? .active
                    let live = AdvancementEngine.makeNewSkillItem(
                        catalogKey: item.targetKey,
                        displayName: item.displayName,
                        category: category,
                        rules: rules
                    )
                    if live.karmaCost != item.karmaCost {
                        changed = true
                    }
                    refreshed.append(live)
                }
            case .other, .runAward:
                dropped = true
                changed = true
            }
        }
        // One pending raise per target
        var seen = Set<String>()
        let deduped = refreshed.filter { seen.insert($0.targetKey).inserted }
        if deduped.count != refreshed.count { changed = true }
        guard changed || dropped else { return }
        setCart(deduped)
        if dropped {
            errorMessage = "Plan updated — some items no longer match the character."
        }
    }

    // MARK: - Apply

    private func applyPlan() {
        errorMessage = nil
        guard !cart.isEmpty else { return }
        let items = cart
        let spent = planTotal
        let count = items.count
        do {
            try AdvancementEngine.apply(items: items, to: &character, rules: rules)
            character.advancementPlanItems = []
            onPersist()
            onStatus?("Applied \(count) advance\(count == 1 ? "" : "s") (−\(spent) karma).")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func buyNow(_ item: AdvancementPlanItem) {
        errorMessage = nil
        pendingBuy = nil
        do {
            try AdvancementEngine.apply(item, to: &character, rules: rules)
            // Drop matching cart entry if present
            character.advancementPlanItems = character.advancementPlanItems.filter {
                $0.targetKey != item.targetKey
            }
            onPersist()
            onStatus?("Bought \(item.displayName) (−\(item.karmaCost) karma).")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
