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

