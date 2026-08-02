//
//  ContentView.swift
//  ShadowDeck
//
//  Root window: sidebar shell, detail routing, library/import/generation.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, Identifiable, Hashable, CaseIterable {
    case characters
    case campaigns
    case runs
    case newCharacter
    case newCampaign
    case newRun
    case newRunFromTemplate
    case importCharacter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characters: "Characters"
        case .campaigns: "Campaigns"
        case .runs: "Runs"
        case .newCharacter: "New Character"
        case .newCampaign: "New Campaign"
        case .newRun: "New Run"
        case .newRunFromTemplate: "New Run from Template"
        case .importCharacter: "Import New Character"
        }
    }

    /// Base glyph (Create run/campaign get a shared top-trailing `+` overlay in the sidebar).
    var systemImage: String {
        switch self {
        case .characters: "person.3.fill"
        case .campaigns: "folder.fill"
        case .runs: "list.clipboard.fill"
        // Single person + shared + badge (Library Characters uses person.3.fill).
        case .newCharacter: "person.fill"
        case .newCampaign: "folder.fill"
        case .newRun: "list.clipboard.fill"
        case .newRunFromTemplate: "list.bullet.rectangle"
        case .importCharacter: "square.and.arrow.down.fill"
        }
    }

    /// When true, sidebar draws a consistent top-trailing plus badge (system `.badge.plus` glyphs place + differently).
    var showsCreatePlusBadge: Bool {
        switch self {
        case .newCharacter, .newRun, .newRunFromTemplate, .newCampaign: true
        default: false
        }
    }

    var help: String? {
        switch self {
        case .importCharacter:
            return "Import a new character from Chummer (.json / .chum5) or a .shadowdeck package"
        case .newCampaign:
            return "Create a campaign to group missions for a table or ruleset"
        case .newRun:
            return "Create a new mission / job in the Runs library"
        case .newRunFromTemplate:
            return "Start a job from a built-in or saved run template"
        case .newCharacter:
            return "Start the character generation wizard"
        case .characters:
            return "Browse characters in your library"
        case .campaigns:
            return "Group missions under campaigns for a table or ruleset"
        case .runs:
            return "Browse missions and jobs"
        }
    }
}

struct ContentView: View {
    // Marketing extension (ContentView+Marketing) needs cross-file access.
    @Environment(LibraryEnvironment.self) var libraryEnvironment
    @State var selection: SidebarItem? = .characters
    @State private var summaries: [CharacterSummary] = []
    @State var statusMessage: String?
    @State var selectedCharacterID: UUID?
    @State private var characterPendingDelete: CharacterSummary?
    @State var libraryQuery = ""
    @State private var libraryLayout: CharacterLibraryLayout = .gallery
    @State private var isLibraryDropTargeted = false
    @State private var newRunDetailID: UUID?
    /// Open this campaign detail after Create → New Campaign (or toolbar create).
    @State private var openCampaignID: UUID?
    @State private var showNewRunFromTemplate = false
    @State private var showDraftRunFromPDF = false
    @State private var templatePreferredCampaignID: UUID?
    @State var marketingOpenRunID: UUID?
    @State var marketingForceRunListOnly = false
    @Environment(\.openWindow) var openWindow

