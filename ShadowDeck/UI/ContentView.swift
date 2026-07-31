//
//  ContentView.swift
//  ShadowDeck
//
//  Root window: library list, at-a-glance summary, import, and generation.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarItem: String, Identifiable, Hashable, CaseIterable {
    case characters
    case runs
    case newCharacter
    case newRun
    case importCharacter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characters: "Characters"
        case .runs: "Runs"
        case .newCharacter: "New Character"
        case .newRun: "New Run"
        case .importCharacter: "Import Character…"
        }
    }

    var systemImage: String {
        switch self {
        case .characters: "person.3"
        case .runs: "list.clipboard"
        case .newCharacter: "plus.circle"
        case .newRun: "plus.rectangle.on.folder"
        case .importCharacter: "square.and.arrow.down"
        }
    }

    var help: String? {
        switch self {
        case .importCharacter:
            return "Import a character from Chummer (.json / .chum5) or a .shadowdeck package"
        case .newRun:
            return "Create a new mission / job in the Runs library"
        case .newCharacter:
            return "Start the character generation wizard"
        case .characters:
            return "Browse characters in your library"
        case .runs:
            return "Browse missions and jobs"
        }
    }
}

struct ContentView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @State private var selection: SidebarItem? = .characters
    @State private var summaries: [CharacterSummary] = []
    @State private var statusMessage: String?
    @State private var selectedCharacterID: UUID?
    /// Pending library delete (confirmation dialog).
    @State private var characterPendingDelete: CharacterSummary?
    @State private var libraryQuery = ""
    @State private var isLibraryDropTargeted = false
    /// Run opened via Create → New Run / File → New Run (detail only; never a list host).
    @State private var newRunDetailID: UUID?
    /// Marketing screenshots: force-open a run inside the Runs library list host.
    @State private var marketingOpenRunID: UUID?

    private var filteredSummaries: [CharacterSummary] {
        let q = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return summaries }
        return summaries.filter {
            $0.displayTitle.lowercased().contains(q)
                || $0.concept.lowercased().contains(q)
                || $0.editionRaw.lowercased().contains(q)
                || $0.metatypeRaw.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
                || $0.streetName.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label(SidebarItem.characters.title, systemImage: SidebarItem.characters.systemImage)
                        .badge(summaries.count)
                        .tag(SidebarItem.characters)
                        .help(SidebarItem.characters.help ?? "")
                    Label(SidebarItem.runs.title, systemImage: SidebarItem.runs.systemImage)
                        .badge(libraryEnvironment.runCount)
                        .tag(SidebarItem.runs)
                        .help(SidebarItem.runs.help ?? "")
                }
                Section("Create") {
                    Label(SidebarItem.newCharacter.title, systemImage: SidebarItem.newCharacter.systemImage)
                        .tag(SidebarItem.newCharacter)
                        .help(SidebarItem.newCharacter.help ?? "")
                    Label(SidebarItem.newRun.title, systemImage: SidebarItem.newRun.systemImage)
                        .tag(SidebarItem.newRun)
                        .help(SidebarItem.newRun.help ?? "")
                    Label(SidebarItem.importCharacter.title, systemImage: SidebarItem.importCharacter.systemImage)
                        .tag(SidebarItem.importCharacter)
                        .help(SidebarItem.importCharacter.help ?? "")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            .listStyle(.sidebar)
        } detail: {
            // NavigationStack keeps the detail column a proper primary column;
            // shared min frame prevents collapse under contentMinSize sizing.
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
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .characters {
                // Stay on summary if a character is selected; refresh list data.
                refresh()
            } else {
                selectedCharacterID = nil
            }
            if newValue == .runs {
                // Keep the Runs badge / list in sync after create/delete from other routes.
                refresh()
            }
            // Sidebar Create → New Run: create once when entering this item.
            // (File menu path calls beginNewRun() itself before setting selection.)
            if newValue == .newRun, oldValue != .newRun, newRunDetailID == nil {
                beginNewRun()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newCharacter)) { _ in
            selection = .newCharacter
            selectedCharacterID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newRun)) { _ in
            selectedCharacterID = nil
            // Always mint a new run (even if already on .newRun).
            beginNewRun()
            selection = .newRun
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.importCharacter)) { _ in
            selection = .importCharacter
            selectedCharacterID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openPackage)) { _ in
            // Unified with Import… (packages, Chummer JSON, .chum5).
            selection = .importCharacter
            selectedCharacterID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openPackageURL)) { note in
            if let url = note.object as? URL {
                importShadowDeckPackage(from: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MarketingScreenshotExporter.phaseNotification)) { note in
            guard let raw = note.object as? String,
                  let phase = MarketingScreenshotExporter.Phase(rawValue: raw)
            else { return }
            handleMarketingPhase(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openCharacterForScreenshots)) { note in
            if let id = note.object as? UUID {
                selection = .characters
                selectedCharacterID = id
            }
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

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .runs:
            RunsListView(forcedOpenRunID: marketingOpenRunID)
        case .newRun:
            // Detail only — creation happens once in beginNewRun(), never via onAppear.
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
            ImportView { importedID in
                finishImport(importedID: importedID)
            }
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
                charactersLibrary
            }
        }
    }

    private var charactersLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Character Library")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                    .help("Reload the library list from disk (useful after external changes).")
                Button("Load Samples", systemImage: "tray.and.arrow.down") { seedSamplesIfEmpty() }
                    .help("If the library is empty, add one sample runner for each edition (SR4 / SR5 / SR6). Does nothing when characters already exist.")
                Button("New Character", systemImage: "plus.circle") {
                    selection = .newCharacter
                }
                Button("Import…", systemImage: "square.and.arrow.down") {
                    selection = .importCharacter
                }
                .help("Import Chummer (.json / .chum5) or a .shadowdeck package")
            }

            if isLibraryDropTargeted {
                Text("Drop to import (.json / .chum5 / .shadowdeck)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }

            if !summaries.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by name, street name, concept, edition…", text: $libraryQuery)
                        .textFieldStyle(.plain)
                    if !libraryQuery.isEmpty {
                        Button {
                            libraryQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 480)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = libraryEnvironment.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if summaries.isEmpty {
                ContentUnavailableView {
                    Label("No Characters Yet", systemImage: "person.crop.rectangle.stack")
                } description: {
                    Text("Create a runner with the generation wizard, import Chummer or a .shadowdeck package, or load samples.")
                } actions: {
                    Button("New Character") { selection = .newCharacter }
                    Button("Import…") { selection = .importCharacter }
                    Button("Load Samples") { seedSamplesIfEmpty() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSummaries.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No characters match “\(libraryQuery)”.")
                } actions: {
                    Button("Clear Filter") { libraryQuery = "" }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a runner for the at-a-glance summary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(filteredSummaries) { summary in
                        HStack(spacing: 10) {
                            // Tappable open area — separate from action buttons.
                            HStack(spacing: 12) {
                                libraryPortrait(summary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.displayTitle)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(librarySubtitle(for: summary))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCharacterID = summary.id
                            }
                            .layoutPriority(1)

                            // Compact trailing actions (fixed width so Menu doesn't expand).
                            HStack(spacing: 4) {
                                Button {
                                    selectedCharacterID = summary.id
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.body)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .help("Open \(summary.displayTitle)")

                                Menu {
                                    Button("ShadowDeck Package…") {
                                        exportCharacter(summary)
                                    }
                                    Button("PDF Character Sheet…") {
                                        exportPDFSheet(summary)
                                    }
                                    Button("Chummer .chum5…") {
                                        exportChummer(summary)
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.body)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .help("Export \(summary.displayTitle)")

                                Button {
                                    characterPendingDelete = summary
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.body)
                                        .foregroundStyle(.red)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .help("Delete \(summary.displayTitle)")
                            }
                            .fixedSize()
                        }
                        .contextMenu {
                            Button("Open Character Sheet") {
                                selectedCharacterID = summary.id
                            }
                            Button("Export ShadowDeck Package…") {
                                exportCharacter(summary)
                            }
                            Button("Export PDF Character Sheet…") {
                                exportPDFSheet(summary)
                            }
                            Button("Export Chummer .chum5…") {
                                exportChummer(summary)
                            }
                            Button("Delete…", role: .destructive) {
                                characterPendingDelete = summary
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: 720)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isLibraryDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isLibraryDropTargeted) { providers in
            handleLibraryFileDrop(providers)
        }
    }

    /// Drag-and-drop import for the library (`.json` / `.chum5` / `.shadowdeck`).
    private func handleLibraryFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let urlItem = item as? URL {
                url = urlItem
            } else if let str = item as? String {
                url = URL(fileURLWithPath: str)
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                importDroppedFile(from: url)
            }
        }
        return true
    }

    private func importDroppedFile(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let result = try libraryEnvironment.library.importAndSave(from: url)
            selection = .characters
            selectedCharacterID = result.character.id
            refresh()
            statusMessage = "Imported “\(result.character.displayTitle)” into the library."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func libraryPortrait(_ summary: CharacterSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let data = summary.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "person.crop.rectangle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
        }
    }

    /// After import: open the character only when they are the sole library entry;
    /// otherwise land on the library list so the user can choose among runners.
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

    private func refresh() {
        do {
            summaries = try libraryEnvironment.library.listSummaries()
            libraryEnvironment.refreshRunCount()
            if selectedCharacterID != nil,
               !summaries.contains(where: { $0.id == selectedCharacterID })
            {
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

    /// Edition · Metatype · short concept tagline (keyword-derived when free text is long).
    private func librarySubtitle(for summary: CharacterSummary) -> String {
        let tag = summary.concept.trimmingCharacters(in: .whitespacesAndNewlines)
        let conceptPart = tag.isEmpty ? "—" : tag
        return "\(summary.editionRaw) · \(summary.metatypeRaw.capitalized) · \(conceptPart)"
    }

    /// Mint exactly one run and show its detail under Create → New Run.
    private func beginNewRun() {
        var run = Run.makeDraft(title: "New Run")
        let count = (try? libraryEnvironment.runLibrary.count()) ?? 0
        // Next ordinal: 1 existing → "New Run 2", etc.
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
                for sample in SampleCharacters.makeAll() {
                    try libraryEnvironment.library.save(sample)
                }
                statusMessage = "Seeded sample SR4 / SR5 / SR6 characters."
            } else {
                statusMessage = "Library already has characters. Use New Character or Import."
            }
            refresh()
        } catch {
            statusMessage = "Seed failed: \(error.localizedDescription)"
        }
    }

    /// Drive UI into known-good states for README marquee captures.
    /// Capture launches with an in-memory sample-only library (`LibraryEnvironment.marketingCapture()`).
    private func handleMarketingPhase(_ phase: MarketingScreenshotExporter.Phase) {
        switch phase {
        case .splash:
            break
        case .library:
            marketingOpenRunID = nil
            selection = .characters
            selectedCharacterID = nil
            libraryQuery = ""
            refresh()
        case .generationRole:
            marketingOpenRunID = nil
            selection = .newCharacter
            selectedCharacterID = nil
            // Wizard observes and jumps to Concept & Role.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: AppCommand.wizardShowRoleStep, object: nil)
            }
        case .characterSheet:
            marketingOpenRunID = nil
            selection = .characters
            refresh()
            // Always the SR5 sample combat mage (seeded in marketingCapture library).
            // Marquee “play sheet” stays on Summary (default tab).
            selectedCharacterID = SampleCharacters.sr5ID
        case .runLibrary:
            selectedCharacterID = nil
            marketingOpenRunID = nil
            openMarketingSampleRun(detail: false)
            selection = .runs
            refresh()
        case .runDetail:
            selectedCharacterID = nil
            openMarketingSampleRun(detail: true)
            selection = .runs
            refresh()
        case .finished:
            break
        }
    }

    /// Open the single seeded marketing run (never scans personal on-disk libraries).
    private func openMarketingSampleRun(detail: Bool) {
        do {
            let runs = try libraryEnvironment.runLibrary.listSummaries()
            marketingOpenRunID = detail ? runs.first?.id : nil
            libraryEnvironment.refreshRunCount()
        } catch {
            statusMessage = "Screenshot run open failed: \(error.localizedDescription)"
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shadowdeckCharacter]
        let baseName: String = {
            if !summary.streetName.isEmpty { return summary.streetName }
            if !summary.name.isEmpty { return summary.name }
            return "Runner"
        }()
        panel.nameFieldStringValue = "\(baseName).\(ShadowDeckFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export a portable ShadowDeck character package"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try libraryEnvironment.library.exportPackage(id: summary.id, to: url)
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Import a portable `.shadowdeck` package into the library (File menu / double-click).
    private func exportPDFSheet(_ summary: CharacterSummary) {
        do {
            let character = try libraryEnvironment.library.require(summary.id)
            let report = CampaignSheetReport.build(for: character)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let baseName: String = {
                if !summary.streetName.isEmpty { return summary.streetName }
                if !summary.name.isEmpty { return summary.name }
                return "Runner"
            }()
            panel.nameFieldStringValue = "\(baseName)_sheet.pdf"
            panel.canCreateDirectories = true
            panel.message = "Export a printable ShadowDeck character sheet (PDF)"
            panel.prompt = "Export PDF"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try CharacterSheetPDF.write(report: report, to: url)
            statusMessage = "Exported PDF sheet for \(summary.displayTitle)."
        } catch {
            statusMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }

    private func exportChummer(_ summary: CharacterSummary) {
        do {
            let character = try libraryEnvironment.library.require(summary.id)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "chum5") ?? .xml]
            let baseName: String = {
                if !summary.streetName.isEmpty { return summary.streetName }
                if !summary.name.isEmpty { return summary.name }
                return "Runner"
            }()
            panel.nameFieldStringValue = "\(baseName).chum5"
            panel.canCreateDirectories = true
            let hasOriginal = character.importProvenance?.originalPayload != nil
            panel.message = hasOriginal
                ? "Export original imported Chummer file when available"
                : "Best-effort regenerated Chummer .chum5"
            panel.prompt = "Export .chum5"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let result = try ChummerXMLExporter.export(character, mode: .preferOriginal)
            try result.xmlData.write(to: url, options: .atomic)
            statusMessage = result.usedOriginalPayload
                ? "Exported original Chummer file for \(summary.displayTitle)."
                : "Exported regenerated Chummer file for \(summary.displayTitle)."
        } catch {
            statusMessage = "Chummer export failed: \(error.localizedDescription)"
        }
    }

    private func importShadowDeckPackage(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
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
}

#Preview {
    ContentView()
        .environment(LibraryEnvironment.preview())
        .frame(width: 1100, height: 720)
}
