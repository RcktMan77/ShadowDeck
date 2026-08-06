//
//  GenerationWizardView.swift
//  ShadowDeck
//
//  Multi-page character generation with painted art, rules help, and recommendations.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GenerationWizardView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var draft = GenerationDraft()
    @State private var statusMessage: String?
    @State private var didFinish = false
    @State private var avatarImportError: String?
    @State private var scrollAnchor = UUID()
    @State private var showHouseRulesBrowser = false
    @State private var confirmCancel = false
    @State private var showSpellCatalog = false
    @State private var draftContactName = ""
    @State private var draftContactRole = "Fixer"
    @State private var draftContactConnection = 2
    @State private var draftContactLoyalty = 2
    /// Text field for direct BP entry on the SR4 resources step (kept in sync with draft.nuyen).
    @State private var resourceBPText = "0"

    var onFinished: (() -> Void)?
    /// Leave the wizard without saving (any step).
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AllocationCounterBar(draft: draft)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()

            // Sticky profile art after concept is chosen
            if draft.step > .concept {
                ProfileArtChrome(draft: draft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }

            // Sticky priority balance on priorities step
            if draft.step == .priorities && draft.generationSystem != .buildPoints {
                PriorityBalanceBanner(draft: draft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    stepContent
                        .padding(20)
                        .frame(maxWidth: 960, alignment: .leading)
                        .id(scrollAnchor)
                }
                .onChange(of: draft.step) { _, _ in
                    statusMessage = nil
                    scrollAnchor = UUID()
                    Task { @MainActor in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(scrollAnchor, anchor: .top)
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.wizardShowRoleStep)) { _ in
            // Marketing screenshots: land on Concept & Role with a photogenic archetype.
            draft.edition = .sr5
            draft.archetype = .decker
            if draft.concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.concept = "Ex-Renraku matrix specialist"
            }
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = "Aiko Sato"
            }
            if draft.streetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.streetName = "Ghostwire"
            }
            draft.step = .concept
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Cancel character creation?",
            isPresented: $confirmCancel,
            titleVisibility: .visible
        ) {
            Button("Discard Character", role: .destructive) {
                onCancel?()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Progress in this wizard will be lost. Nothing has been saved to your library yet.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Character")
                    .font(.title2.weight(.semibold))
                Text("Step \(draft.step.rawValue + 1) of \(draft.steps.count) — \(draft.step.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Progress dots only — Cancel lives next to Back in the footer.
            HStack(spacing: 6) {
                ForEach(draft.steps) { step in
                    Circle()
                        .fill(step == draft.step ? Color.accentColor : (step < draft.step ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25)))
                        .frame(width: 8, height: 8)
                        .help(step.title)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch draft.step {
        case .edition: editionStep
        case .concept: conceptStep
        case .metatype: metatypeStep
        case .priorities: prioritiesStep
        case .attributes: attributesStep
        case .magic: magicStep
        case .skills: skillsStep
        case .qualities: qualitiesStep
        case .resources: resourcesStep
        case .finish: finishStep
        }
    }

    private var footer: some View {
        HStack {
            AppChromeButton.title(
                "Cancel",
                help: "Leave without saving this character"
            ) {
                requestCancel()
            }
            AppChromeButton.title(
                "Back",
                help: "Previous step",
                isEnabled: draft.step != .edition
            ) {
                draft.goBack()
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if draft.step == .finish {
                AppChromeButton.title(
                    "Save Character",
                    help: "Save this character to your library",
                    style: .prominent,
                    isEnabled: draft.canGoNext && !didFinish,
                    keyEquivalent: "\r"
                ) {
                    saveCharacter()
                }
            } else {
                AppChromeButton.title(
                    "Continue",
                    help: "Next step",
                    style: .prominent,
                    isEnabled: draft.canGoNext,
                    keyEquivalent: "\r"
                ) {
                    draft.goNext()
                }
            }
        }
        .padding(16)
    }

    // MARK: - Edition

    private var editionStep: some View {
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

    private var houseRulesSummaryLine: String {
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

    private var houseRuleChips: some View {
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

    private func editionCard(_ edition: Edition) -> some View {
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

    private var conceptStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Concept & Role")
                .font(.title3.weight(.semibold))
            HelpCallout(text: """
                Pick a runner role (playstyle archetype). This is not a mechanical character class—\
                it guides recommendations and your default Magic/Resonance path.
                """)

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    PaintedPortraitView(kind: .archetype(draft.archetype), showLabel: true)
                        .frame(height: 320)
                        .animation(.easeInOut(duration: 0.3), value: draft.archetype)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(draft.archetype.tagline)
                            .font(.headline)
                        EmphasizedHelpText(text: draft.archetype.summaryMarkdown)

                        Divider()
                        Text("Suggested Focus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(draft.archetype.suggestedFocus, id: \.self) { focus in
                                Text(focus)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default Magical Path")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(draft.archetype.defaultPathLabel)
                                .font(.callout)
                            EmphasizedHelpText(text: pathDescriptionMarkdown(draft.archetype.defaultAwakened))
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 380)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(RunnerArchetype.allCases) { arch in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                draft.selectArchetype(arch)
                            }
                        } label: {
                            PaintedPortraitView(
                                kind: .archetype(arch),
                                cornerRadius: 10,
                                showLabel: true
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        draft.archetype == arch ? Color.accentColor : Color.clear,
                                        lineWidth: 3
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sheet concept line")
                    .font(.subheadline.weight(.semibold))
                Text(ChargenHelpCatalog.conceptFieldHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Ex-Renraku security consultant", text: $draft.concept)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Metatype

    private var metatypeStep: some View {
        let showBPCosts = draft.generationSystem == .buildPoints
        return VStack(alignment: .leading, spacing: 16) {
            Text("Metatype")
                .font(.title3.weight(.semibold))
            if showBPCosts {
                HelpCallout(text: """
                    Your metatype sets natural min/max attributes and costs **Build Points** from the **400 BP** budget \
                    (Human **0**, Ork **20**, Dwarf **25**, Elf **30**, Troll **40**). \
                    Body and Edge ranges matter for every runner:
                    """)
            } else {
                HelpCallout(text: """
                    Your metatype sets natural minimum and maximum scores for attributes. \
                    Availability and special/adjustment points come from the **Metatype** priority column (not a flat karma fee). \
                    Body and Edge are especially important for every runner:
                    """)
            }

            HStack(spacing: 12) {
                attributeChip(id: .body, short: "BOD")
                attributeChip(id: .edge, short: "EDG")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(MetatypeID.allCases) { meta in
                    let profile = MetatypeCatalog.profile(for: meta, edition: draft.edition)
                    let selected = draft.metatype == meta
                    let bpCost = SR4BuildPointEngine.metatypeCost(meta)
                    Button {
                        draft.selectMetatype(meta)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PaintedPortraitView(kind: .metatype(meta), cornerRadius: 8, showLabel: false)
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .contentShape(Rectangle())
                            HStack(alignment: .firstTextBaseline) {
                                Text(meta.displayName)
                                    .font(.headline)
                                Spacer(minLength: 4)
                                if showBPCosts {
                                    Text(bpCost == 0 ? "0 BP" : "\(bpCost) BP")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                                        )
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                        .help("SR4A metatype Build Point cost")
                                }
                            }
                            Text(ChargenHelpCatalog.metatypeBlurb(meta))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("BOD \(profile.bounds(for: .body).minimum)–\(profile.bounds(for: .body).maximum) · EDG max \(profile.bounds(for: .edge).maximum)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func attributeChip(id: AttributeID, short: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(short) — \(id.displayName)")
                .font(.subheadline.weight(.semibold))
            Text(ChargenHelpCatalog.attributeDescription(id))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Influences: \(ChargenHelpCatalog.attributeInfluences(id))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func pathDescriptionMarkdown(_ path: AwakenedPath) -> String {
        // Emphasize key game terms consistently for hover help.
        switch path {
        case .mundane:
            "You have no **Magic** or **Resonance**—neither a spellcaster nor a technomancer. Most runners are mundane and rely on **Skills**, **Edge**, gear, and cyberware."
        case .fullMagician:
            "A Magician channels mana to cast spells, summon spirits, and project astrally. You need a **Magic** attribute; **Essence** loss from cyberware can reduce **Magic**."
        case .aspectedMagician:
            "Limited to one magical skill category (for example only **Sorcery**, Conjuring, or Enchanting). Cheaper than a full Magician, with a narrower toolbox."
        case .mysticAdept:
            "Splits power between spellcasting and adept powers. Flexible but expensive; you juggle **Magic** for both spells and power points."
        case .adept:
            "Spends **Magic** on adept powers (improved reflexes, combat sense, attribute boosts) instead of spells. Your body is the focus."
        case .technomancer:
            "Emerged, not awakened: **Resonance** replaces a cyberdeck. You thread complex forms and compile sprites. Guard your **Essence**."
        }
    }

    // MARK: - Priorities

    private var prioritiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if draft.generationSystem == .buildPoints {
                Text("Build Points overview")
                    .font(.title3.weight(.semibold))
                Text("You do not assign BP here — later steps spend it. This page is your live ledger.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                buildPointsOverview
            } else {
                Text("Priorities")
                    .font(.title3.weight(.semibold))
                HelpCallout(text: {
                    if draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen) {
                        return """
                            Assign priority letters so their values sum to 10 (A=4, B=3, C=2, D=1, E=0). \
                            Duplicates are allowed. Watch the balance banner above as you click.
                            """
                    }
                    return """
                        Assign each of A–E exactly once across the five columns. \
                        The balance banner above updates as you choose.
                        """
                }())

                RecommendButton(
                    title: "Apply Recommended Priorities",
                    subtitle: ChargenRecommendations.priorities(archetype: draft.archetype, metatype: draft.metatype).rationale
                ) {
                    draft.applyRecommendedPriorities()
                }

                ForEach(PriorityColumn.allCases, id: \.self) { column in
                    priorityRow(column)
                }
            }
        }
    }

    /// Live SR4A BP category breakdown (real accounting — not placeholder pools).
    private var buildPointsOverview: some View {
        let ledger = draft.buildPointLedger
        let remaining = draft.budget.buildPointsRemaining
        let total = draft.budget.buildPointsTotal
        let rows: [(label: String, rate: String, bp: Int)] = [
            ("Metatype", "Fixed cost (Human 0 · Ork 20 · Dwarf 25 · Elf 30 · Troll 40)", ledger.metatype),
            ("Attributes", "10 BP per point above racial/path min (incl. Edge, Magic, Resonance)", ledger.attributes),
            ("Skills", "4 BP per active rank · 2 BP per knowledge/language rank", ledger.skills),
            ("Skill groups", "10 BP per rating (max 4 at chargen)", ledger.skillGroups),
            ("Spells", "3 BP each (max 2× higher of Spellcasting / Ritual Spellcasting)", ledger.spells),
            ("Contacts", "Connection + Loyalty (each 1–6)", ledger.contacts),
            ("Qualities", "Positive cost BP · negative refund · ±35 BP caps", ledger.qualities),
            ("Resources", "1 BP = ¥5,000 starting nuyen", ledger.resources)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            // Compact wallet strip (no multi-line cost essay).
            HStack(spacing: 20) {
                bpWalletStat(title: "Budget", value: "\(total) BP")
                bpWalletStat(title: "Spent", value: "\(ledger.total) BP")
                bpWalletStat(
                    title: "Remaining",
                    value: "\(remaining) BP",
                    valueColor: remaining < 0 ? .red : .primary
                )
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if remaining < 0 {
                Text("Over budget — reduce spends on later steps before finishing.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            GroupBox {
                VStack(spacing: 0) {
                    // Column headers
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Category")
                            .frame(width: 110, alignment: .leading)
                        Text("How you spend")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Spent")
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                    Divider()

                    ForEach(rows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label)
                                .font(.body.weight(.medium))
                                .frame(width: 110, alignment: .leading)
                            Text(row.rate)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(row.bp) BP")
                                .font(.body.monospacedDigit().weight(row.bp > 0 ? .semibold : .regular))
                                .foregroundStyle(row.bp > 0 ? Color.primary : Color.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        if row.label != rows.last?.label {
                            Divider()
                        }
                    }
                }
            } label: {
                Text("Category ledger")
                    .font(.headline)
            }

            Text("""
                Continue to spend on later steps; this ledger updates live. Metatype is already applied. \
                Out of wizard scope: complex forms as full BP UI, initiate grades, and gear shopping \
                (buy nuyen with BP, then equip on the sheet).
                """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bpWalletStat(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }

    private func priorityRow(_ column: PriorityColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.displayName)
                .font(.title3.weight(.semibold))
            Text(ChargenHelpCatalog.priorityColumnDescription(column))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(PriorityLetter.allCases, id: \.self) { letter in
                    let selected = draft.priority[column] == letter
                    let summary = PrioritySummaryBuilder.summaries(
                        for: draft.edition,
                        metatype: draft.metatype,
                        rules: draft.rules
                    )
                    .first { $0.column == column && $0.letter == letter }

                    Button {
                        draft.assignPriority(letter, to: column)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(letter.rawValue)
                                .font(.title2.weight(.bold))
                            if let summary {
                                ForEach(summary.detailLines.prefix(3), id: \.self) { line in
                                    Text(line)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(summary?.detailLines.joined(separator: "\n") ?? letter.rawValue)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Attributes

    private var attributesStep: some View {
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

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func attributeRow(_ id: AttributeID) -> some View {
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

    private var magicStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Magic / Resonance")
                .font(.title3.weight(.semibold))
            HelpCallout(text: """
                Your path decides whether you use Magic, Resonance, or neither. \
                Mundane is the normal state for most runners—no spells, no complex forms—\
                just skills, Edge, and gear.
                """)

            ForEach(AwakenedPath.allCases, id: \.self) { path in
                let selected = draft.awakened == path
                Button {
                    draft.setAwakenedPath(path)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            Text(path == .mundane ? ChargenHelpCatalog.mundanePathLabel : path.displayName)
                                .font(.headline)
                        }
                        EmphasizedHelpText(text: pathDescriptionMarkdown(path))
                        Text(ChargenHelpCatalog.pathStory(path))
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            if draft.generationSystem == .buildPoints, draft.awakened.usesMagic {
                sr4SpellsSection
            }
        }
        .sheet(isPresented: $showSpellCatalog) {
            CatalogBrowserView(
                title: "Learn Spell (3 BP)",
                kinds: [.gear],
                edition: .sr4,
                matching: { $0.category.localizedCaseInsensitiveContains("spell") },
                onPick: { entry in
                    draft.addSpell(
                        SpellInstance(
                            catalogKey: entry.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                            name: entry.name,
                            category: entry.category
                        )
                    )
                    showSpellCatalog = false
                },
                onCustom: nil,
                onCancel: { showSpellCatalog = false }
            )
        }
    }

    private var sr4SpellsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Spells (SR4A Build Points)")
                .font(.headline)
            HelpCallout(text: """
                Each spell costs **3 BP**. Maximum at chargen is twice the higher of Spellcasting or \
                Ritual Spellcasting (currently max \(draft.maxSpellsAtChargen)). \
                Raise Spellcasting on the Skills step first if you need more slots.
                """)
            LabeledContent("Spells", value: "\(draft.spells.count) / \(draft.maxSpellsAtChargen)")
            LabeledContent("Spell BP", value: "\(draft.buildPointLedger.spells) BP")

            if draft.spells.isEmpty {
                Text("No spells yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.spells) { spell in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spell.name).font(.body.weight(.medium))
                            if !spell.category.isEmpty {
                                Text(spell.category).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("3 BP").font(.caption.monospacedDigit())
                        Button(role: .destructive) {
                            draft.removeSpell(id: spell.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            AppChromeButton.title(
                "Add Spell from Catalog…",
                help: "Browse SR4A spells (3 BP each)",
                isEnabled: draft.canAddSpell()
            ) {
                showSpellCatalog = true
            }
        }
    }

    // MARK: - Skills

    private var skillsStep: some View {
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

    private var qualitiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Qualities")
                .font(.title3.weight(.semibold))
            if draft.generationSystem == .buildPoints {
                HelpCallout(text: """
                    Positive qualities cost **BP**; negative qualities refund **BP**. \
                    Cap **35 BP** of positive and **35 BP** of negative qualities.
                    """)
                GroupBox("Quality BP") {
                    let pos = draft.qualities.filter { $0.kind == .positive }.reduce(0) { $0 + abs($1.karmaValue) }
                    let neg = draft.qualities.filter { $0.kind == .negative }.reduce(0) { $0 + abs($1.karmaValue) }
                    LabeledContent("Positive qualities", value: "\(pos) / 35 BP")
                    LabeledContent("Negative qualities", value: "\(neg) / 35 BP")
                    LabeledContent("Net quality BP", value: "\(draft.buildPointLedger.qualities) BP")
                    LabeledContent("BP remaining", value: "\(draft.budget.buildPointsRemaining)")
                }
            } else {
                HelpCallout(text: "Qualities are optional lasting traits. Positive qualities cost Karma; negative qualities grant Karma but add complications.")

                GroupBox("Karma budgeting") {
                    Text(ChargenHelpCatalog.karmaBudgetGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent(
                        "Positive quality Karma used",
                        value: "\(draft.budget.positiveQualityKarmaUsed) / \(draft.budget.positiveQualityKarmaCap)"
                    )
                    LabeledContent("Karma remaining", value: "\(draft.budget.karmaRemaining)")
                }
            }

            let starters: [(String, String, QualityKind, Int)] = [
                ("toughness", "Toughness", .positive, 10),
                ("guts", "Guts", .positive, 10),
                ("first_impression", "First Impression", .positive, 11),
                ("sinner", "SINner (National)", .negative, 5),
                ("allergy", "Allergy (Common, Mild)", .negative, 10),
                ("distinctive", "Distinctive Style", .negative, 5)
            ]

            ForEach(starters, id: \.0) { item in
                let selected = draft.qualities.contains { $0.catalogKey == item.0 }
                let unit = draft.generationSystem == .buildPoints ? "BP" : "Karma"
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { selected },
                        set: { on in toggleQuality(item, on: on) }
                    )) {
                        Text("\(item.1) (\(item.2 == .positive ? "costs" : "grants") \(item.3) \(unit))")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!selected && !draft.canAddQuality(kind: item.2, karmaValue: item.3))
                    Text(ChargenHelpCatalog.qualityDescription(catalogKey: item.0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var sr4ContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Contacts (SR4A Build Points)")
                .font(.headline)
            HelpCallout(text: """
                **SR4A:** every contact costs **Connection + Loyalty** BP (each 1–6). \
                Example: Connection 3 + Loyalty 5 costs **8 BP**. There is **no free CHA×3 contact pool** \
                in Build Points chargen (that free-point model is for priority editions). \
                Contacts you buy here appear under the **Contacts** tab after you finish.
                """)
            LabeledContent("Contact BP", value: "\(draft.buildPointLedger.contacts) BP")

            if draft.contacts.isEmpty {
                Text("No contacts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.contacts) { contact in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.body.weight(.medium))
                            Text("\(contact.role) · C\(contact.connection) / L\(contact.loyalty)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(draft.contactBPCost(contact)) BP")
                            .font(.caption.monospacedDigit())
                        Button(role: .destructive) {
                            draft.removeContact(id: contact.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GroupBox("Add contact") {
                TextField("Name", text: $draftContactName)
                    .textFieldStyle(.roundedBorder)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Role")
                        .font(.callout)
                        .frame(width: 44, alignment: .leading)
                    Picker("Role", selection: $draftContactRole) {
                        ForEach(contactRoleOptions, id: \.self) { role in
                            Text(role).tag(role)
                        }
                        // Keep a custom selection visible if the user typed something else previously.
                        if !contactRoleOptions.contains(draftContactRole), !draftContactRole.isEmpty {
                            Text(draftContactRole).tag(draftContactRole)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)

                    TextField("Or custom role…", text: $draftContactRole)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                .help("Pick a contact archetype from the SR4A catalog, or type a custom role.")

                Stepper("Connection: \(draftContactConnection)", value: $draftContactConnection, in: 1...6)
                Stepper("Loyalty: \(draftContactLoyalty)", value: $draftContactLoyalty, in: 1...6)
                let cost = SR4BuildPointEngine.contactCost(
                    connection: draftContactConnection,
                    loyalty: draftContactLoyalty
                )
                LabeledContent("Cost", value: "\(cost) BP")
                AppChromeButton.title(
                    "Add Contact",
                    help: "Spend BP for this contact",
                    isEnabled: !draftContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && draft.canAddContact(
                            connection: draftContactConnection,
                            loyalty: draftContactLoyalty
                        )
                ) {
                    let name = draftContactName.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.addContact(
                        Contact(
                            name: name,
                            role: draftContactRole.trimmingCharacters(in: .whitespacesAndNewlines),
                            loyalty: draftContactLoyalty,
                            connection: draftContactConnection
                        )
                    )
                    draftContactName = ""
                }
            }
            .onAppear {
                catalog.ensureLoaded(for: draft.edition)
                if !contactRoleOptions.contains(draftContactRole), let first = contactRoleOptions.first {
                    draftContactRole = first
                }
            }
        }
    }

    private func toggleQuality(_ item: (String, String, QualityKind, Int), on: Bool) {
        if on {
            guard draft.canAddQuality(kind: item.2, karmaValue: item.3) else { return }
            if draft.generationSystem == .buildPoints {
                draft.qualities.append(
                    QualityInstance(catalogKey: item.0, name: item.1, kind: item.2, karmaValue: item.3)
                )
                draft.recomputeBuildPoints()
                return
            }
            if item.2 == .positive {
                let next = draft.budget.positiveQualityKarmaUsed + item.3
                guard next <= draft.budget.positiveQualityKarmaCap else { return }
                draft.budget.positiveQualityKarmaUsed = next
            } else {
                let next = draft.budget.negativeQualityKarmaGained + item.3
                guard next <= draft.budget.negativeQualityKarmaCap else { return }
                draft.budget.negativeQualityKarmaGained = next
                draft.budget.karmaRemaining += item.3
            }
            draft.qualities.append(
                QualityInstance(catalogKey: item.0, name: item.1, kind: item.2, karmaValue: item.3)
            )
        } else {
            draft.qualities.removeAll { $0.catalogKey == item.0 }
            if draft.generationSystem == .buildPoints {
                draft.recomputeBuildPoints()
                return
            }
            if item.2 == .positive {
                draft.budget.positiveQualityKarmaUsed = max(0, draft.budget.positiveQualityKarmaUsed - item.3)
            } else {
                draft.budget.negativeQualityKarmaGained = max(0, draft.budget.negativeQualityKarmaGained - item.3)
                draft.budget.karmaRemaining = max(0, draft.budget.karmaRemaining - item.3)
            }
        }
    }

    // MARK: - Resources

    private var resourcesStep: some View {
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
    private var maxResourceBPAffordable: Int {
        draft.buildPointLedger.resources + max(0, draft.budget.buildPointsRemaining)
    }

    private var currentResourceBP: Int {
        SR4BuildPointEngine.resourceCost(nuyen: draft.nuyen)
    }

    private func setResourceBP(_ bp: Int) {
        let clamped = max(0, min(bp, maxResourceBPAffordable))
        draft.setNuyenForBuildPoints(SR4BuildPointEngine.nuyenForBuildPoints(clamped))
        syncResourceBPText()
    }

    private func syncResourceBPText() {
        resourceBPText = "\(currentResourceBP)"
    }

    private var sr4NuyenBPControls: some View {
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

    private func resourceBPPresetButton(_ title: String, bp: Int) -> some View {
        AppChromeButton.title(title, help: "Set resource spend to \(bp) BP") {
            setResourceBP(bp)
        }
    }

    private func commitResourceBPText() {
        let trimmed = resourceBPText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            syncResourceBPText()
            return
        }
        setResourceBP(value)
    }

    // MARK: Priority (SR5/SR6) resources summary

    /// Keep cash on hand equal to the full Resources priority grant (no voluntary underspend).
    private func ensurePriorityNuyenIsFullGrant() {
        guard draft.generationSystem != .buildPoints else { return }
        let grant = draft.budget.nuyenTotal
        if draft.nuyen != grant {
            draft.nuyen = grant
        }
        draft.budget.nuyenRemaining = 0
    }

    private var priorityResourcesSummary: some View {
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
    private var contactRoleOptions: [String] {
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

    private var finishStep: some View {
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

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.title = "Choose Portrait"
        panel.message = "Choose a portrait image for this runner"
        panel.prompt = "Use Image"
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .heic, .tiff]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                avatarImportError = "Selected image was empty."
                return
            }
            guard data.count < 8 * 1024 * 1024 else {
                avatarImportError = "Image must be under 8 MB."
                return
            }
            guard NSImage(data: data) != nil else {
                avatarImportError = "Could not read that file as an image."
                return
            }
            draft.avatarData = data
            avatarImportError = nil
        } catch {
            avatarImportError = error.localizedDescription
        }
    }

    private func requestCancel() {
        // Confirm only after the user has moved past the first step or entered a name.
        let hasProgress = draft.step != .edition
            || !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.houseRules.enabled.isEmpty == false && draft.houseRules != .coreBook
        if hasProgress {
            confirmCancel = true
        } else {
            onCancel?()
        }
    }

    private func saveCharacter() {
        do {
            let character = draft.buildCharacter()
            try libraryEnvironment.library.save(character, avatarData: draft.avatarData)
            didFinish = true
            statusMessage = "Saved \(character.displayTitle)."
            onFinished?()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    GenerationWizardView()
        .environment(LibraryEnvironment.preview(seedSamples: false))
        .frame(width: 1000, height: 760)
}
