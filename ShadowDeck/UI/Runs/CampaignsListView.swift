//
//  CampaignsListView.swift
//  ShadowDeck
//
//  Campaign library list + campaign detail (runs under a campaign).
//

import SwiftUI

struct CampaignsListView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    /// When set, open this campaign detail immediately (e.g. Create → New Campaign).
    var forcedOpenCampaignID: UUID?
    /// Called after the forced open is applied so the parent can clear its token.
    var onOpenedForcedCampaign: (() -> Void)?

    @State private var summaries: [CampaignSummary] = []
    @State private var runSummaries: [RunSummary] = []
    @State private var selectedCampaignID: UUID?
    @State private var showArchived = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var campaignPendingDelete: CampaignSummary?
    @State private var openRunID: UUID?

    private var displayedCampaigns: [CampaignSummary] {
        summaries
    }

    var body: some View {
        Group {
            if let openRunID {
                RunDetailView(
                    runID: openRunID,
                    onBack: {
                        self.openRunID = nil
                        refresh()
                    },
                    onDeleted: {
                        self.openRunID = nil
                        refresh()
                    }
                )
            } else if let selectedCampaignID {
                CampaignDetailView(
                    campaignID: selectedCampaignID,
                    onBack: {
                        self.selectedCampaignID = nil
                        refresh()
                    },
                    onDeleted: {
                        self.selectedCampaignID = nil
                        refresh()
                    },
                    onOpenRun: { runID in
                        self.openRunID = runID
                    }
                )
                .id(selectedCampaignID)
            } else {
                listRoot
            }
        }
        .onAppear {
            refresh()
            applyForcedOpenIfNeeded()
        }
        .onChange(of: forcedOpenCampaignID) { _, _ in
            applyForcedOpenIfNeeded()
        }
    }

    private func applyForcedOpenIfNeeded() {
        guard let forcedOpenCampaignID else { return }
        selectedCampaignID = forcedOpenCampaignID
        openRunID = nil
        refresh()
        onOpenedForcedCampaign?()
    }

    private var listRoot: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Campaigns")
                    .font(.title2.weight(.semibold))
                Spacer()
                Toggle("Show archived", isOn: $showArchived)
                    .toggleStyle(.checkbox)
                    .onChange(of: showArchived) { _, _ in refresh() }
                AppChromeButton.labeled("Refresh", systemImage: "arrow.clockwise", help: "Reload campaigns") {
                    refresh()
                }
                AppChromeButton.labeled("New Campaign", systemImage: "plus.circle", help: "Create a new campaign") {
                    createCampaign()
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if displayedCampaigns.isEmpty {
                // Primary create path is Create → New Campaign (and the header button).
                // Avoid a third redundant action on the empty canvas (unlike Characters/Runs,
                // campaign creation is a single-purpose list with an always-visible toolbar).
                ContentUnavailableView {
                    Label(
                        showArchived ? "No Campaigns" : "No Active Campaigns",
                        systemImage: "folder"
                    )
                } description: {
                    Text(
                        showArchived
                            ? "Use Create → New Campaign or the New Campaign button above."
                            : "Use Create → New Campaign (or New Campaign above). Enable Show archived to see archived ones."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(displayedCampaigns) { summary in
                        campaignRow(summary)
                            .contextMenu {
                                Button("Open") { selectedCampaignID = summary.id }
                                if summary.isArchived {
                                    Button("Unarchive") { setArchived(summary.id, archived: false) }
                                } else {
                                    Button("Archive") { setArchived(summary.id, archived: true) }
                                }
                                Button("Delete…", role: .destructive) {
                                    campaignPendingDelete = summary
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Delete this campaign?",
            isPresented: Binding(
                get: { campaignPendingDelete != nil },
                set: { if !$0 { campaignPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: campaignPendingDelete
        ) { summary in
            Button("Delete \(summary.name)", role: .destructive) {
                deleteCampaign(summary.id)
                campaignPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { campaignPendingDelete = nil }
        } message: { summary in
            Text(
                "“\(summary.name)” will be removed. Its runs stay in the library as Unassigned — they are not deleted."
            )
        }
    }

    private func campaignRow(_ summary: CampaignSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Primary open target — leading content opens the editor.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.name)
                        .font(.headline)
                        .lineLimit(1)
                    RunEditionBadge(edition: summary.edition)
                    if summary.isArchived {
                        Text("Archived")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Label(
                        "\(summary.runCount) run\(summary.runCount == 1 ? "" : "s")",
                        systemImage: "list.clipboard"
                    )
                    if summary.activeRunCount > 0 {
                        Label(
                            "\(summary.activeRunCount) active",
                            systemImage: "bolt.fill"
                        )
                    }
                    if let last = summary.lastActivityAt {
                        Label(
                            "Last \(RunSupport.formatDate(last))",
                            systemImage: "clock"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selectedCampaignID = summary.id }

            // Explicit actions (same pattern as Run Library rows).
            HStack(spacing: 4) {
                Button {
                    selectedCampaignID = summary.id
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Edit campaign")

                Button {
                    campaignPendingDelete = summary
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Delete campaign")
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func refresh() {
        do {
            let campaigns = try libraryEnvironment.campaignLibrary.listSummaries(
                includeArchived: showArchived
            )
            runSummaries = try libraryEnvironment.runLibrary.listSummaries()
            summaries = campaigns.map { base in
                enrich(base, runs: runSummaries)
            }
            libraryEnvironment.refreshCampaignCount()
            libraryEnvironment.refreshRunCount()
            errorMessage = nil
            statusMessage = summaries.isEmpty
                ? nil
                : "\(summaries.count) campaign(s)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enrich(_ summary: CampaignSummary, runs: [RunSummary]) -> CampaignSummary {
        let mine = runs.filter { $0.campaignID == summary.id }
        let active = mine.filter { $0.status == .active || $0.status == .planning }.count
        let last = mine
            .flatMap { r -> [Date] in
                [r.completedAt, r.startedAt, r.plannedDate, r.modifiedAt].compactMap { $0 }
            }
            .max()
        return CampaignSummary(
            id: summary.id,
            name: summary.name,
            edition: summary.edition,
            isArchived: summary.isArchived,
            modifiedAt: summary.modifiedAt,
            createdAt: summary.createdAt,
            runCount: mine.count,
            activeRunCount: active,
            lastActivityAt: last ?? summary.modifiedAt
        )
    }

    private func createCampaign() {
        var campaign = Campaign.makeDraft(name: "New Campaign")
        let count = (try? libraryEnvironment.campaignLibrary.count(includeArchived: true)) ?? 0
        if count > 0 {
            campaign.name = "New Campaign \(count + 1)"
        }
        do {
            try libraryEnvironment.campaignLibrary.save(campaign)
            libraryEnvironment.refreshCampaignCount()
            refresh()
            selectedCampaignID = campaign.id
            statusMessage = "Created “\(campaign.name)”."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setArchived(_ id: UUID, archived: Bool) {
        do {
            var campaign = try libraryEnvironment.campaignLibrary.require(id)
            campaign.isArchived = archived
            try libraryEnvironment.campaignLibrary.save(campaign)
            libraryEnvironment.refreshCampaignCount()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCampaign(_ id: UUID) {
        do {
            try libraryEnvironment.deleteCampaignUnassigningRuns(id: id)
            if selectedCampaignID == id { selectedCampaignID = nil }
            refresh()
            statusMessage = "Campaign deleted. Runs moved to Unassigned."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Detail

struct CampaignDetailView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    let campaignID: UUID
    var onBack: () -> Void
    var onDeleted: () -> Void
    var onOpenRun: (UUID) -> Void

    @State private var campaign: Campaign?
    @State private var runs: [RunSummary] = []
    @State private var nameDraft = ""
    @State private var notesDraft = ""
    /// Selected catalog house-rule labels (display names) for this campaign’s hints.
    @State private var selectedHouseRuleLabels: [String] = []
    /// Free-text notes beyond the catalog chips.
    @State private var freeHouseRuleHints = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmDelete = false
    @State private var showAddRunsSheet = false
    @State private var showHouseRuleHintsSheet = false

    var body: some View {
        VStack(spacing: 0) {
            stickyToolbar
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

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

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if campaign != nil {
                        RunSectionCard(title: "Campaign") {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Name") {
                                    TextField("Campaign name", text: $nameDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 360)
                                        .onSubmit { commitIdentity(forceNotes: true) }
                                }
                                LabeledContent("Ruleset") {
                                    Picker("Ruleset", selection: editionBinding) {
                                        ForEach(Edition.allCases) { edition in
                                            Text(edition.shortName).tag(edition)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 280)
                                }
                                Text("New runs created here default to this ruleset.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                summaryChips

                                notesEditorBlock

                                houseRuleHintsBlock
                            }
                        }

                        RunSectionCard(title: "Runs") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(runs.count) run(s)")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Menu {
                                        Button("Create New Run") {
                                            createRunInCampaign()
                                        }
                                        Button("New Run from Template…") {
                                            NotificationCenter.default.post(
                                                name: AppCommand.newRunFromTemplate,
                                                object: nil,
                                                userInfo: ["campaignID": campaignID]
                                            )
                                        }
                                        Button("Add from Run Library…") {
                                            showAddRunsSheet = true
                                        }
                                    } label: {
                                        Label("Add Run", systemImage: "plus.circle")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("Create a run, start from a template, or attach existing runs")
                                }
                                if runs.isEmpty {
                                    Text("No runs assigned yet. Add jobs from your Run Library or create a new one.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(runs) { summary in
                                        HStack(spacing: 8) {
                                            Button {
                                                commitIdentity(forceNotes: true)
                                                onOpenRun(summary.id)
                                            } label: {
                                                HStack {
                                                    Text(summary.title)
                                                        .foregroundStyle(.primary)
                                                    Spacer()
                                                    RunStatusBadge(status: summary.status)
                                                    RunEditionBadge(edition: summary.edition)
                                                }
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                unassignRun(summary.id)
                                            } label: {
                                                Image(systemName: "xmark.circle")
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 28, height: 28)
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Remove from campaign (keeps the run as Unassigned)")
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView("Loading…")
                    }
                }
                .padding(24)
                .frame(maxWidth: 960, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            // Bottom-right save: flush drafts and return to Campaigns library.
            HStack {
                Spacer()
                AppChromeButton.title(
                    "Save",
                    help: "Save and return to Campaigns",
                    style: .prominent,
                    isEnabled: campaign != nil,
                    keyEquivalent: "s",
                    keyModifiers: .command
                ) {
                    saveAndReturn()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { load() }
        .onDisappear { commitIdentity(forceNotes: true) }
        .sheet(isPresented: $showAddRunsSheet) {
            AddRunsToCampaignSheet(
                campaignID: campaignID,
                campaignEdition: campaign?.edition ?? .sr5,
                alreadyAssignedIDs: Set(runs.map(\.id)),
                onCancel: { showAddRunsSheet = false },
                onAdded: {
                    showAddRunsSheet = false
                    load()
                    statusMessage = "Runs updated."
                }
            )
            .environment(libraryEnvironment)
        }
        .sheet(isPresented: $showHouseRuleHintsSheet) {
            HouseRuleHintsPickerSheet(
                selectedLabels: $selectedHouseRuleLabels,
                onDone: {
                    showHouseRuleHintsSheet = false
                    commitIdentity(forceNotes: true)
                }
            )
        }
        .confirmationDialog(
            "Delete this campaign?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Campaign", role: .destructive) {
                deleteCampaign()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs stay in the library as Unassigned. They are not deleted.")
        }
    }

    private var stickyToolbar: some View {
        HStack(spacing: 4) {
            AppChromeButton.labeled("Campaigns", systemImage: "chevron.left", help: "Back to Campaigns") {
                commitIdentity(forceNotes: true)
                onBack()
            }

            Text(nameDraft.isEmpty ? "Untitled Campaign" : nameDraft)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
                .help(nameDraft.isEmpty ? "Untitled Campaign" : nameDraft)

            Spacer(minLength: 8)

            // Tight trailing cluster (matches Character / Run detail toolbars).
            if let campaign {
                HStack(spacing: 4) {
                    if campaign.isArchived {
                        AppChromeButton.icon(
                            "tray.and.arrow.up",
                            help: "Unarchive this campaign"
                        ) {
                            setArchived(false)
                        }
                    } else {
                        AppChromeButton.icon(
                            "archivebox",
                            help: "Archive this campaign (hides from default list)"
                        ) {
                            setArchived(true)
                        }
                    }

                    AppChromeButton.icon(
                        "trash",
                        help: "Delete this campaign (runs become Unassigned)",
                        style: .destructive
                    ) {
                        confirmDelete = true
                    }
                }
            }
        }
    }

    private var notesEditorBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Private prep notes for this campaign.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            NotesEditor(text: $notesDraft) {
                commitIdentity(forceNotes: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
        }
    }

    private var houseRuleHintsBlock: some View {
        // Same chrome pattern as the Runs section header: title/caption left, action menu right.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("House-rule hints")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        "GM reminders for this table only — catalog picks and/or free text. Not applied to characters automatically."
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Menu {
                    Button("Choose from supported rules…") {
                        showHouseRuleHintsSheet = true
                    }
                } label: {
                    Label("Add Rules", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Pick from house rules ShadowDeck supports, then edit free text below")
            }

            if !selectedHouseRuleLabels.isEmpty {
                FlowHouseRuleChips(labels: selectedHouseRuleLabels) { label in
                    selectedHouseRuleLabels.removeAll { $0 == label }
                    commitIdentity(forceNotes: true)
                }
            }

            TextField("Free-text notes (optional)…", text: $freeHouseRuleHints, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onSubmit { commitIdentity(forceNotes: true) }
        }
    }

    private func saveAndReturn() {
        commitIdentity(forceNotes: true)
        onBack()
    }

    /// Compose catalog chips + free text into the single `houseRuleHints` storage string.
    private func composedHouseRuleHints() -> String {
        CampaignHouseRuleHintsCodec.encode(
            selectedLabels: selectedHouseRuleLabels,
            freeText: freeHouseRuleHints
        )
    }

    private func applyHouseRuleHints(from stored: String) {
        let parsed = CampaignHouseRuleHintsCodec.decode(stored)
        selectedHouseRuleLabels = parsed.selectedLabels
        freeHouseRuleHints = parsed.freeText
    }

    private var summaryChips: some View {
        let active = runs.filter { $0.status == .active || $0.status == .planning }.count
        let last = runs
            .flatMap { [$0.completedAt, $0.startedAt, $0.modifiedAt].compactMap { $0 } }
            .max()
        return HStack(spacing: 16) {
            Label("\(runs.count) total", systemImage: "list.clipboard")
            Label("\(active) active/planning", systemImage: "bolt.fill")
            if let last {
                Label("Last \(RunSupport.formatDate(last))", systemImage: "clock")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var editionBinding: Binding<Edition> {
        Binding(
            get: { campaign?.edition ?? .sr5 },
            set: { newValue in
                guard var c = campaign else { return }
                c.edition = newValue
                c.notes = notesDraft
                c.name = nameDraft
                c.houseRuleHints = composedHouseRuleHints()
                save(c)
            }
        )
    }

    private func load() {
        do {
            let c = try libraryEnvironment.campaignLibrary.require(campaignID)
            campaign = c
            nameDraft = c.name
            notesDraft = c.notes
            applyHouseRuleHints(from: c.houseRuleHints)
            runs = try libraryEnvironment.runLibrary.listSummaries(campaignID: campaignID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitIdentity(forceNotes: Bool) {
        guard var c = campaign else { return }
        c.name = nameDraft
        c.notes = notesDraft
        c.houseRuleHints = composedHouseRuleHints()
        _ = forceNotes
        save(c)
    }

    private func save(_ c: Campaign) {
        do {
            try libraryEnvironment.campaignLibrary.save(c)
            campaign = try libraryEnvironment.campaignLibrary.require(campaignID)
            nameDraft = campaign?.name ?? nameDraft
            if let hints = campaign?.houseRuleHints {
                applyHouseRuleHints(from: hints)
            }
            libraryEnvironment.refreshCampaignCount()
            statusMessage = "Saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setArchived(_ archived: Bool) {
        guard var c = campaign else { return }
        c.isArchived = archived
        c.notes = notesDraft
        c.name = nameDraft
        c.houseRuleHints = composedHouseRuleHints()
        save(c)
        libraryEnvironment.refreshCampaignCount()
    }

    private func createRunInCampaign() {
        commitIdentity(forceNotes: true)
        let edition = campaign?.edition ?? .sr5
        var run = Run.makeDraft(title: "New Run", edition: edition, campaignID: campaignID)
        let count = (try? libraryEnvironment.runLibrary.count()) ?? 0
        if count > 0 {
            run.title = "New Run \(count + 1)"
        }
        do {
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            load()
            onOpenRun(run.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unassignRun(_ id: UUID) {
        do {
            var run = try libraryEnvironment.runLibrary.require(id)
            run.campaignID = nil
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            load()
            statusMessage = "Run moved to Unassigned."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCampaign() {
        commitIdentity(forceNotes: true)
        do {
            try libraryEnvironment.deleteCampaignUnassigningRuns(id: campaignID)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
private struct FlowHouseRuleChips: View {
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

// MARK: - Add existing runs

/// Pick runs from the library and assign them to a campaign.
struct AddRunsToCampaignSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let campaignID: UUID
    let campaignEdition: Edition
    let alreadyAssignedIDs: Set<UUID>
    var onCancel: () -> Void
    var onAdded: () -> Void

    @State private var candidates: [RunSummary] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var onlyMatchingEdition = true
    @State private var errorMessage: String?

    private var visible: [RunSummary] {
        candidates.filter { summary in
            if alreadyAssignedIDs.contains(summary.id) { return false }
            if onlyMatchingEdition, summary.edition != campaignEdition { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add Runs from Library")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add \(selectedIDs.isEmpty ? "" : "\(selectedIDs.count) ")Run\(selectedIDs.count == 1 ? "" : "s")") {
                    assignSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding()

            Divider()

            HStack {
                Toggle("Only \(campaignEdition.shortName) ruleset", isOn: $onlyMatchingEdition)
                    .toggleStyle(.checkbox)
                Spacer()
                Text("\(visible.count) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Runs to Add", systemImage: "list.clipboard")
                } description: {
                    Text(
                        onlyMatchingEdition
                            ? "No unassigned \(campaignEdition.shortName) runs (or runs in other campaigns) match. Create a new run or clear the ruleset filter."
                            : "Every run is already in this campaign, or the library is empty."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedIDs) {
                    ForEach(visible) { summary in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.title)
                                    .font(.body.weight(.medium))
                                HStack(spacing: 8) {
                                    RunStatusBadge(status: summary.status)
                                    RunEditionBadge(edition: summary.edition)
                                    if let other = summary.campaignID, other != campaignID {
                                        Text("Reassign from another campaign")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else if summary.campaignID == nil {
                                        Text("Unassigned")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .tag(summary.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { refreshCandidates() }
    }

    private func refreshCandidates() {
        do {
            candidates = try libraryEnvironment.runLibrary.listSummaries()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignSelected() {
        do {
            for id in selectedIDs {
                var run = try libraryEnvironment.runLibrary.require(id)
                run.campaignID = campaignID
                try libraryEnvironment.runLibrary.save(run)
            }
            libraryEnvironment.refreshRunCount()
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
