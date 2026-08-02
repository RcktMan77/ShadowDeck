//
//  CharacterAtAGlanceView.swift
//  ShadowDeck
//
//  Phase 5–6 — character workspace: interactive summary + detailed management tabs.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CharacterAtAGlanceView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let characterID: UUID
    var onBack: () -> Void
    var onDeleted: () -> Void

    @State private var character: Character?
    @State private var sheetTab: CharacterSheetTab = .summary
    @State private var notesDraft: String = ""
    @State private var conceptDraft: String = ""
    @State private var backgroundDraft: String = ""
    @State private var isEditingStory = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isPortraitImporterPresented = false
    @State private var confirmDeletePresented = false
    @State private var showHouseRulesBrowser = false
    @State private var showExportOptions = false
    /// Session-only stack of Summary-sheet manual karma awards (amounts). Pop to undo last `+`.
    @State private var manualKarmaAwardStack: [Int] = []
    @StateObject private var diceRoller = DiceRollerController()
    @Environment(\.openWindow) private var openWindow

    private var rules: any EditionRules {
        RulesRegistry.rules(for: character?.edition ?? .sr5)
    }

    private var derived: DerivedStats {
        guard let character else {
            return DerivedStats()
        }
        return rules.deriveStats(for: character)
    }

    var body: some View {
        Group {
            if character != nil {
                workspace
            } else {
                ProgressView("Loading character…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reload() }
        .onChange(of: characterID) { _, _ in
            sheetTab = .summary
            diceRoller.dismiss()
            manualKarmaAwardStack = []
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.characterSheetShowAdvanceTab)) { _ in
            sheetTab = .advance
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.marketingReloadCharacter)) { _ in
            reload()
            sheetTab = .advance
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openDiceRoller)) { _ in
            openDiceRollerManual()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.marketingShowDiceRoller)) { _ in
            prepareMarketingDiceRoller()
        }
        .fileImporter(
            isPresented: $isPortraitImporterPresented,
            allowedContentTypes: [.image, .png, .jpeg, .gif, .webP, .heic, .tiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                applyPortrait(from: url)
            case .failure(let error):
                errorMessage = "Portrait picker failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Workspace (tabs)

    private var workspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
            if let c = character {
                toolbar(c)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                Picker(selection: $sheetTab) {
                    ForEach(CharacterSheetTab.tabs(for: c.awakened)) { tab in
                        Text(tab.title).tag(tab)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)
                }

                if sheetTab == .summary {
                    validationBanner(for: c)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 6)
                }

                Divider()

                Group {
                    switch sheetTab {
                    case .summary:
                        dashboard(c)
                    case .skills:
                        SkillsManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { skill in openDiceRoller(skill: skill) }
                    case .gear:
                        GearManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { statusMessage = $0 }
                    case .augmentations:
                        AugmentationsManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { statusMessage = $0 }
                    case .qualities:
                        QualitiesManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { statusMessage = $0 }
                    case .contacts:
                        ContactsManagementView(character: binding(to: c), onPersist: persistCharacter)
                    case .lifestyle:
                        LifestyleManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { statusMessage = $0 }
                    case .advance:
                        AdvancementPlannerView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { statusMessage = $0 }
                    case .magic:
                        MagicManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter
                        ) { statusMessage = $0 }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(sheetTab) // tear down management views cleanly when switching tabs
            }
            } // end main column VStack

            if diceRoller.isPresented {
                Divider()
                DiceRollerPanel(controller: diceRoller) {
                    diceRoller.dismiss()
                }
                .frame(width: 320)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: diceRoller.isPresented)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Dice roller

    private func openDiceRollerManual() {
        guard let c = character else { return }
        diceRoller.presentManual(character: c)
    }

    /// Opens the dedicated Rules Reference window (not a trailing inspector).
    private func openRulesReference(query: String? = nil) {
        RulesReferenceOpener.open(
            query: query,
            edition: character?.edition,
            character: character,
            openWindow: openWindow
        )
    }

    /// Marquee still: Skills tab, roller open after a skill roll, Edge options visible.
    private func prepareMarketingDiceRoller() {
        guard let c = character else { return }
        sheetTab = .skills
        let skill = c.skills
            .filter { $0.category == .active && $0.rating > 0 }
            .max { $0.rating < $1.rating }
            ?? c.skills.first
        if let skill {
            openDiceRoller(skill: skill)
        } else {
            openDiceRollerManual()
        }
        // Let the inspector open, then roll so result + Second Chance chrome appear.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            diceRoller.roll()
            // Leave Edge remaining so Push / Second Chance options read as available.
            if diceRoller.edgeRemaining == 0, diceRoller.edgeRating > 0 {
                diceRoller.refreshEdge()
            }
        }
    }

    private func openDiceRoller(skill: SkillRating) {
        guard let c = character else { return }
        let resolved = DicePoolResolver.skillPool(character: c, skill: skill)
        diceRoller.present(
            request: DiceRollRequest(
                pool: resolved.pool,
                edition: c.edition,
                sourceLabel: resolved.label,
                edgeRating: DicePoolResolver.edgeRating(character: c)
            ),
            characterID: c.id,
            diceRules: c.houseRules.resolvedDice
        )
    }

    private func openDiceRoller(attribute: AttributeID) {
        guard let c = character else { return }
        let resolved = DicePoolResolver.attributePool(character: c, attribute: attribute)
        diceRoller.present(
            request: DiceRollRequest(
                pool: resolved.pool,
                edition: c.edition,
                sourceLabel: resolved.label,
                edgeRating: DicePoolResolver.edgeRating(character: c)
            ),
            characterID: c.id,
            diceRules: c.houseRules.resolvedDice
        )
    }

    /// Safe binding — never force-unwraps optional `character`.
    private func binding(to fallback: Character) -> Binding<Character> {
        Binding(
            get: { character ?? fallback },
            set: { character = $0 }
        )
    }

    private func persistCharacter() {
        guard var c = character else { return }
        c.touch()
        do {
            try libraryEnvironment.library.save(c)
            // Keep local state as source of truth so in-progress UI (disclosure,
            // notes editing) is not reset by a full re-fetch mid-keystroke.
            character = c
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Validation (Phase 8)

    @ViewBuilder
    private func validationBanner(for c: Character) -> some View {
        let result = rules.validate(c)
        let errors = result.errors
        let warnings = result.warnings
        if !errors.isEmpty || !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !errors.isEmpty {
                    Label(
                        "\(errors.count) validation issue\(errors.count == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    ForEach(errors.prefix(4)) { issue in
                        Text("• \(issue.message)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if errors.count > 4 {
                        Text("…and \(errors.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else if !warnings.isEmpty {
                    Label(
                        "\(warnings.count) note\(warnings.count == 1 ? "" : "s")",
                        systemImage: "info.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(warnings.prefix(3)) { issue in
                        Text("• \(issue.message)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(!errors.isEmpty ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08))
            )
        }
    }

    // MARK: - Summary dashboard

    private func dashboard(_ c: Character) -> some View {
        // Single sheet scroll — Notes is the last section so it doesn't steal vertical chrome.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Identity header: name + chips, then concept/background above the sheet body
                VStack(alignment: .leading, spacing: 12) {
                    CharacterGlanceIdentityHeader(
                        character: c,
                        houseRulesLabel: c.houseRules.enabled.isEmpty
                            ? "Core book rules"
                            : "\(c.houseRules.enabled.count) house rules"
                    ) { showHouseRulesBrowser = true }
                    .sheet(isPresented: $showHouseRulesBrowser) {
                        HouseRulesBrowserView(
                            houseRules: Binding(
                                get: { character?.houseRules ?? .coreBook },
                                set: { newRules in
                                    updateCharacter({ $0.houseRules = newRules }, status: "House rules updated.")
                                }
                            ),
                            editionBaselineKarma: rules.standardPriorityKarma,
                            onApply: {
                                showHouseRulesBrowser = false
                                statusMessage = "House rules updated — validation & essence use the new set."
                            },
                            onCancel: { showHouseRulesBrowser = false }
                        )
                    }
                    CharacterGlanceStorySection(
                        character: c,
                        isEditing: $isEditingStory,
                        conceptDraft: $conceptDraft,
                        backgroundDraft: $backgroundDraft,
                        onBeginEdit: {
                            conceptDraft = c.concept
                            backgroundDraft = resolvedBackground(for: c)
                            isEditingStory = true
                        },
                        onCancel: { isEditingStory = false },
                        onSave: { commitStory() }
                    )
                }

                // Hero: portrait | attributes — bottoms aligned (caption baseline ≈ card edge).
                // Portrait is intentionally large; attributes stay compact so they share a baseline.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 18) {
                        CharacterGlancePortraitColumn(character: c) {
                            isPortraitImporterPresented = true
                        }
                        CharacterGlanceAttributesColumn(
                            character: c,
                            essenceDisplay: essenceString(c),
                            onAdjust: { adjustAttribute($0, by: $1) },
                            onRoll: { openDiceRoller(attribute: $0) }
                        )
                        .frame(
                            maxWidth: CharacterGlancePortraitMetrics.attributesMaxWidth,
                            alignment: .leading
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 16) {
                        CharacterGlancePortraitColumn(character: c) {
                            isPortraitImporterPresented = true
                        }
                        CharacterGlanceAttributesColumn(
                            character: c,
                            essenceDisplay: essenceString(c),
                            onAdjust: { adjustAttribute($0, by: $1) },
                            onRoll: { openDiceRoller(attribute: $0) }
                        )
                        .frame(
                            maxWidth: CharacterGlancePortraitMetrics.attributesMaxWidth,
                            alignment: .leading
                        )
                    }
                }

                // Resource vitals (Karma, Nuyen, …)
                CharacterGlanceVitalsGrid(
                    character: c,
                    derived: derived,
                    canUndoKarma: !manualKarmaAwardStack.isEmpty,
                    onAwardKarma: { advanceKarma(by: 1) },
                    onAwardKarmaFive: { advanceKarma(by: 5) },
                    onUndoKarma: { undoLastManualKarmaAward() }
                )

                CharacterGlanceLifestyleBanner(character: c)

                // Combat readiness
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        CharacterGlanceConditionCard(
                            physicalDamage: derived.condition.physicalFilled,
                            physicalBoxes: derived.condition.physicalBoxes,
                            stunDamage: derived.condition.stunFilled,
                            stunBoxes: derived.condition.stunBoxes,
                            overflowBoxes: derived.condition.overflowBoxes,
                            onPhysicalSelect: { setPhysicalDamage($0 + 1) },
                            onPhysicalClear: { setPhysicalDamage(0) },
                            onStunSelect: { setStunDamage($0 + 1) },
                            onStunClear: { setStunDamage(0) }
                        )
                        .frame(maxWidth: .infinity)
                        initiativeCard(c).frame(maxWidth: .infinity)
                        limitsCard(c).frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 12) {
                        CharacterGlanceConditionCard(
                            physicalDamage: derived.condition.physicalFilled,
                            physicalBoxes: derived.condition.physicalBoxes,
                            stunDamage: derived.condition.stunFilled,
                            stunBoxes: derived.condition.stunBoxes,
                            overflowBoxes: derived.condition.overflowBoxes,
                            onPhysicalSelect: { setPhysicalDamage($0 + 1) },
                            onPhysicalClear: { setPhysicalDamage(0) },
                            onStunSelect: { setStunDamage($0 + 1) },
                            onStunClear: { setStunDamage(0) }
                        )
                        initiativeCard(c)
                        limitsCard(c)
                    }
                }

                // Skills & qualities (previews — full editors on other tabs)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        skillsCard(c).frame(maxWidth: .infinity, alignment: .topLeading)
                        qualitiesCard(c).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    VStack(spacing: 12) {
                        skillsCard(c)
                        qualitiesCard(c)
                    }
                }

                // Notes last — editor has its own scroll for long logs
                notesSection(c)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
        }
    }

    // MARK: - Toolbar

    private func toolbar(_ c: Character) -> some View {
        HStack(spacing: 12) {
            Button {
                onBack()
            } label: {
                Label("Library", systemImage: "chevron.left")
            }

            Spacer()

            Button {
                if diceRoller.isPresented {
                    diceRoller.dismiss()
                } else {
                    openDiceRollerManual()
                }
            } label: {
                Label(
                    diceRoller.isPresented ? "Hide Dice" : "Dice",
                    systemImage: "dice.fill"
                )
            }
            .help("Open dice roller (⌘D)")
            .keyboardShortcut("d", modifiers: [.command])
            .accessibilityLabel(diceRoller.isPresented ? "Hide dice roller" : "Open dice roller")

            Button {
                openRulesReference()
            } label: {
                Label("Rules", systemImage: "book.pages.fill")
            }
            .help("Open Rules Reference window (⌘R)")
            .accessibilityLabel("Open Rules Reference")
            .keyboardShortcut("r", modifiers: [.command])

            Button("Export…", systemImage: "square.and.arrow.up") {
                showExportOptions = true
            }
            .help("Export package, PDF character sheet, or Chummer .chum5")
            .confirmationDialog(
                "Export \(c.displayTitle)",
                isPresented: $showExportOptions,
                titleVisibility: .visible
            ) {
                Button("ShadowDeck Package…") { exportPackage() }
                Button("PDF Character Sheet…") { exportPDFSheet() }
                Button("Chummer .chum5…") { exportChummer() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a format for GMs, backups, or online hubs.")
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                confirmDeletePresented = true
            }
            .confirmationDialog(
                "Delete this character?",
                isPresented: $confirmDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete \(c.displayTitle)", role: .destructive) {
                    deleteCharacter()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("“\(c.displayTitle)” will be removed from your library. This cannot be undone.")
            }
        }
    }

    /// Prefer dedicated background; fall back to legacy “Background\n…” block in notes.
    private func resolvedBackground(for c: Character) -> String {
        if let bg = c.background?.trimmingCharacters(in: .whitespacesAndNewlines), !bg.isEmpty {
            return bg
        }
        return CharacterGlanceStorySection.extractLegacyBackground(from: c.notes) ?? ""
    }

    // MARK: - Notes (end of sheet)

    private func notesSection(_ c: Character) -> some View {
        sectionCard("Notes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mission logs & table notes — scroll inside the editor for long text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save Notes") {
                        commitNotesIfNeeded(force: true)
                    }
                    .controlSize(.small)
                }

                NotesEditor(text: $notesDraft) {
                    commitNotesIfNeeded()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
    }

    private func initiativeCard(_ c: Character) -> some View {
        let eff = c.effectiveAttributes
        let effects = c.effects
        return sectionCard("Initiative") {
            VStack(alignment: .leading, spacing: 8) {
                Text(initiativeString(c))
                    .font(.title.monospacedDigit().weight(.semibold))
                Text("Reaction \(eff.reaction) + Intuition \(eff.intuition)"
                    + (effects.initiativeBonus != 0
                        ? " \(effects.initiativeBonus >= 0 ? "+" : "")\(effects.initiativeBonus)"
                        : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(initiativeDiceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                statRow("Armor", "\(derived.armor)")
                Divider()
                // Same right-aligned value style as Limits.
                statRow("Composure", "\(derived.composure)")
                statRow("Judge Intentions", "\(derived.judgeIntentions)")
                statRow("Memory", "\(derived.memory)")
            }
        }
    }

    @ViewBuilder
    private func limitsCard(_ c: Character) -> some View {
        sectionCard(c.edition.usesLimits ? "Limits" : "Derived") {
            if c.edition.usesLimits {
                VStack(alignment: .leading, spacing: 8) {
                    statRow("Physical", derived.physicalLimit.map(String.init) ?? "—")
                    statRow("Mental", derived.mentalLimit.map(String.init) ?? "—")
                    statRow("Social", derived.socialLimit.map(String.init) ?? "—")
                    Text("SR5-style limits cap dice used on related tests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    statRow("Armor", "\(derived.armor)")
                    statRow("Walk / Run", "\(derived.movementWalk) / \(derived.movementRun)")
                    if c.edition.usesSessionEdgePool {
                        Text("SR6: Edge is a session pool that refreshes between encounters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This edition does not use classic Physical/Mental/Social limits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Shared label/value row: title left, value right-aligned with consistent emphasis.
    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private func skillsCard(_ c: Character) -> some View {
        let top = c.skills
            .filter { $0.rating > 0 }
            .sorted { $0.rating > $1.rating }
            .prefix(10)

        return sectionCard("Key Skills") {
            if top.isEmpty {
                Text("No skills recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(top)) { skill in
                        HStack(spacing: 8) {
                            Text(skill.displayName)
                            if skill.category != .active {
                                Text(skill.category == .language ? "Language" : "Knowledge")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                            if let spec = skill.specialized, !spec.isEmpty {
                                Text("(\(spec))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("\(skill.rating)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .frame(width: 24, alignment: .trailing)
                            // Always reserve space so knowledge skills align with actives.
                            Text(poolLabel(for: skill))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                    Text("Pool = linked attribute + skill rank (+ gear/quality bonuses). Knowledge uses Logic or Intuition by type.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Open the Skills tab for the full list and editing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Dice pool string for Summary alignment (always same width).
    private func poolLabel(for skill: SkillRating) -> String {
        if let pool = derived.dicePools[skill.catalogKey] {
            return "pool \(pool)"
        }
        return "pool —"
    }

    private func qualitiesCard(_ c: Character) -> some View {
        sectionCard("Qualities") {
            if c.qualities.isEmpty {
                Text("No qualities recorded.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(c.qualities) { q in
                        HStack(alignment: .top) {
                            Image(systemName: q.kind == .positive ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(q.kind == .positive ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.name)
                                    .font(.callout.weight(.medium))
                                Text("\(q.kind == .positive ? "Cost" : "Bonus") \(q.karmaValue) Karma")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }

    private func attributeTile(_ title: String, value: String, editable: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Actions / mutations

    private func reload() {
        do {
            character = try libraryEnvironment.library.fetch(id: characterID)
            notesDraft = character?.notes ?? ""
            if let c = character {
                conceptDraft = c.concept
                backgroundDraft = resolvedBackground(for: c)
                // Lift legacy background out of notes once, if dedicated field is empty.
                // Defer save so we don't nest Observable/state publishes during onAppear.
                if c.background == nil || c.background?.isEmpty == true,
                   let legacy = CharacterGlanceStorySection.extractLegacyBackground(from: c.notes) {
                    Task { @MainActor in
                        self.updateCharacter { char in
                            char.background = legacy
                        }
                    }
                }
                errorMessage = nil
            } else {
                errorMessage = "Character not found."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitStory() {
        updateCharacter({ c in
            c.concept = conceptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let bg = backgroundDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            c.background = bg.isEmpty ? nil : bg
        }, status: "Story updated.")
        isEditingStory = false
    }

    private func updateCharacter(_ mutate: (inout Character) -> Void, status: String? = nil) {
        guard var c = character else { return }
        mutate(&c)
        c.touch()
        do {
            try libraryEnvironment.library.save(c)
            character = try libraryEnvironment.library.fetch(id: characterID)
            // Keep notes draft if we didn't intentionally change notes via editor.
            if let fresh = character, notesDraft != fresh.notes, status != nil {
                // no-op
            }
            if let status { statusMessage = status }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adjustAttribute(_ id: AttributeID, by delta: Int) {
        updateCharacter({ c in
            // Edit base only; effective = base + active modifiers.
            let next = c.attributes[id] + delta
            let bounds = rules.metatypeProfile(c.metatype).bounds(for: id)
            let maxAllowed = ValidationHelpers.augmentedAttributeMaximum(
                naturalMaximum: bounds.maximum,
                houseRules: c.houseRules
            )
            c.attributes[id] = min(max(next, bounds.minimum), maxAllowed)
        }, status: "\(id.displayName) base updated.")
    }

    private func setPhysicalDamage(_ damage: Int) {
        let maxBoxes = derived.condition.physicalBoxes
        updateCharacter({ c in
            var track = c.conditionTrack ?? ConditionTrack()
            track.setPhysicalDamage(damage, maxBoxes: maxBoxes)
            c.conditionTrack = track
        }, status: damage == 0 ? "Physical track cleared." : "Physical damage set to \(min(damage, maxBoxes)).")
    }

    private func setStunDamage(_ damage: Int) {
        let maxBoxes = derived.condition.stunBoxes
        updateCharacter({ c in
            var track = c.conditionTrack ?? ConditionTrack()
            track.setStunDamage(damage, maxBoxes: maxBoxes)
            c.conditionTrack = track
        }, status: damage == 0 ? "Stun track cleared." : "Stun damage set to \(min(damage, maxBoxes)).")
    }

    private func commitNotesIfNeeded(force: Bool = false) {
        guard var c = character else { return }
        guard force || c.notes != notesDraft else { return }
        c.notes = notesDraft
        c.touch()
        do {
            try libraryEnvironment.library.save(c)
            character = try libraryEnvironment.library.fetch(id: characterID)
            if force { statusMessage = "Notes saved." }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPortrait(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                errorMessage = "Selected image was empty."
                return
            }
            guard data.count < 8 * 1024 * 1024 else {
                errorMessage = "Image must be under 8 MB."
                return
            }
            guard NSImage(data: data) != nil else {
                errorMessage = "Could not read that file as an image."
                return
            }
            guard var c = character else { return }
            let ext = url.pathExtension.lowercased()
            c.avatar.inlineData = data
            c.avatar.mimeType = AvatarStoragePolicy.mimeType(forFileExtension: ext)
            // Prefer real multi-frame detection over extension alone (covers APNG / mislabeled files).
            c.avatar.isAnimated = GIFDecoder.isAnimatedImageData(data) || ext == "gif"
            c.touch()
            try libraryEnvironment.library.save(c, avatarData: data)
            character = try libraryEnvironment.library.fetch(id: characterID)
            statusMessage = "Portrait updated."
            errorMessage = nil
        } catch {
            errorMessage = "Portrait failed: \(error.localizedDescription)"
        }
    }

    private func exportPDFSheet() {
        guard let c = character else { return }
        let report = CampaignSheetReport.build(for: c)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = c.streetName.isEmpty ? c.name : c.streetName
        panel.nameFieldStringValue = "\(base.isEmpty ? "Runner" : base)_sheet.pdf"
        panel.canCreateDirectories = true
        panel.message = "Export a printable ShadowDeck character sheet (PDF)"
        panel.prompt = "Export PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CharacterSheetPDF.write(report: report, to: url)
            let ready = report.isCampaignReady ? "validated" : "with validation notes"
            statusMessage = "Exported PDF sheet (\(ready))."
            errorMessage = nil
        } catch {
            errorMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }

    private func exportChummer() {
        guard let c = character else { return }
        let hasOriginal = c.importProvenance?.originalPayload != nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "chum5") ?? .xml]
        let base = c.streetName.isEmpty ? c.name : c.streetName
        panel.nameFieldStringValue = "\(base.isEmpty ? "Runner" : base).chum5"
        panel.canCreateDirectories = true
        panel.message = hasOriginal
            ? "Export Chummer .chum5 — uses the original imported file when available (faithful)."
            : "Best-effort regenerated Chummer .chum5 (not full Chummer parity)."
        panel.prompt = "Export .chum5"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try ChummerXMLExporter.export(c, mode: .preferOriginal)
            try result.xmlData.write(to: url, options: .atomic)
            if result.usedOriginalPayload {
                statusMessage = "Exported original Chummer file (byte-faithful import payload)."
            } else {
                statusMessage = "Exported regenerated Chummer file (\(result.fidelity.included.count) groups)."
            }
            errorMessage = nil
        } catch {
            errorMessage = "Chummer export failed: \(error.localizedDescription)"
        }
    }

    private func exportPackage() {
        guard character != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shadowdeckCharacter]
        panel.nameFieldStringValue = "\((character?.streetName.isEmpty == false ? character?.streetName : character?.name) ?? "Runner").\(ShadowDeckFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export a portable ShadowDeck character package"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try libraryEnvironment.library.exportPackage(id: characterID, to: url)
            statusMessage = "Exported \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advanceKarma(by amount: Int) {
        // Manual control is award-only; spending should happen via advancement purchases.
        guard amount > 0 else { return }
        updateCharacter({ c in
            c.karmaTotal += amount
            c.karmaAvailable += amount
        }, status: "Awarded \(amount) Karma.")
        manualKarmaAwardStack.append(amount)
    }

    /// Reverts the most recent Summary-sheet manual award (both available and total).
    /// Session-only — not a full karma history; Plan spends are not on this stack.
    private func undoLastManualKarmaAward() {
        guard let amount = manualKarmaAwardStack.popLast(), amount > 0 else { return }
        updateCharacter({ c in
            c.karmaTotal = max(0, c.karmaTotal - amount)
            c.karmaAvailable = max(0, c.karmaAvailable - amount)
            // Keep available from drifting above total if other edits intervened.
            if c.karmaAvailable > c.karmaTotal {
                c.karmaAvailable = c.karmaTotal
            }
        }, status: "Undid last karma award (−\(amount)).")
    }

    private func deleteCharacter() {
        do {
            try libraryEnvironment.library.delete(id: characterID)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func essenceString(_ c: Character) -> String {
        let ess = derived.currentEssence
        let n = NSDecimalNumber(decimal: ess)
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "\(ess)"
    }

    private func initiativeString(_ c: Character) -> String {
        "\(derived.initiativeBase) + \(derived.initiativeDice)D6"
    }

    private var initiativeDiceLabel: String {
        let n = derived.initiativeDice
        return n == 1 ? "1 Initiative Die" : "\(n) Initiative Dice"
    }

    private func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Chips

struct FlowChips: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

#Preview {
    CharacterAtAGlanceView(
        characterID: SampleCharacters.sr5ID,
        onBack: {},
        onDeleted: {}
    )
    .environment(LibraryEnvironment.preview())
    .frame(width: 1100, height: 860)
}
