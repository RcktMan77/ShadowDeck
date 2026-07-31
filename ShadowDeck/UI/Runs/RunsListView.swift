//
//  RunsListView.swift
//  ShadowDeck
//
//  GM list + filter of runs/missions; opens RunDetailView.
//

import SwiftUI

struct RunsListView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    /// Optional run to open immediately (marketing screenshots / deep links).
    var forcedOpenRunID: UUID? = nil

    @State private var summaries: [RunSummary] = []
    @State private var characterSummaries: [CharacterSummary] = []
    @State private var selectedRunID: UUID?
    @State private var statusFilter: RunStatus?
    @State private var characterFilterID: UUID?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var runPendingDelete: RunSummary?

    private var filtered: [RunSummary] {
        summaries.filter { summary in
            if let statusFilter, summary.status != statusFilter { return false }
            if let characterFilterID,
               !summary.participantCharacterIDs.contains(characterFilterID)
            {
                return false
            }
            return true
        }
    }

    var body: some View {
        Group {
            if let selectedRunID {
                RunDetailView(
                    runID: selectedRunID,
                    onBack: {
                        // Always return to the library list (not Create → New Run).
                        self.selectedRunID = nil
                        refresh()
                    },
                    onDeleted: {
                        self.selectedRunID = nil
                        refresh()
                    }
                )
            } else {
                listRoot
            }
        }
        .onAppear {
            refresh()
            if let forcedOpenRunID {
                selectedRunID = forcedOpenRunID
            }
        }
        .onChange(of: forcedOpenRunID) { _, newID in
            if let newID {
                selectedRunID = newID
            } else if selectedRunID != nil, forcedOpenRunID == nil {
                // Parent cleared force-open (e.g. returning to list capture).
                // Leave manual selection alone unless we're in marketing list mode.
            }
        }
    }

    private var listRoot: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            filters

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

            if summaries.isEmpty {
                ContentUnavailableView {
                    Label("No Runs Yet", systemImage: "list.clipboard")
                } description: {
                    Text("Plan jobs for your table — briefings, objectives, team, and session log.")
                } actions: {
                    Button("New Run") { createRun() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Runs", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try clearing status or character filters.")
                } actions: {
                    Button("Clear Filters") {
                        statusFilter = nil
                        characterFilterID = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedRunID) {
                    ForEach(filtered) { summary in
                        runRow(summary)
                            .tag(summary.id)
                            .contextMenu {
                                Button("Open") { selectedRunID = summary.id }
                                Button("Delete…", role: .destructive) {
                                    runPendingDelete = summary
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
            "Delete this run?",
            isPresented: Binding(
                get: { runPendingDelete != nil },
                set: { if !$0 { runPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: runPendingDelete
        ) { summary in
            Button("Delete \(summary.title)", role: .destructive) {
                deleteRun(summary.id)
                runPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { runPendingDelete = nil }
        } message: { summary in
            Text("“\(summary.title)” will be removed. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack {
            Text("Run Library")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
            Button("New Run", systemImage: "plus.circle") { createRun() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Status", selection: $statusFilter) {
                Text("All statuses").tag(Optional<RunStatus>.none)
                ForEach(RunStatus.allCases) { status in
                    Text(status.displayName).tag(Optional(status))
                }
            }
            .frame(maxWidth: 200)

            Picker("Character", selection: $characterFilterID) {
                Text("All characters").tag(Optional<UUID>.none)
                ForEach(characterSummaries) { summary in
                    Text(summary.displayTitle).tag(Optional(summary.id))
                }
            }
            .frame(maxWidth: 260)

            Spacer()
            Text("\(filtered.count) of \(summaries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func runRow(_ summary: RunSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Primary open target — entire leading content opens the editor.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(1)
                    RunStatusBadge(status: summary.status)
                }
                RunTagChips(tags: summary.tags)
                HStack(spacing: 12) {
                    dateChip(label: "Planned", date: summary.plannedDate, systemImage: "calendar")
                    dateChip(label: "Started", date: summary.startedAt, systemImage: "play.fill")
                    dateChip(label: "Ended", date: summary.completedAt, systemImage: "flag.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Label(
                        "\(summary.participantCount) runner\(summary.participantCount == 1 ? "" : "s")",
                        systemImage: "person.2"
                    )
                    Text(participantNames(for: summary))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selectedRunID = summary.id }

            // Explicit actions (separate from the open tap target).
            HStack(spacing: 4) {
                Button {
                    selectedRunID = summary.id
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Edit run")

                Button {
                    runPendingDelete = summary
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Delete run")
            }
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dateChip(label: String, date: Date?, systemImage: String) -> some View {
        if let date {
            Label("\(label) \(RunSupport.formatDate(date))", systemImage: systemImage)
        } else {
            Label("\(label) —", systemImage: systemImage)
                .opacity(0.55)
        }
    }

    private func participantNames(for summary: RunSummary) -> String {
        let names = summary.participantCharacterIDs.compactMap { id in
            characterSummaries.first(where: { $0.id == id })?.displayTitle
        }
        if names.isEmpty {
            return summary.participantCount > 0 ? "Missing runners" : "No team yet"
        }
        return names.joined(separator: " · ")
    }

    private func refresh() {
        do {
            summaries = try libraryEnvironment.runLibrary.listSummaries()
            characterSummaries = try libraryEnvironment.library.listSummaries()
            libraryEnvironment.refreshRunCount()
            errorMessage = nil
            if selectedRunID == nil {
                statusMessage = summaries.isEmpty
                    ? "Library is empty."
                    : "\(summaries.count) run(s) in library."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createRun() {
        var run = Run.makeDraft(title: "New Run")
        // Ensure unique-ish default if many "New Run" exist.
        let count = (try? libraryEnvironment.runLibrary.count()) ?? 0
        if count > 0 {
            run.title = "New Run \(count + 1)"
        }
        do {
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            refresh()
            selectedRunID = run.id
            statusMessage = "Created “\(run.title)”."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRun(_ id: UUID) {
        do {
            try libraryEnvironment.runLibrary.delete(id: id)
            libraryEnvironment.refreshRunCount()
            if selectedRunID == id { selectedRunID = nil }
            refresh()
            statusMessage = "Run deleted."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

