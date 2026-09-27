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

    @State var skillFilter: AdvancementSkillListFilter = .all
    @State var skillSort: AdvancementSkillListSort = .name
    @State var skillPreviewCache = AdvancementSkillPreviewCache()
    @State var errorMessage: String?
    @State var confirmApplyPlan = false
    @State var pendingBuy: AdvancementPlanItem?
    @State var showNewSkill = false
    /// Marketing GIF scroll / pulse targets.
    @State var marketingAnchor: String?
    @State var marketingHighlight: String?

    /// Draft plan is stored on the character so it survives tab switches and app restarts.
    var cart: [AdvancementPlanItem] {
        character.advancementPlanItems
    }

    var rules: any EditionRules {
        RulesRegistry.rules(for: character.edition)
    }

    var planTotal: Int {
        cart.reduce(0) { $0 + $1.karmaCost }
    }

    var remainingAfterPlan: Int {
        character.karmaAvailable - planTotal
    }

    var cartTargetKeys: Set<String> {
        Set(cart.map(\.targetKey))
    }

    var attributePreviews: [AdvancementRaisePreview] {
        AdvancementEngine.raiseableAttributes(for: character).map {
            AdvancementEngine.attributeRaisePreview(character: character, attribute: $0, rules: rules)
        }
    }

    var skillPreviews: [AdvancementRaisePreview] {
        skillPreviewCache.previews
    }

    /// The only place skill-raise rows are rebuilt.
    func invalidateSkillPreviews() {
        skillPreviewCache.invalidate(
            character: character,
            rules: rules,
            filter: skillFilter,
            sort: skillSort
        )
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
            .onAppear {
                refreshStaleCart()
                invalidateSkillPreviews()
            }
            .onChange(of: skillFilter) { _, _ in invalidateSkillPreviews() }
            .onChange(of: skillSort) { _, _ in invalidateSkillPreviews() }
            .onChange(of: character.karmaAvailable) { _, _ in
                refreshStaleCart()
                invalidateSkillPreviews()
            }
            .onChange(of: character.skills) { _, _ in
                refreshStaleCart()
                invalidateSkillPreviews()
            }
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
                edition: character.edition,
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

    var stickyPlannerChrome: some View {
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
                    Text("Short by \(-remainingAfterPlan) karma — remove items or earn more before Apply. New adds are blocked while over budget.")
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
    var stickyChromeContentHeight: CGFloat { 108 }

    func metric(_ title: String, _ value: String, emphasizeNegative: Bool = false) -> some View {
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

    var planPanel: some View {
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
    var suggestionGroups: [(title: String, items: [AdvancementRaisePreview])] {
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

    func refreshStaleCart() {
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

    func applyPlan() {
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

    func buyNow(_ item: AdvancementPlanItem) {
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
