//
//  CampaignsListView.swift
//  ShadowDeck
//
//  Campaign library list + campaign detail (runs under a campaign).
//

import SwiftUI

struct CampaignsListView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    /// When set, open this campaign detail immediately.
    var forcedOpenCampaignID: UUID?

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
            if let forcedOpenCampaignID {
                selectedCampaignID = forcedOpenCampaignID
            }
        }
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
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                Button("New Campaign", systemImage: "plus.circle") { createCampaign() }
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
                ContentUnavailableView {
                    Label(
                        showArchived ? "No Campaigns" : "No Active Campaigns",
                        systemImage: "folder"
                    )
                } description: {
                    Text(
                        showArchived
                            ? "Create a campaign to group missions for a table or ruleset."
                            : "Create a campaign, or enable Show archived to see archived ones."
                    )
                } actions: {
                    Button("New Campaign") { createCampaign() }
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

            Button {
                selectedCampaignID = summary.id
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Open campaign")
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
    @State private var hintsDraft = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button("Back", systemImage: "chevron.left") { onBack() }
                    Spacer()
                    if let campaign {
                        if campaign.isArchived {
                            Button("Unarchive") { setArchived(false) }
                        } else {
                            Button("Archive") { setArchived(true) }
                        }
                        Button("Delete…", role: .destructive) { confirmDelete = true }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                if campaign != nil {
                    RunSectionCard(title: "Campaign") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Name") {
                                TextField("Campaign name", text: $nameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 360)
                                    .onSubmit { commitIdentity() }
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

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $notesDraft)
                                    .font(.body)
                                    .frame(minHeight: 100)
                                    .padding(6)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                    .onChange(of: notesDraft) { _, _ in scheduleNotesSave() }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("House-rule hints")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                TextField("Table defaults (free text)…", text: $hintsDraft, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...4)
                                    .onSubmit { commitIdentity() }
                            }

                            HStack {
                                Button("Save") { commitIdentity() }
                                    .keyboardShortcut("s", modifiers: [.command])
                            }
                        }
                    }

                    RunSectionCard(title: "Runs") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("\(runs.count) run(s)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("New Run in Campaign", systemImage: "plus.circle") {
                                    createRunInCampaign()
                                }
                            }
                            if runs.isEmpty {
                                Text("No runs assigned yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(runs) { summary in
                                    Button {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { load() }
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
            hintsDraft = c.houseRuleHints
            runs = try libraryEnvironment.runLibrary.listSummaries(campaignID: campaignID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitIdentity() {
        guard var c = campaign else { return }
        c.name = nameDraft
        c.notes = notesDraft
        c.houseRuleHints = hintsDraft
        save(c)
    }

    private func scheduleNotesSave() {
        // Lightweight: save notes with identity commit path on next Save; also flush shortly.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard var c = campaign else { return }
            c.notes = notesDraft
            c.houseRuleHints = hintsDraft
            c.name = nameDraft
            try? libraryEnvironment.campaignLibrary.save(c)
            campaign = try? libraryEnvironment.campaignLibrary.require(campaignID)
        }
    }

    private func save(_ c: Campaign) {
        do {
            try libraryEnvironment.campaignLibrary.save(c)
            campaign = try libraryEnvironment.campaignLibrary.require(campaignID)
            nameDraft = campaign?.name ?? nameDraft
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
        save(c)
        libraryEnvironment.refreshCampaignCount()
    }

    private func createRunInCampaign() {
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

    private func deleteCampaign() {
        do {
            try libraryEnvironment.deleteCampaignUnassigningRuns(id: campaignID)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
