//
//  DraftRunFromPDFSheet.swift
//  ShadowDeck
//
//  Phase 2F: pick a library mission PDF (page range) → draft → review → create planning run.
//

import SwiftUI

struct DraftRunFromPDFSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    var preferredCampaignID: UUID? = nil
    var onCancel: () -> Void
    var onCreated: (UUID) -> Void

    @State private var pdfItems: [PDFLibraryItem] = []
    @State private var selectedPDFID: UUID?
    @State private var pageStart: Int = 1
    @State private var pageEnd: Int = 4
    @State private var documentPageCount: Int = 1
    @State private var campaignID: UUID?
    @State private var campaigns: [CampaignSummary] = []
    @State private var edition: Edition = .sr5
    @State private var draft: RunDraft?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var statusNote: String?
    @State private var phase: Phase = .pick

    private enum Phase {
        case pick
        case review
    }

    private var selectedItem: PDFLibraryItem? {
        pdfItems.first { $0.id == selectedPDFID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch phase {
                case .pick:
                    pickForm
                case .review:
                    if let draft {
                        reviewForm(draft)
                    } else {
                        ProgressView("Preparing draft…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 560, height: 620)
        .onAppear {
            loadShelf()
            campaignID = preferredCampaignID
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(phase == .pick ? "Draft run from PDF" : "Review draft")
                    .font(.headline)
                Text(
                    phase == .pick
                        ? "Extract a short page range from a library mission PDF. AI fills a draft when available — always review before saving."
                        : (draft?.usedOnDeviceAI == true
                            ? "On-device AI draft. Edit freely, then create a planning run."
                            : "Heuristic draft from PDF text. Edit freely, then create a planning run.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            AppChromeButton.title("Cancel", help: "Close without creating a run") {
                onCancel()
            }
        }
        .padding()
    }

    private var pickForm: some View {
        Form {
            Section {
                if pdfItems.isEmpty {
                    Text("No mission PDFs on the shelf yet. Open Rules Reference → Library, add a mission PDF, then return here.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Mission PDF", selection: $selectedPDFID) {
                        Text("Select…").tag(Optional<UUID>.none)
                        ForEach(pdfItems) { item in
                            Text(item.displayTitle).tag(Optional(item.id))
                        }
                    }
                    .onChange(of: selectedPDFID) { _, _ in
                        refreshPageBounds()
                    }
                }

                HStack {
                    Text("Pages")
                    TextField("Start", value: $pageStart, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("–")
                    TextField("End", value: $pageEnd, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("of \(documentPageCount)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Keep the range small (briefing / setup pages). Max \(PDFMissionTextExtractor.hardMaxPages) pages.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("Campaign", selection: $campaignID) {
                    Text("Unassigned").tag(Optional<UUID>.none)
                    ForEach(campaigns) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }
                Picker("Edition", selection: $edition) {
                    ForEach(Edition.allCases) { ed in
                        Text(ed.shortName).tag(ed)
                    }
                }
                .pickerStyle(.segmented)

                Text(RunDraftGenerator.availabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            if let statusNote {
                Text(statusNote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    AppChromeButton.title(
                        "Extract & Draft…",
                        help: "Extract the page range and build a reviewable draft",
                        style: .prominent,
                        isEnabled: selectedPDFID != nil && !isWorking && pageStart <= pageEnd
                    ) {
                        Task { await extractAndDraft() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }

    private func reviewForm(_ draftBinding: RunDraft) -> some View {
        // Local editable copy via state
        Form {
            if !draftBinding.warnings.isEmpty {
                Section("Notes") {
                    ForEach(draftBinding.warnings, id: \.self) { w in
                        Text(w)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Job") {
                TextField("Title", text: draftTitle)
                TextField("Mission code / tag", text: draftMissionCode)
                TextField("Client", text: draftClient)
                TextField("Location", text: draftLocation)
            }

            Section("Player-facing") {
                TextField("What runners know", text: draftPlayerSummary, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Known risks", text: draftKnownRisks, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("Objectives") {
                TextField("One objective per line", text: draftObjectivesText, axis: .vertical)
                    .lineLimit(4...12)
            }

            Section("GM-only") {
                TextField("Opposition summary", text: draftOpposition, axis: .vertical)
                    .lineLimit(2...6)
                TextField("GM notes", text: draftGMNotes, axis: .vertical)
                    .lineLimit(2...6)
                HStack {
                    TextField("Expected ¥", value: draftNuyen, format: .number)
                        .textFieldStyle(.roundedBorder)
                    TextField("Karma", value: draftKarma, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                HStack {
                    AppChromeButton.title("Back", help: "Return to PDF selection") {
                        phase = .pick
                        draft = nil
                    }
                    Spacer()
                    AppChromeButton.title(
                        "Create Planning Run",
                        help: "Save this draft as a planning run",
                        style: .prominent,
                        isEnabled: !(draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    ) {
                        createRun()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Draft field bindings

    private var draftTitle: Binding<String> {
        Binding(
            get: { draft?.title ?? "" },
            set: { draft?.title = $0 }
        )
    }

    private var draftMissionCode: Binding<String> {
        Binding(
            get: { draft?.missionCode ?? "" },
            set: { draft?.missionCode = $0.isEmpty ? nil : $0 }
        )
    }

    private var draftClient: Binding<String> {
        Binding(get: { draft?.client ?? "" }, set: { draft?.client = $0 })
    }

    private var draftLocation: Binding<String> {
        Binding(get: { draft?.location ?? "" }, set: { draft?.location = $0 })
    }

    private var draftPlayerSummary: Binding<String> {
        Binding(get: { draft?.playerFacingSummary ?? "" }, set: { draft?.playerFacingSummary = $0 })
    }

    private var draftKnownRisks: Binding<String> {
        Binding(get: { draft?.knownRisks ?? "" }, set: { draft?.knownRisks = $0 })
    }

    private var draftOpposition: Binding<String> {
        Binding(get: { draft?.oppositionSummary ?? "" }, set: { draft?.oppositionSummary = $0 })
    }

    private var draftGMNotes: Binding<String> {
        Binding(get: { draft?.gmNotes ?? "" }, set: { draft?.gmNotes = $0 })
    }

    private var draftNuyen: Binding<Int?> {
        Binding(get: { draft?.expectedPayoutNuyen }, set: { draft?.expectedPayoutNuyen = $0 })
    }

    private var draftKarma: Binding<Int?> {
        Binding(get: { draft?.expectedKarma }, set: { draft?.expectedKarma = $0 })
    }

    private var draftObjectivesText: Binding<String> {
        Binding(
            get: { (draft?.objectives ?? []).joined(separator: "\n") },
            set: { text in
                draft?.objectives = text
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: - Actions

    private func loadShelf() {
        let store = PDFLibraryStore.loadDefault()
        let all = store.items
        // Prefer mission section; still allow any PDF if shelf is sparse.
        let missions = all.filter { $0.shelfSection == .mission }
        pdfItems = (missions.isEmpty ? all : missions)
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        campaigns = (try? libraryEnvironment.campaignLibrary.listSummaries()) ?? []
        if selectedPDFID == nil {
            selectedPDFID = pdfItems.first?.id
        }
        refreshPageBounds()
    }

    private func refreshPageBounds() {
        guard let item = selectedItem else {
            documentPageCount = 1
            return
        }
        let store = PDFLibraryStore.loadDefault()
        let url = store.fileURL(for: item)
        if let doc = PDFDocument(url: url) {
            documentPageCount = max(1, doc.pageCount)
        } else {
            documentPageCount = item.pageCount ?? 1
        }
        pageStart = min(max(1, pageStart), documentPageCount)
        pageEnd = min(max(pageStart, pageEnd), documentPageCount)
        if pageEnd - pageStart + 1 > PDFMissionTextExtractor.defaultMaxPages {
            pageEnd = min(documentPageCount, pageStart + PDFMissionTextExtractor.defaultMaxPages - 1)
        }
    }

    @MainActor
    private func extractAndDraft() async {
        guard let item = selectedItem else { return }
        isWorking = true
        errorMessage = nil
        statusNote = "Extracting PDF text…"
        defer { isWorking = false }

        let store = PDFLibraryStore.loadDefault()
        let url = store.fileURL(for: item)
        let range = pageStart...max(pageStart, pageEnd)
        do {
            let extracted = try PDFMissionTextExtractor.extract(url: url, pageRange: range)
            statusNote = RunDraftGenerator.isOnDeviceAIAvailable
                ? "Drafting with on-device AI…"
                : "Building heuristic draft…"
            let source = RunDraftGenerator.Source(
                pdfID: item.id,
                pdfTitle: item.displayTitle,
                pageRange: extracted.extractedPages,
                extractedText: extracted.text
            )
            var result = await RunDraftGenerator.generate(from: source)
            result.warnings = extracted.warnings + result.warnings
            draft = result
            phase = .review
            statusNote = nil
        } catch {
            errorMessage = error.localizedDescription
            statusNote = nil
        }
    }

    private func createRun() {
        guard let current = draft else { return }
        let run = current.makeRun(edition: edition, campaignID: campaignID)
        do {
            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()
            onCreated(run.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import PDFKit
