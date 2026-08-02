//
//  RulesReferenceController.swift
//  ShadowDeck
//
//  Session state for the dedicated Rules Reference window.
//

import Foundation
import PDFKit
import SwiftUI

/// Top-level window mode: knowledge browser vs PDF shelf.
public enum RulesReferenceMode: String, CaseIterable, Identifiable, Sendable {
    case reference
    case library

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reference: "Reference"
        case .library: "Library"
        }
    }

    public var systemImage: String {
        switch self {
        case .reference: "text.book.closed"
        case .library: "books.vertical"
        }
    }
}

/// Sort order for the Library shelf (browse phase).
public enum LibraryShelfSort: String, CaseIterable, Identifiable, Sendable {
    case title
    case dateAdded
    case bookKey
    case editionTag

    public var id: String { rawValue }

    public var menuLabel: String {
        switch self {
        case .title: "Title"
        case .dateAdded: "Date added"
        case .bookKey: "Book key"
        case .editionTag: "Edition tag"
        }
    }
}

/// List / Gallery for the PDF shelf (matches Character Library glyphs).
public enum LibraryShelfLayout: String, CaseIterable, Identifiable, Sendable {
    case list
    case gallery

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .list: "List"
        case .gallery: "Gallery"
        }
    }

    public var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        }
    }
}

/// One non-empty section on the PDF shelf.
struct LibraryShelfSectionGroup: Identifiable {
    var section: PDFShelfSection
    var items: [PDFLibraryItem]
    var id: String { section.rawValue }
}

/// One hit from shelf-wide PDF text search.
struct LibraryTextSearchHit: Identifiable, Hashable, Sendable {
    var id: String { "\(itemID.uuidString):\(page):\(score):\(snippet.prefix(24))" }
    var itemID: UUID
    var bookTitle: String
    var page: Int
    var snippet: String
    /// Higher is better (phrase and multi-token density).
    var score: Int
    /// How many query tokens matched on this page.
    var matchedTokenCount: Int
    var queryTokenCount: Int

    var relevanceLabel: String {
        if queryTokenCount <= 1 { return "match" }
        if matchedTokenCount >= queryTokenCount { return "all \(queryTokenCount) words" }
        return "\(matchedTokenCount)/\(queryTokenCount) words"
    }
}

@MainActor
final class RulesReferenceController: ObservableObject {
    @Published var mode: RulesReferenceMode = .reference

    // MARK: Reference mode
    @Published var query: String = "" {
        didSet { if query != oldValue { refreshResults() } }
    }
    @Published var selectedCategory: RuleCategory? {
        didSet { if selectedCategory != oldValue { refreshResults() } }
    }
    @Published var editionFilter: Edition? {
        didSet { if editionFilter != oldValue { refreshResults() } }
    }
    @Published var selectedID: String?
    /// Bumped when the topics list should scroll to `selectedID` (Look up / deep link).
    @Published private(set) var topicsScrollEpoch: Int = 0
    /// Calculator prefills from the last character that opened Rules Reference.
    @Published var calcContext: RulesCalcContext = .neutral

    // MARK: Library mode
    /// `nil` = full-width shelf; non-nil = reader for that book.
    @Published var selectedLibraryItemID: UUID?
    @Published var pdfTargetPage: Int = 1
    /// Incremented on every explicit page jump (chips / open) so the viewer re-navigates.
    @Published var pdfNavigationEpoch: Int = 0
    @Published var libraryFilter: String = ""
    @Published var librarySort: LibraryShelfSort = .title
    @Published var libraryLayout: LibraryShelfLayout = .gallery
    /// When jumping from a page chip, enable Back to card.
    @Published var returnToCardID: String?
    /// Zoom preset per document (survives mode toggles). Default: fit entire page.
    @Published var pdfZoomByItemID: [UUID: PDFZoomPreset] = [:]
    /// Transient status for Library actions (bind key, import).
    @Published var libraryStatusMessage: String?

    /// Full-text search across shelf PDFs (Library mode).
    @Published var libraryTextQuery: String = ""
    @Published private(set) var libraryTextHits: [LibraryTextSearchHit] = []
    @Published private(set) var libraryTextSearching = false
    /// True after a search finishes until the user clears — so empty results show a message
    /// instead of silently falling back to the book shelf.
    @Published private(set) var libraryTextSearchActive = false
    @Published private(set) var libraryTextSearchStatus: String?
    /// 0-based index into `libraryTextHits` for next/previous navigation.
    @Published var libraryTextHitIndex: Int = 0

    @Published private(set) var store: RulesReferenceStore
    @Published private(set) var pdfLibrary: PDFLibraryStore