    var body: some View {
        NavigationSplitView {
            MainSidebarView(
                selection: $selection,
                characterCount: summaries.count,
                campaignCount: libraryEnvironment.campaignCount,
                runCount: libraryEnvironment.runCount,
                onNewCampaign: { requestNewCampaign() },
                onNewCharacter: {
                    selectedCharacterID = nil
                    selection = .newCharacter
                },
                onImportCharacter: {
                    selectedCharacterID = nil
                    selection = .importCharacter
                },
                onNewRun: { requestNewRun() },
                onNewRunFromTemplate: { showNewRunFromTemplate = true },
                onNewRunFromPDF: { showDraftRunFromPDF = true }
            )
        } detail: {
            NavigationStack {
                detail
                    .frame(
                        minWidth: 640,
                        maxWidth: .infinity,
                        minHeight: 400,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("ShadowDeck")
        .onAppear { refresh() }
        .onChange(of: selection) { _, newValue in
            if newValue == .characters {
                refresh()
            } else {
                selectedCharacterID = nil
            }
            if newValue == .runs {
                refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newCharacter)) { _ in
            selection = .newCharacter
            selectedCharacterID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newRun)) { _ in
            requestNewRun()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newRunFromTemplate)) { note in
            templatePreferredCampaignID = note.userInfo?["campaignID"] as? UUID
            showNewRunFromTemplate = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newRunFromPDF)) { _ in
            showDraftRunFromPDF = true
        }
        .sheet(isPresented: $showNewRunFromTemplate) {
            NewRunFromTemplateSheet(
                preferredCampaignID: templatePreferredCampaignID,
                onCancel: {
                    showNewRunFromTemplate = false
                    templatePreferredCampaignID = nil
                },
                onCreated: { runID in
                    showNewRunFromTemplate = false
                    templatePreferredCampaignID = nil
                    newRunDetailID = runID
                    selection = .newRun
                    libraryEnvironment.refreshRunCount()
                }
            )
            .environment(libraryEnvironment)
        }
        .sheet(isPresented: $showDraftRunFromPDF) {
            DraftRunFromPDFSheet(
                preferredCampaignID: templatePreferredCampaignID,
                onCancel: { showDraftRunFromPDF = false },
                onCreated: { runID in
                    showDraftRunFromPDF = false
                    newRunDetailID = runID
                    selection = .newRun
                    libraryEnvironment.refreshRunCount()
                }
            )
            .environment(libraryEnvironment)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.importCharacter)) { _ in
            selection = .importCharacter
            selectedCharacterID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openPackage)) { _ in
            selection = .importCharacter
            selectedCharacterID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openPackageURL)) { note in
            if let url = note.object as? URL {
                Task { await importShadowDeckPackage(from: url) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MarketingScreenshotExporter.phaseNotification)) { note in
            guard let raw = note.object as? String,
                  let phase = MarketingScreenshotExporter.Phase(rawValue: raw)
            else { return }
            let step = note.userInfo?["step"] as? Int
            handleMarketingPhase(phase, step: step)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openCharacterForScreenshots)) { note in
            if let id = note.object as? UUID {
                selection = .characters
                selectedCharacterID = id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openRulesReference)) { note in
            let query = note.userInfo?["query"] as? String
            let edition = note.userInfo?["edition"] as? Edition
            let calc = note.userInfo?["calcContext"] as? RulesCalcContext
            RulesReferenceSession.shared.prepare(
                query: query,
                edition: edition ?? calc?.edition,
                calcContext: calc
            )
            openWindow(id: RulesReferenceOpener.windowID)
        }
        .confirmationDialog(
            "Delete this character?",
            isPresented: Binding(
                get: { characterPendingDelete != nil },
                set: { if !$0 { characterPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: characterPendingDelete
        ) { summary in
            Button("Delete \(summary.displayTitle)", role: .destructive) {
                deleteCharacter(summary.id)
                characterPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                characterPendingDelete = nil
            }
        } message: { summary in
            Text("“\(summary.displayTitle)” will be removed from your library. This cannot be undone.")
        }
    }

    // MARK: - Detail routing

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .campaigns:
            CampaignsListView(
                forcedOpenCampaignID: openCampaignID,
                onOpenedForcedCampaign: { openCampaignID = nil }
            )
        case .newCampaign:
            // Create action routes through requestNewCampaign → .campaigns + detail.
            ProgressView("Creating campaign…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .newRunFromTemplate:
            // Sheet-only create path (opened from New Run menu); stay on a neutral placeholder.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .runs:
            RunsListView(
                forcedOpenRunID: marketingForceRunListOnly ? nil : marketingOpenRunID,
                forceListOnly: marketingForceRunListOnly
            )
            .id(marketingForceRunListOnly ? "runs-list-only" : "runs-\(marketingOpenRunID?.uuidString ?? "list")")
        case .newRun:
            if let newRunDetailID {
                RunDetailView(
                    runID: newRunDetailID,
                    onBack: {
                        self.newRunDetailID = nil
                        selection = .runs
                        refresh()
                    },
                    onDeleted: {
                        self.newRunDetailID = nil
                        selection = .runs
                        refresh()
                    }
                )
                .id(newRunDetailID)
            } else {
                ProgressView("Creating run…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .importCharacter:
            ImportView(
                onFinished: { importedID in
                    finishImport(importedID: importedID)
                },
                onCancel: {
                    selection = .characters
                    selectedCharacterID = nil
                    refresh()
                }
            )
            .onDisappear { refresh() }
        case .newCharacter:
            GenerationWizardView(
                onFinished: {
                    selection = .characters
                    refresh()
                },
                onCancel: {
                    selection = .characters
                    refresh()
                }
            )
        case .characters, .none:
            if let id = selectedCharacterID {
                CharacterAtAGlanceView(
                    characterID: id,
                    onBack: {
                        selectedCharacterID = nil
                        refresh()
                    },
                    onDeleted: {
                        selectedCharacterID = nil
                        refresh()
                    }
                )
            } else {
                CharacterLibraryBrowserView(
                    summaries: summaries,
                    libraryQuery: $libraryQuery,
                    libraryLayout: $libraryLayout,
                    isDropTargeted: $isLibraryDropTargeted,
                    statusMessage: statusMessage,
                    libraryError: libraryEnvironment.lastErrorMessage,
                    onRefresh: { refresh() },
                    onLoadSamples: { seedSamplesIfEmpty() },
                    onOpen: { openCharacterSheet($0) },
                    onExportPackage: { exportCharacter($0) },
                    onExportPDF: { exportPDFSheet($0) },
                    onExportChummer: { exportChummer($0) },
                    onDelete: { characterPendingDelete = $0 },
                    onDropProviders: { handleLibraryFileDrop($0) }
                )
            }
        }
    }

    // MARK: - Import / drop

    private func handleLibraryFileDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            guard let url = await LibraryFileDrop.firstFileURL(from: providers) else { return }
            await importDroppedFile(from: url)
        }
        return true
    }

    private func importDroppedFile(from url: URL) async {
        do {
            let result = try await libraryEnvironment.library.importAndSave(from: url)
            selection = .characters
            selectedCharacterID = result.character.id
            refresh()
            statusMessage = "Imported “\(result.character.displayTitle)” into the library."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func finishImport(importedID: UUID) {
        selection = .characters
        do {
            let count = try libraryEnvironment.library.count()
            selectedCharacterID = count == 1 ? importedID : nil
            refresh()
            if count == 1 {
                statusMessage = "Imported and opened the only character in the library."
            } else {
                statusMessage = "Import complete. \(count) character(s) in library."
            }
        } catch {
            selectedCharacterID = nil
            refresh()
            statusMessage = "Import finished, but could not refresh library: \(error.localizedDescription)"
        }
    }

    private func importShadowDeckPackage(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            // Package import is lightweight vs Chummer parse; still async for UI consistency.
            let character = try libraryEnvironment.library.importPackage(from: url)
            selection = .characters
            selectedCharacterID = character.id
            refresh()
            statusMessage = "Opened package “\(character.displayTitle)” into the library."
        } catch {
            selection = .characters
            refresh()
            statusMessage = "Could not open package: \(error.localizedDescription)"
        }
    }

    // MARK: - Library actions

    func refresh() {
        do {
            summaries = try libraryEnvironment.library.listSummaries()
            libraryEnvironment.refreshRunCount()
            if selectedCharacterID != nil,
               !summaries.contains(where: { $0.id == selectedCharacterID }) {
                selectedCharacterID = nil
            }
            if selectedCharacterID == nil, selection == .characters || selection == nil {
                statusMessage = summaries.isEmpty
                    ? "Library is empty."
                    : "\(summaries.count) character(s) in library."
            }
        } catch {
            statusMessage = "Failed to load library: \(error.localizedDescription)"
        }
    }

    private func openCharacterSheet(_ id: UUID) {
        Task { @MainActor in
            selectedCharacterID = id
        }
    }

    private func requestNewRun() {
        selectedCharacterID = nil
        beginNewRun()
        selection = .newRun
    }

    /// Create → New Campaign (re-click always mints another campaign, like New Run).
    private func requestNewCampaign() {
        selectedCharacterID = nil
        var campaign = Campaign.makeDraft(name: "New Campaign")
        let count = (try? libraryEnvironment.campaignLibrary.count(includeArchived: true)) ?? 0
        if count > 0 {
            campaign.name = "New Campaign \(count + 1)"
        }
        do {
            try libraryEnvironment.campaignLibrary.save(campaign)
            libraryEnvironment.refreshCampaignCount()
            openCampaignID = campaign.id
            selection = .campaigns
            statusMessage = nil
        } catch {
            openCampaignID = nil
            statusMessage = "Could not create campaign: \(error.localizedDescription)"
            selection = .campaigns
        }
    }

    private func beginNewRun() {
        var run = Run.makeDraft(title: "New Run")
        let count = (try? libraryEnvironment.runLibrary.count()) ?? 0
        if count > 0 {
            run.title = "New Run \(count + 1)"
        }
        do {
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            newRunDetailID = run.id
            statusMessage = nil
        } catch {
            newRunDetailID = nil
            statusMessage = "Could not create run: \(error.localizedDescription)"
            selection = .runs
        }
    }

    private func seedSamplesIfEmpty() {
        do {
            if try libraryEnvironment.library.count() == 0 {
                try libraryEnvironment.seedSampleCharactersWithPortraits()
                statusMessage = "Seeded sample SR4 / SR5 / SR6 characters with role portraits."
            } else {
                statusMessage = "Library already has characters. Use New Character or Import."
            }
            refresh()
        } catch {
            statusMessage = "Seed failed: \(error.localizedDescription)"
        }
    }

    private func deleteCharacter(_ id: UUID) {
        do {
            try libraryEnvironment.library.delete(id: id)
            if selectedCharacterID == id { selectedCharacterID = nil }
            refresh()
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func exportCharacter(_ summary: CharacterSummary) {
        do {
            statusMessage = try CharacterLibraryExportActions.exportPackage(
                summary: summary,
                library: libraryEnvironment.library
            )
        } catch is CancellationError {
            // User cancelled save panel.
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportPDFSheet(_ summary: CharacterSummary) {
        do {
            statusMessage = try CharacterLibraryExportActions.exportPDFSheet(
                summary: summary,
                library: libraryEnvironment.library
            )
        } catch is CancellationError {
            // User cancelled.
        } catch {
            statusMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }

    private func exportChummer(_ summary: CharacterSummary) {
        do {
            statusMessage = try CharacterLibraryExportActions.exportChummer(
                summary: summary,
                library: libraryEnvironment.library
            )
        } catch is CancellationError {
            // User cancelled.
        } catch {
            statusMessage = "Chummer export failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(LibraryEnvironment.preview())
        .frame(width: 1100, height: 720)
}
