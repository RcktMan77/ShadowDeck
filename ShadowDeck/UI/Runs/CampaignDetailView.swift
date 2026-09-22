//
//  CampaignsListView.swift
//  ShadowDeck
//
//  Campaign library list + campaign detail (runs under a campaign).
//

import SwiftUI
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