    private var libraryTextSearchTask: Task<Void, Never>?
    private var didRestoreState = false

    /// Cached search rows — invalidated only when query / category / edition change.
    @Published private(set) var results: [RulesReferenceSearchResult] = []

    init(
        store: RulesReferenceStore = .loadBundled(),
        pdfLibrary: PDFLibraryStore = PDFLibraryStore.loadDefault()
    ) {
        self.store = store
        self.pdfLibrary = pdfLibrary
        restoreUIState()
        refreshResults()
    }

    private func refreshResults() {
        results = store.search(
            query: query,
            category: selectedCategory,
            edition: editionFilter,
            limit: 80
        )
    }

    /// Library is in reader phase when a book is open.
    var isLibraryReaderOpen: Bool {
        mode == .library && selectedLibraryItemID != nil
    }

    var selectedEntry: RuleEntry? {
        guard let selectedID else { return nil }
        return store.entry(id: selectedID)
            ?? results.first { $0.entry.id == selectedID }?.entry
    }

    var selectedPDFItem: PDFLibraryItem? {
        guard let selectedLibraryItemID else { return nil }
        return pdfLibrary.item(id: selectedLibraryItemID)
    }

    /// PDF shelf filtered + sorted for the browse phase.
    var filteredLibraryItems: [PDFLibraryItem] {
        let q = libraryFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [PDFLibraryItem]
        if q.isEmpty {
            filtered = pdfLibrary.items
        } else {
            filtered = pdfLibrary.items.filter {
                $0.displayTitle.lowercased().contains(q)
                    || ($0.bookKey?.lowercased().contains(q) ?? false)
                    || $0.notes.lowercased().contains(q)
                    || $0.editionTags.contains { $0.lowercased().contains(q) }
                    || $0.shelfSection.displayName.lowercased().contains(q)
            }
        }
        return sortLibraryItems(filtered)
    }

    /// Shelf items grouped into non-empty sections (core, missions, …).
    var librarySectionGroups: [LibraryShelfSectionGroup] {
        let items = filteredLibraryItems
        return PDFShelfSection.allCases.compactMap { section in
            let group = items.filter { $0.shelfSection == section }
            guard !group.isEmpty else { return nil }
            return LibraryShelfSectionGroup(section: section, items: group)
        }
    }

    var loadErrors: [String] { store.loadErrors }

    var canReturnToCard: Bool {
        returnToCardID != nil && store.entry(id: returnToCardID ?? "") != nil
    }

    /// Reader was opened from shelf text-search hits that are still active.
    var canReturnToSearchResults: Bool {
        libraryTextSearchActive && !libraryTextHits.isEmpty
    }

    func count(for category: RuleCategory?) -> Int {
        store.entries(category: category, edition: editionFilter).count
    }

    func ensureInitialSelection() {
        guard selectedID == nil else { return }
        selectedID = store.entries.first?.id
    }

