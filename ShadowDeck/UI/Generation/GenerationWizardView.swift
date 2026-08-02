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
    @State private var draft = GenerationDraft()
    @State private var statusMessage: String?
    @State private var didFinish = false
    @State private var avatarImportError: String?
    @State private var scrollAnchor = UUID()
    @State private var showHouseRulesBrowser = false
    @State private var confirmCancel = false
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
            HStack(spacing: 6) {
                ForEach(draft.steps) { step in
                    Circle()
                        .fill(step == draft.step ? Color.accentColor : (step < draft.step ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25)))
                        .frame(width: 8, height: 8)
                        .help(step.title)
                }
            }
            Button("Cancel", role: .cancel) {
                requestCancel()
            }
            .keyboardShortcut(.cancelAction)
            .help("Leave without saving this character")
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
            Button("Cancel", role: .cancel) {
                requestCancel()
            }
            Button("Back") { draft.goBack() }
                .disabled(draft.step == .edition)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if draft.step == .finish {
                Button("Save Character") { saveCharacter() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canGoNext || didFinish)
            } else {
                Button("Continue") { draft.goNext() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canGoNext)
            }
        }
        .padding(16)
    }

    // MARK: - Edition

    private var editionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Edition")
                .font(.title3.weight(.semibold))
            HelpCallout(text: "ShadowDeck treats 4th, 5th, and 6th edition as equal peers. Generation rules (priority tables, limits, Edge) adapt to your choice.")

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
                    Button("Configure…") {
                        showHouseRulesBrowser = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
            HelpCallout(text: "Pick a runner role (playstyle archetype). This is not a mechanical character class—it guides recommendations and your default Magic/Resonance path.")

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Metatype")
                .font(.title3.weight(.semibold))
            HelpCallout(text: "Your metatype sets natural minimum and maximum scores for attributes. Body and Edge are especially important for every runner:")

            HStack(spacing: 12) {
                attributeChip(id: .body, short: "BOD")
                attributeChip(id: .edge, short: "EDG")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(MetatypeID.allCases) { meta in
                    let profile = MetatypeCatalog.profile(for: meta, edition: draft.edition)
                    let selected = draft.metatype == meta
                    Button {
                        draft.selectMetatype(meta)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PaintedPortraitView(kind: .metatype(meta), cornerRadius: 8, showLabel: false)
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .contentShape(Rectangle())
                            Text(meta.displayName)
                                .font(.headline)
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
            Text(draft.generationSystem == .buildPoints ? "Build Points" : "Priorities")
                .font(.title3.weight(.semibold))

            if draft.generationSystem == .buildPoints {
                HelpCallout(text: "SR4 uses Build Points. This wizard uses simplified attribute/skill pools for guidance; full BP accounting expands later.")
            } else {
                HelpCallout(text: draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen)
                    ? "Assign priority letters so their values sum to 10 (A=4, B=3, C=2, D=1, E=0). Duplicates are allowed. Watch the balance banner above as you click."
                    : "Assign each of A–E exactly once across the five columns. The balance banner above updates as you choose.")

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
                    ).first { $0.column == column && $0.letter == letter }

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

            RecommendButton(
                title: "Apply Recommended Attributes",
                subtitle: ChargenRecommendations.attributes(
                    archetype: draft.archetype,
                    metatype: draft.metatype,
                    edition: draft.edition,
                    pointBudget: draft.budget.attributePointsTotal
                ).rationale
            ) {
                draft.applyRecommendedAttributes()
            }

            sectionCard(title: "Physical & Mental") {
                ForEach(AttributeID.standardGenerationAttributes, id: \.self) { id in
                    attributeRow(id)
                }
            }

            if draft.budget.specialPointsTotal > 0 || draft.awakened != .mundane {
                sectionCard(title: "Special (Edge, Magic, Resonance)") {
                    Text(ChargenHelpCatalog.specialAdjustmentPointsHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            HelpCallout(text: "Your path decides whether you use Magic, Resonance, or neither. Mundane is the normal state for most runners—no spells, no complex forms—just skills, Edge, and gear.")

            ForEach(AwakenedPath.allCases, id: \.self) { path in
                let selected = draft.awakened == path
                Button {
                    draft.awakened = path
                    if path.usesMagic && draft.attributes.magic < 1 { draft.attributes.magic = 1 }
                    if path.usesResonance && draft.attributes.resonance < 1 { draft.attributes.resonance = 1 }
                    if path == .mundane {
                        draft.attributes.magic = 0
                        draft.attributes.resonance = 0
                    }
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
        }
    }

    // MARK: - Skills

    private var skillsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skills")
                .font(.title3.weight(.semibold))
            HelpCallout(text: "Skills plus linked attributes form dice pools. Recommendations match your role; adjust any rank afterward.")
            if draft.freeKnowledgePool > 0 {
                HelpCallout(text: "House rule: \(draft.freeKnowledgePool) free Knowledge/Language ranks (not spent from the active skill pool above). Track them on the Skills tab after creation if needed.")
            }

            RecommendButton(
                title: "Apply Recommended Skills",
                subtitle: ChargenRecommendations.skills(
                    archetype: draft.archetype,
                    pointBudget: draft.budget.skillPointsTotal
                ).rationale
            ) {
                draft.applyRecommendedSkills()
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

            let starters: [(String, String, QualityKind, Int)] = [
                ("toughness", "Toughness", .positive, 10),
                ("guts", "Guts", .positive, 10),
                ("first_impression", "First Impression", .positive, 11),
                ("sinner", "SINner (National)", .negative, 5),
                ("allergy", "Allergy (Common, Mild)", .negative, 10),
                ("distinctive", "Distinctive Style", .negative, 5),
            ]

            ForEach(starters, id: \.0) { item in
                let selected = draft.qualities.contains { $0.catalogKey == item.0 }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { selected },
                        set: { on in toggleQuality(item, on: on) }
                    )) {
                        Text("\(item.1) (\(item.2 == .positive ? "costs" : "grants") \(item.3) Karma)")
                            .font(.body.weight(.medium))
                    }
                    Text(ChargenHelpCatalog.qualityDescription(catalogKey: item.0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func toggleQuality(_ item: (String, String, QualityKind, Int), on: Bool) {
        if on {
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
            HelpCallout(text: ChargenHelpCatalog.resourcesHelp)

            LabeledContent("Nuyen from Resources priority", value: "¥\(draft.budget.nuyenTotal)")
            Stepper(value: $draft.nuyen, in: 0...max(draft.budget.nuyenTotal, draft.nuyen), step: 500) {
                Text("Cash on hand: ¥\(draft.nuyen)")
            }
            .onChange(of: draft.nuyen) { _, newValue in
                draft.budget.nuyenRemaining = max(0, draft.budget.nuyenTotal - newValue)
            }
        }
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

                Button("Choose Portrait…") { pickAvatar() }
                if draft.avatarData != nil {
                    Button("Use Role Art Instead", role: .destructive) {
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
                        LabeledContent("Attributes spent", value: "\(draft.budget.attributePointsSpent) / \(draft.budget.attributePointsTotal)")
                        LabeledContent("Skills spent", value: "\(draft.budget.skillPointsSpent) / \(draft.budget.skillPointsTotal)")
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
                        if draft.contactPointPool > 0 {
                            LabeledContent("Contact points", value: "\(draft.contactPointPool)")
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
