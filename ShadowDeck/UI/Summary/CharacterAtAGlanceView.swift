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
                            onPersist: persistCharacter,
                            onRollSkill: { skill in openDiceRoller(skill: skill) }
                        )
                    case .gear:
                        GearManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter,
                            onStatus: { statusMessage = $0 }
                        )
                    case .augmentations:
                        AugmentationsManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter,
                            onStatus: { statusMessage = $0 }
                        )
                    case .qualities:
                        QualitiesManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter,
                            onStatus: { statusMessage = $0 }
                        )
                    case .contacts:
                        ContactsManagementView(character: binding(to: c), onPersist: persistCharacter)
                    case .lifestyle:
                        LifestyleManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter,
                            onStatus: { statusMessage = $0 }
                        )
                    case .advance:
                        AdvancementPlannerView(
                            character: binding(to: c),
                            onPersist: persistCharacter,
                            onStatus: { statusMessage = $0 }
                        )
                    case .magic:
                        MagicManagementView(
                            character: binding(to: c),
                            onPersist: persistCharacter,
                            onStatus: { statusMessage = $0 }
                        )
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

    /// Marquee still: Skills tab, roller open after a skill roll, Edge options visible.
    private func prepareMarketingDiceRoller() {
        guard let c = character else { return }
        sheetTab = .skills
        let skill = c.skills
            .filter { $0.category == .active && $0.rating > 0 }
            .sorted { $0.rating > $1.rating }
            .first
            ?? c.skills.first
        if let skill {
            openDiceRoller(skill: skill)
        } else {
            openDiceRollerManual()
        }
        // Let the inspector open, then roll so result + Second Chance chrome appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
                    identityColumn(c)
                    storySection(c)
                }

                // Hero: portrait | attributes — bottoms aligned (caption baseline ≈ card edge).
                // Portrait is intentionally large; attributes stay compact so they share a baseline.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 18) {
                        portraitColumn(c)
                        attributesColumn(c)
                            .frame(maxWidth: PortraitMetrics.attributesMaxWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 16) {
                        portraitColumn(c)
                        attributesColumn(c)
                            .frame(maxWidth: PortraitMetrics.attributesMaxWidth, alignment: .leading)
                    }
                }

                // Resource vitals (Karma, Nuyen, …)
                vitalsGrid(c)

                lifestyleBanner(c)

                // Combat readiness
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        conditionCard(c).frame(maxWidth: .infinity)
                        initiativeCard(c).frame(maxWidth: .infinity)
                        limitsCard(c).frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 12) {
                        conditionCard(c)
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

    // MARK: - Portrait

    /// Hero portrait sizing. Attributes max width keeps the grid compact so the portrait can grow.
    private enum PortraitMetrics {
        static let width: CGFloat = 280
        static let height: CGFloat = 350
        static let cornerRadius: CGFloat = 16
        /// Cap so attribute tiles stay dense; leftover width goes to the portrait, not empty tile padding.
        static let attributesMaxWidth: CGFloat = 440
    }

    private func portraitColumn(_ c: Character) -> some View {
        VStack(spacing: 8) {
            portraitView(c)
                .frame(width: PortraitMetrics.width, height: PortraitMetrics.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: PortraitMetrics.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PortraitMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: PortraitMetrics.cornerRadius, style: .continuous))
                .onTapGesture { isPortraitImporterPresented = true }
                .help("Click to change portrait")

            Button {
                isPortraitImporterPresented = true
            } label: {
                Label(
                    c.avatar.hasImage ? "Change Portrait…" : "Add Portrait…",
                    systemImage: "photo"
                )
            }
            .controlSize(.small)

            Text(c.avatar.hasImage
                 ? (c.avatar.isAnimated ? "Animated portrait" : "Custom portrait")
                 : "No custom portrait — showing placeholder")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: PortraitMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: PortraitMetrics.width, alignment: .bottom)
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private func portraitView(_ c: Character) -> some View {
        if let data = c.avatar.inlineData, !data.isEmpty {
            // Animated GIFs (and multi-frame APNG) need ImageIO playback;
            // SwiftUI Image(nsImage:) only shows the first frame.
            if c.avatar.isAnimated || GIFDecoder.isAnimatedImageData(data) {
                AnimatedImageView(data: data, contentMode: .fill)
            } else if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                portraitPlaceholder
            }
        } else if let meta = ChargenArtLoader.nsImage(named: ChargenArtLoader.metatypeImageName(c.metatype)) {
            Image(nsImage: meta)
                .resizable()
                .scaledToFill()
        } else {
            portraitPlaceholder
        }
    }

    private var portraitPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.secondary.opacity(0.2), .secondary.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Attributes (editable base; display effective)

    private func attributesColumn(_ c: Character) -> some View {
        let effects = c.effects
        // Three dense columns keep overall card height close to the large portrait + caption.
        let columns = [
            GridItem(.flexible(minimum: 96), spacing: 6),
            GridItem(.flexible(minimum: 96), spacing: 6),
            GridItem(.flexible(minimum: 96), spacing: 6),
        ]
        return sectionCard("Attributes") {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AttributeID.standardGenerationAttributes, id: \.self) { id in
                    editableAttributeTile(
                        id,
                        base: c.attributes[id],
                        bonus: effects.attributeBonus(for: id)
                    )
                }
                editableAttributeTile(
                    .edge,
                    base: c.attributes.edge,
                    bonus: effects.attributeBonus(for: .edge)
                )
                if c.awakened.usesMagic {
                    editableAttributeTile(
                        .magic,
                        base: c.attributes.magic,
                        bonus: effects.attributeBonus(for: .magic)
                    )
                }
                if c.awakened.usesResonance {
                    editableAttributeTile(
                        .resonance,
                        base: c.attributes.resonance,
                        bonus: effects.attributeBonus(for: .resonance)
                    )
                }
                attributeTile("Essence", value: essenceString(c), editable: false)
            }
            Text("± edits base rating. Bonuses from equipped gear, augs, qualities, and powers show as +N.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !effects.applied.isEmpty {
                DisclosureGroup("Active modifiers (\(effects.applied.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(effects.applied) { mod in
                            Text(mod.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
    }

    private func editableAttributeTile(_ id: AttributeID, base: Int, bonus: Int) -> some View {
        let effective = base + bonus
        return VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(id.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if id != .essence {
                    Button {
                        openDiceRoller(attribute: id)
                    } label: {
                        Image(systemName: "dice")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Roll \(id.displayName) (pool \(effective))")
                }
            }
            HStack(spacing: 4) {
                Button {
                    adjustAttribute(id, by: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    Text("\(effective)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 22)
                    if bonus != 0 {
                        Text(bonus > 0 ? "\(base)+\(bonus)" : "\(base)\(bonus)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                }

                Button {
                    adjustAttribute(id, by: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            (bonus != 0 ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .help(bonus != 0 ? "Base \(base), modifiers \(bonus >= 0 ? "+" : "")\(bonus)" : "Base \(base)")
    }

    // MARK: - Identity

    private func identityColumn(_ c: Character) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.displayTitle)
                .font(.largeTitle.weight(.bold))
                .textSelection(.enabled)

            HStack(alignment: .center, spacing: 12) {
                FlowChips(items: [
                    c.edition.shortName,
                    c.metatype.displayName,
                    c.awakened == .mundane ? "Mundane" : c.awakened.displayName,
                    c.generation.system.displayName,
                ])

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if c.houseRules.enabled.isEmpty {
                        Text("Core book rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(c.houseRules.enabled.count) house rules")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                    Button("House Rules…") {
                        showHouseRulesBrowser = true
                    }
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    @ViewBuilder
    private func lifestyleBanner(_ c: Character) -> some View {
        let burn = LifestyleTracker.burnSummary(for: c)
        if burn.activeCount > 0 {
            let status = burn.overallStatus
            let icon: String = {
                switch status {
                case .covered: "checkmark.seal.fill"
                case .due: "calendar.badge.exclamationmark"
                case .underfunded: "exclamationmark.triangle.fill"
                case .inactive: "house"
                }
            }()
            let color: Color = {
                switch status {
                case .covered: .green
                case .due: .orange
                case .underfunded: .red
                case .inactive: .secondary
                }
            }()
            let message: String = {
                switch status {
                case .covered:
                    return "Lifestyle covered — min \(burn.minimumPrepaidMonths) prepaid month(s). Burn ¥\(formatInt(burn.monthlyBurn))/mo."
                case .due:
                    return "Lifestyle due — ¥\(formatInt(burn.cashDue)) cash this process (reserve used first). Open the Lifestyle tab."
                case .underfunded:
                    return "Lifestyle underfunded — need ¥\(formatInt(burn.cashDue)), have ¥\(formatInt(burn.liquidity)) (nuyen + reserve)."
                case .inactive:
                    return "Lifestyle inactive."
                }
            }()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Resource / derived vitals — after portrait / attributes.
    private func vitalsGrid(_ c: Character) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                vital("Edge", "\(c.attributes.edge)", "bolt.fill")
                // Available = unspent; Total = career earned (including already spent).
                // + awards (total & available up); undo reverts the last manual award only.
                karmaAwardVital(
                    title: "Karma Available",
                    value: c.karmaAvailable,
                    systemImage: "sparkles",
                    canUndo: !manualKarmaAwardStack.isEmpty,
                    onAward: { advanceKarma(by: 1) },
                    onAwardFive: { advanceKarma(by: 5) },
                    onUndo: { undoLastManualKarmaAward() }
                )
                vital("Karma Total", "\(c.karmaTotal)", "chart.line.uptrend.xyaxis")
                vital("Nuyen", "¥\(formatInt(c.nuyen))", "yensign.circle.fill")
                vital(
                    "Lifestyle /mo",
                    "¥\(formatInt(LifestyleTracker.burnSummary(for: c).monthlyBurn))",
                    "house"
                )
                vital(
                    "Life. Reserve",
                    "¥\(formatInt(c.lifestyleNuyenReserve))",
                    "building.columns"
                )
                vital("Essence", essenceString(c), "heart.fill")
                vital("Armor", "\(derived.armor)", "shield.lefthalf.filled")
                vital("Initiative", initiativeString(c), "gauge.with.dots.needle.67percent")
                if let phys = derived.physicalLimit {
                    vital("Phys. Limit", "\(phys)", "shield")
                }
                vital("Contacts", "\(c.contacts.count)", "person.2")
                vital("Augmentations", "\(c.augmentations.count)", "cpu")
                if !c.adeptPowers.isEmpty {
                    vital("Adept Powers", "\(c.adeptPowers.count)", "bolt.heart")
                }
                if !c.spells.isEmpty {
                    vital("Spells", "\(c.spells.count)", "wand.and.stars")
                }
            }
            Text("Karma + awards 1 (available & total). Right‑click + to Award 5. Undo reverts the last manual award. Plan spends on the Advance tab.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Story / Background

    private func storySection(_ c: Character) -> some View {
        sectionCard("Concept & Background") {
            if isEditingStory {
                storyEditor
            } else {
                storyModeDisplay(c)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        conceptDraft = c.concept
                        backgroundDraft = resolvedBackground(for: c)
                        isEditingStory = true
                    }
                    .help("Click to edit concept and background")
            }
        }
    }

    private var storyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Concept")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Short tagline (e.g. Ex-Renraku coder adept)", text: $conceptDraft)
                .textFieldStyle(.roundedBorder)

            Text("Background")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $backgroundDraft)
                .font(.body)
                .frame(minHeight: 120, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    isEditingStory = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Save Story") {
                    commitStory()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func storyModeDisplay(_ c: Character) -> some View {
        let concept = c.concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let background = resolvedBackground(for: c)

        return VStack(alignment: .leading, spacing: 10) {
            if concept.isEmpty && background.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No concept or background yet")
                            .font(.callout.weight(.medium))
                        Text("Click to add a tagline and story blurb for this runner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                if !concept.isEmpty {
                    Text(concept)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if !background.isEmpty {
                    Text(background)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Text("Click to edit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prefer dedicated background; fall back to legacy “Background\\n…” block in notes.
    private func resolvedBackground(for c: Character) -> String {
        if let bg = c.background?.trimmingCharacters(in: .whitespacesAndNewlines), !bg.isEmpty {
            return bg
        }
        return Self.extractLegacyBackground(from: c.notes) ?? ""
    }

    private static func extractLegacyBackground(from notes: String) -> String? {
        // Older imports stuffed “Background\\n…” into notes.
        let plain = ChummerParsingHelpers.cleanRichText(notes)
        guard let range = plain.range(of: "Background", options: [.caseInsensitive, .anchored])
                ?? plain.range(of: "\nBackground\n", options: .caseInsensitive)
                ?? plain.range(of: "Background\n", options: .caseInsensitive)
        else {
            return nil
        }
        var rest = String(plain[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("\n") { rest = String(rest.dropFirst()) }
        // Stop at next major section if present.
        let cutMarkers = ["\nImported from Chummer", "\nPlayer:", "\nSRM ", "\nMale,", "\nFemale,"]
        var end = rest.endIndex
        for marker in cutMarkers {
            if let r = rest.range(of: marker) {
                end = min(end, r.lowerBound)
            }
        }
        let extracted = String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    private func vital(_ title: String, _ value: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Session karma awards only — spending happens when buying skills/augs/etc.
    private func karmaAwardVital(
        title: String,
        value: Int,
        systemImage: String,
        canUndo: Bool,
        onAward: @escaping () -> Void,
        onAwardFive: @escaping () -> Void,
        onUndo: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(value)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 24)

                    Button(action: onAward) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Award 1 Karma (available + total). Right-click for Award 5.")
                    .contextMenu {
                        Button("Award 1 Karma") { onAward() }
                        Button("Award 5 Karma") { onAwardFive() }
                        if canUndo {
                            Divider()
                            Button("Undo Last Award") { onUndo() }
                        }
                    }

                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canUndo ? .secondary : Color.secondary.opacity(0.35))
                    .disabled(!canUndo)
                    .help(
                        canUndo
                            ? "Undo last manual karma award (available + total)."
                            : "No manual karma award to undo this session."
                    )
                    .accessibilityLabel("Undo last karma award")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    // MARK: - Condition monitors (clickable)

    private func conditionCard(_ c: Character) -> some View {
        sectionCard("Condition Monitors") {
            VStack(alignment: .leading, spacing: 12) {
                monitorRow(
                    title: "Physical",
                    damage: derived.condition.physicalFilled,
                    boxes: derived.condition.physicalBoxes,
                    color: .green
                ) { boxIndex in
                    setPhysicalDamage(boxIndex + 1)
                } onClear: {
                    setPhysicalDamage(0)
                }

                monitorRow(
                    title: "Stun",
                    damage: derived.condition.stunFilled,
                    boxes: derived.condition.stunBoxes,
                    color: .green
                ) { boxIndex in
                    setStunDamage(boxIndex + 1)
                } onClear: {
                    setStunDamage(0)
                }

                Text("Click a box to fill through that mark (damage). Click Clear for healthy. Overflow capacity: \(derived.condition.overflowBoxes).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func monitorRow(
        title: String,
        damage: Int,
        boxes: Int,
        color: Color,
        onSelect: @escaping (Int) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        let remaining = max(0, boxes - damage)
        let status: String = {
            if boxes <= 0 { return "—" }
            if damage <= 0 { return "Healthy" }
            if remaining <= 0 { return "Filled" }
            return "\(remaining) open"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(damage) damage / \(boxes) boxes · \(status)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(damage > 0 ? color : .secondary)
                Button("Clear") { onClear() }
                    .controlSize(.mini)
                    .buttonStyle(.borderless)
            }
            let columns = Array(repeating: GridItem(.fixed(16), spacing: 3), count: min(max(boxes, 1), 18))
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<max(boxes, 0), id: \.self) { i in
                    let filled = i < damage
                    Button {
                        // Click box i → fill through that box (damage = i + 1).
                        // Re-click the last filled box to step damage down by one.
                        if damage == i + 1 {
                            if i == 0 {
                                onClear()
                            } else {
                                onSelect(i - 1)
                            }
                        } else {
                            onSelect(i)
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(filled ? color.opacity(0.9) : Color.secondary.opacity(0.15))
                            .frame(width: 16, height: 20)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Set damage through box \(i + 1)")
                }
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
                if (c.background == nil || c.background?.isEmpty == true),
                   let legacy = Self.extractLegacyBackground(from: c.notes)
                {
                    updateCharacter({ char in
                        char.background = legacy
                    })
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

private struct FlowChips: View {
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