    /// Apply Look up / menu open context **synchronously** on the main actor.
    /// Must not defer via `Task`/`yield`: the Rules window can paint one frame with the
    /// restored Library mode before a deferred switch to Reference (visual flash).
    func applyOpenContext(
        query initialQuery: String? = nil,
        edition: Edition? = nil,
        calcContext: RulesCalcContext? = nil
    ) {
        mode = .reference
        returnToCardID = nil
        selectedCategory = nil
        if let calcContext {
            self.calcContext = calcContext
            editionFilter = calcContext.edition
        } else if let edition {
            editionFilter = edition
        }
        if let initialQuery {
            let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                query = trimmed
                selectedID = results.first?.entry.id ?? store.entries.first?.id
                // Scroll after the topics list has mounted with the new selection.
                Task { @MainActor in
                    await Task.yield()
                    self.requestTopicsScrollToSelection()
                }
                persistUIState()
                return
            }
        }
        syncRuleSelectionToResults()
        Task { @MainActor in
            await Task.yield()
            self.requestTopicsScrollToSelection()
        }
        persistUIState()
    }

    /// Ask the topics List to scroll so `selectedID` is visible (top-aligned).
    func requestTopicsScrollToSelection() {
        guard selectedID != nil else { return }
        topicsScrollEpoch &+= 1
    }

    func switchMode(_ newMode: RulesReferenceMode) {
        Task { @MainActor in
            self.mode = newMode
            self.persistUIState()
        }
    }

    func selectRule(_ id: String) {
        Task { @MainActor in
            self.mode = .reference
            self.selectedID = id
            self.returnToCardID = nil
            self.persistUIState()
        }
    }

    func selectCategory(_ category: RuleCategory?) {
        Task { @MainActor in
            self.mode = .reference
            self.selectedCategory = category
            self.syncRuleSelectionToResults()
            self.persistUIState()
        }
    }

    func selectPDF(_ id: UUID, page: Int? = nil) {
        let resolvedPage: Int = {
            if let page { return max(1, page) }
            if let item = pdfLibrary.item(id: id) { return max(1, item.lastOpenedPage) }
            return 1
        }()
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            // Page + epoch first so a newly mounted reader never opens on restored p.1
            // before the intended jump is applied.
            self.pdfTargetPage = resolvedPage
            self.pdfNavigationEpoch &+= 1
            if self.mode != .library { self.mode = .library }
            if self.selectedLibraryItemID != id { self.selectedLibraryItemID = id }
            self.persistUIState()
        }
    }

    /// Leave the reader and show the main shelf (clears any active PDF text search).
    func backToShelf() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if self.selectedLibraryItemID != nil { self.selectedLibraryItemID = nil }
            if self.libraryStatusMessage != nil { self.libraryStatusMessage = nil }
            // "All books" always means the real shelf, not lingering search results.
            if self.libraryTextSearchActive {
                self.clearLibraryTextSearch()
            }
            self.persistUIState()
        }
    }

    /// Leave the reader but keep shelf text-search hits visible.
    func backToSearchResults() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if self.selectedLibraryItemID != nil { self.selectedLibraryItemID = nil }
            if self.libraryStatusMessage != nil { self.libraryStatusMessage = nil }
            // Keep libraryTextSearchActive + hits.
            self.persistUIState()
        }
    }

    func zoomPreset(for itemID: UUID) -> PDFZoomPreset {
        pdfZoomByItemID[itemID] ?? .fitPage
    }

    func setZoomPreset(_ preset: PDFZoomPreset, for itemID: UUID) {
        pdfZoomByItemID[itemID] = preset
        persistUIState()
    }

    func openPageRef(_ ref: PageRef) {
        guard let item = pdfLibrary.item(bookKey: ref.bookKey) else { return }
        let pdfPage = item.pdfPage(forPrintedPage: ref.page)
        let cardID = selectedID
        let offset = item.pageOffset
        let label = ref.label
        let printPage = ref.page
        let itemID = item.id
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if self.returnToCardID != cardID { self.returnToCardID = cardID }
            // Always assign target page (even if equal) and bump epoch so a fresh
            // document attach re-navigates. Set page *before* selecting the book so
            // the first mount of PDFReaderWorkspace sees the correct page.
            self.pdfTargetPage = pdfPage
            self.pdfNavigationEpoch &+= 1
            if self.mode != .library { self.mode = .library }
            if self.selectedLibraryItemID != itemID { self.selectedLibraryItemID = itemID }
            let status: String
            if offset > 0 {
                status = "Opened \(label) · printed p. \(printPage) → PDF p. \(pdfPage)"
            } else {
                status = "Opened \(label) · p. \(printPage)"
            }
            if self.libraryStatusMessage != status {
                self.libraryStatusMessage = status
            }
            self.persistUIState()
        }
    }

    func backToCard() {
        Task { @MainActor in
            let cardID = self.returnToCardID
            self.returnToCardID = nil
            self.mode = .reference
            if let cardID, self.store.entry(id: cardID) != nil {
                self.selectedID = cardID
            }
            self.persistUIState()
        }
    }

    func clearFilters() {
        Task { @MainActor in
            self.query = ""
            self.selectedCategory = nil
            self.persistUIState()
        }
    }

    func replacePDFLibrary(_ library: PDFLibraryStore) {
        pdfLibrary = library
    }

    /// Marketing capture: full-width gallery shelf (no personal library, no reader open).
    func applyMarketingLibraryShelf() {
        mode = .library
        selectedLibraryItemID = nil
        libraryLayout = .gallery
        libraryFilter = ""
        libraryStatusMessage = nil
        libraryTextQuery = ""
        libraryTextHits = []
        libraryTextHitIndex = 0
        libraryTextSearching = false
        libraryTextSearchActive = false
        libraryTextSearchStatus = nil
    }

    // MARK: - Shelf-wide PDF text search

    func runLibraryTextSearch() {
        let q = libraryTextQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        libraryTextSearchTask?.cancel()
        guard !q.isEmpty else {
            clearLibraryTextSearch()
            return
        }
        guard !pdfLibrary.items.isEmpty else {
            libraryTextHits = []
            libraryTextHitIndex = 0
            libraryTextSearching = false
            libraryTextSearchActive = true
            libraryTextSearchStatus = "No books on the shelf to search."
            return
        }

        libraryTextSearching = true
        libraryTextSearchActive = true
        libraryTextSearchStatus = nil
        libraryTextHits = []
        libraryTextHitIndex = 0

        let fileURLs: [(UUID, String, URL)] = pdfLibrary.items.map {
            ($0.id, $0.displayTitle, pdfLibrary.fileURL(for: $0))
        }

        libraryTextSearchTask = Task.detached(priority: .userInitiated) {
            // Cap concurrent PDFDocument opens to limit peak memory on large CRBs.
            let bookResults = await withTaskGroup(
                of: (opened: Bool, failed: Bool, hits: [LibraryTextSearchHit]).self
            ) { group in
                var iterator = fileURLs.makeIterator()
                let limit = PDFLibrarySearchEngine.maxConcurrentBooks

                func enqueueNext() -> Bool {
                    guard let (id, title, url) = iterator.next() else { return false }
                    group.addTask {
                        if Task.isCancelled {
                            return (false, false, [])
                        }
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            return (false, true, [])
                        }
                        guard let doc = PDFDocument(url: url) else {
                            return (false, true, [])
                        }
                        let pageHits = PDFLibrarySearchEngine.rankDocument(doc, query: q)
                        let hits = pageHits.prefix(15).map { hit in
                            LibraryTextSearchHit(
                                itemID: id,
                                bookTitle: title,
                                page: hit.page,
                                snippet: hit.snippet,
                                score: hit.score,
                                matchedTokenCount: hit.matchedTokens,
                                queryTokenCount: hit.tokenCount
                            )
                        }
                        return (true, false, Array(hits))
                    }
                    return true
                }

                var inFlight = 0
                while inFlight < limit, enqueueNext() {
                    inFlight += 1
                }

                var opened = 0
                var failed = 0
                var all: [LibraryTextSearchHit] = []
                for await result in group {
                    if Task.isCancelled { break }
                    if result.opened { opened += 1 }
                    if result.failed { failed += 1 }
                    all.append(contentsOf: result.hits)
                    inFlight -= 1
                    if enqueueNext() {
                        inFlight += 1
                    }
                }
                return (opened, failed, all)
            }

            var hits = bookResults.2
            hits.sort {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.matchedTokenCount != $1.matchedTokenCount {
                    return $0.matchedTokenCount > $1.matchedTokenCount
                }
                if $0.bookTitle != $1.bookTitle {
                    return $0.bookTitle.localizedCaseInsensitiveCompare($1.bookTitle) == .orderedAscending
                }
                return $0.page < $1.page
            }
            if hits.count > 80 {
                hits = Array(hits.prefix(80))
            }

            let status: String?
            if hits.isEmpty {
                if bookResults.0 == 0 {
                    status = bookResults.1 > 0
                        ? "Could not open any PDF files to search."
                        : "No searchable PDFs found."
                } else {
                    status = "No strong matches for “\(q)” in \(bookResults.0) book(s). Try a shorter phrase."
                }
            } else {
                status = nil
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.libraryTextHits = hits
                self.libraryTextHitIndex = hits.isEmpty ? 0 : 0
                self.libraryTextSearching = false
                self.libraryTextSearchActive = true
                self.libraryTextSearchStatus = status
            }
        }
    }

    func clearLibraryTextSearch() {
        libraryTextSearchTask?.cancel()
        libraryTextQuery = ""
        libraryTextHits = []
        libraryTextHitIndex = 0
        libraryTextSearching = false
        libraryTextSearchActive = false
        libraryTextSearchStatus = nil
    }

    func openLibraryTextHit(_ hit: LibraryTextSearchHit) {
        if let idx = libraryTextHits.firstIndex(of: hit) {
            libraryTextHitIndex = idx
        }
        selectPDF(hit.itemID, page: hit.page)
    }

    var canGoToPreviousLibraryHit: Bool {
        libraryTextSearchActive && !libraryTextHits.isEmpty && libraryTextHitIndex > 0
    }

    var canGoToNextLibraryHit: Bool {
        libraryTextSearchActive
            && !libraryTextHits.isEmpty
            && libraryTextHitIndex < libraryTextHits.count - 1
    }

    func goToPreviousLibraryHit() {
        guard canGoToPreviousLibraryHit else { return }
        libraryTextHitIndex -= 1
        openLibraryTextHit(libraryTextHits[libraryTextHitIndex])
    }

    func goToNextLibraryHit() {
        guard canGoToNextLibraryHit else { return }
        libraryTextHitIndex += 1
        openLibraryTextHit(libraryTextHits[libraryTextHitIndex])
    }

    func selectLibraryHitIndex(_ index: Int) {
        guard libraryTextHits.indices.contains(index) else { return }
        libraryTextHitIndex = index
        openLibraryTextHit(libraryTextHits[index])
    }

    // MARK: - UI state persistence

    private func restoreUIState() {
        guard !didRestoreState else { return }
        didRestoreState = true
        if let raw = AppPreferences.string(.rulesRefMode),
           let modeValue = RulesReferenceMode(rawValue: raw) {
            mode = modeValue
        }
        query = AppPreferences.string(.rulesRefQuery) ?? ""
        if let raw = AppPreferences.string(.rulesRefCategory),
           let category = RuleCategory(rawValue: raw) {
            selectedCategory = category
        }
        if let raw = AppPreferences.string(.rulesRefEdition),
           let edition = Edition(rawValue: raw) {
            editionFilter = edition
        }
        if let id = AppPreferences.string(.rulesRefSelectedID), store.entry(id: id) != nil {
            selectedID = id
        }
        if let raw = AppPreferences.string(.rulesRefLibraryLayout),
           let layout = LibraryShelfLayout(rawValue: raw) {
            libraryLayout = layout
        }
        if let raw = AppPreferences.string(.rulesRefLibrarySort),
           let sort = LibraryShelfSort(rawValue: raw) {
            librarySort = sort
        }
        if let uuid = AppPreferences.string(.rulesRefLibraryItem).flatMap(UUID.init(uuidString:)),
           pdfLibrary.item(id: uuid) != nil {
            selectedLibraryItemID = uuid
        }
        let page = AppPreferences.int(.rulesRefPDFPage)
        if page > 0 { pdfTargetPage = page }
        if let data = AppPreferences.data(.rulesRefZoomMap),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var map: [UUID: PDFZoomPreset] = [:]
            for (k, v) in decoded {
                if let id = UUID(uuidString: k), let preset = PDFZoomPreset(rawValue: v) {
                    map[id] = preset
                }
            }
            pdfZoomByItemID = map
        }
        if selectedID == nil {
            selectedID = results.first?.entry.id ?? store.entries.first?.id
        }
    }

    func persistUIState() {
        // Capture runs must not overwrite the interactive user's Rules Reference prefs.
        guard !MarketingScreenshotExporter.isEnabled else { return }
        AppPreferences.set(mode.rawValue, for: .rulesRefMode)
        AppPreferences.set(query, for: .rulesRefQuery)
        AppPreferences.set(selectedCategory?.rawValue, for: .rulesRefCategory)
        AppPreferences.set(editionFilter?.rawValue, for: .rulesRefEdition)
        AppPreferences.set(selectedID, for: .rulesRefSelectedID)
        AppPreferences.set(libraryLayout.rawValue, for: .rulesRefLibraryLayout)
        AppPreferences.set(librarySort.rawValue, for: .rulesRefLibrarySort)
        AppPreferences.set(selectedLibraryItemID?.uuidString, for: .rulesRefLibraryItem)
        AppPreferences.set(pdfTargetPage, for: .rulesRefPDFPage)
        var zoomRaw: [String: String] = [:]
        for (id, preset) in pdfZoomByItemID {
            zoomRaw[id.uuidString] = preset.rawValue
        }
        if let data = try? JSONEncoder().encode(zoomRaw) {
            AppPreferences.set(data, for: .rulesRefZoomMap)
        }
    }

    private func sortLibraryItems(_ items: [PDFLibraryItem]) -> [PDFLibraryItem] {
        switch librarySort {
        case .title:
            return items.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .dateAdded:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .bookKey:
            return items.sorted { a, b in
                let ak = a.bookKey?.lowercased() ?? "\u{FFFF}"
                let bk = b.bookKey?.lowercased() ?? "\u{FFFF}"
                if ak != bk { return ak < bk }
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            }
        case .editionTag:
            return items.sorted { a, b in
                let at = a.editionTags.first?.lowercased() ?? "\u{FFFF}"
                let bt = b.editionTags.first?.lowercased() ?? "\u{FFFF}"
                if at != bt { return at < bt }
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            }
        }
    }

    /// Keep selection inside the current result set; prefer first row when missing.
    func syncRuleSelectionToResults(preferTopHit: Bool = false) {
        let rows = results
        if preferTopHit {
            selectedID = rows.first?.entry.id ?? store.entries.first?.id
            return
        }
        if let selectedID, rows.contains(where: { $0.entry.id == selectedID }) {
            return
        }
        selectedID = rows.first?.entry.id ?? store.entries.first?.id
    }
}
