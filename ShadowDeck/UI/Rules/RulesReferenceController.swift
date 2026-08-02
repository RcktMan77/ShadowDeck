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
    @Published var query: String = ""
    @Published var selectedCategory: RuleCategory?
    @Published var editionFilter: Edition?
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

    init(
        store: RulesReferenceStore = .loadBundled(),
        pdfLibrary: PDFLibraryStore = PDFLibraryStore.loadDefault()
    ) {
        self.store = store
        self.pdfLibrary = pdfLibrary
        restoreUIState()
    }

    /// Library is in reader phase when a book is open.
    var isLibraryReaderOpen: Bool {
        mode == .library && selectedLibraryItemID != nil
    }

    var selectedEntry: RuleEntry? {
        guard let selectedID else { return nil }
        return store.entry(id: selectedID)
            ?? results.first(where: { $0.entry.id == selectedID })?.entry
    }

    var selectedPDFItem: PDFLibraryItem? {
        guard let selectedLibraryItemID else { return nil }
        return pdfLibrary.item(id: selectedLibraryItemID)
    }

    var results: [RulesReferenceSearchResult] {
        store.search(
            query: query,
            category: selectedCategory,
            edition: editionFilter,
            limit: 80
        )
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

    func applyOpenContext(
        query initialQuery: String? = nil,
        edition: Edition? = nil,
        calcContext: RulesCalcContext? = nil
    ) {
        Task { @MainActor in
            self.mode = .reference
            self.returnToCardID = nil
            self.selectedCategory = nil
            if let calcContext {
                self.calcContext = calcContext
                self.editionFilter = calcContext.edition
            } else if let edition {
                self.editionFilter = edition
            }
            if let initialQuery {
                let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self.query = trimmed
                    self.selectedID = self.results.first?.entry.id ?? self.store.entries.first?.id
                    self.requestTopicsScrollToSelection()
                    self.persistUIState()
                    return
                }
            }
            self.syncRuleSelectionToResults()
            self.requestTopicsScrollToSelection()
            self.persistUIState()
        }
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
            if self.mode != .library { self.mode = .library }
            if self.selectedLibraryItemID != id { self.selectedLibraryItemID = id }
            if self.pdfTargetPage != resolvedPage { self.pdfTargetPage = resolvedPage }
            self.pdfNavigationEpoch &+= 1
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
            if self.mode != .library { self.mode = .library }
            if self.selectedLibraryItemID != itemID { self.selectedLibraryItemID = itemID }
            if self.pdfTargetPage != pdfPage { self.pdfTargetPage = pdfPage }
            self.pdfNavigationEpoch &+= 1
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
            // Parallelize across books (one PDFDocument per task — PDFKit is not cross-thread safe).
            let bookResults = await withTaskGroup(
                of: (opened: Bool, failed: Bool, hits: [LibraryTextSearchHit]).self
            ) { group in
                for (id, title, url) in fileURLs {
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
                        let pageHits = Self.rankPDFDocument(doc, query: q)
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
                }

                var opened = 0
                var failed = 0
                var all: [LibraryTextSearchHit] = []
                for await result in group {
                    if Task.isCancelled { break }
                    if result.opened { opened += 1 }
                    if result.failed { failed += 1 }
                    all.append(contentsOf: result.hits)
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

    /// Ranked page hits for one document.
    private struct RankedPageHit: Sendable {
        var page: Int
        var snippet: String
        var score: Int
        var matchedTokens: Int
        var tokenCount: Int
    }

    /// Phrase-first, then token intersection via PDFKit `findString` (not page.string alone).
    /// Multi-word queries prefer pages containing **all** tokens; partial matches rank lower.
    nonisolated private static func rankPDFDocument(
        _ doc: PDFDocument,
        query: String
    ) -> [RankedPageHit] {
        let options: NSString.CompareOptions = [.caseInsensitive]
        let tokens = tokenizeQuery(query)
        let tokenCount = max(1, tokens.count)

        // 1) Contiguous phrase — highest relevance.
        let phraseSels = doc.findString(query, withOptions: options)
        if !phraseSels.isEmpty {
            var hits: [RankedPageHit] = []
            var seen = Set<Int>()
            for sel in phraseSels {
                guard let page = sel.pages.first else { continue }
                let pageIndex = doc.index(for: page) + 1
                if seen.contains(pageIndex) { continue }
                seen.insert(pageIndex)
                hits.append(RankedPageHit(
                    page: pageIndex,
                    snippet: snippet(from: sel, fallback: query, page: page, tokens: tokens),
                    score: 10_000 + tokenCount * 100,
                    matchedTokens: tokenCount,
                    tokenCount: tokenCount
                ))
                if hits.count >= 20 { break }
            }
            return hits
        }

        guard !tokens.isEmpty else { return [] }

        // 2) Per-token page sets from PDFKit (reliable even when page.string is sparse).
        var pagesByToken: [String: Set<Int>] = [:]
        for token in tokens {
            var pages = Set<Int>()
            for sel in doc.findString(token, withOptions: options) {
                guard let page = sel.pages.first else { continue }
                pages.insert(doc.index(for: page) + 1)
            }
            pagesByToken[token] = pages
        }

        // Union of all pages that match at least one token.
        var candidatePages = Set<Int>()
        for pages in pagesByToken.values {
            candidatePages.formUnion(pages)
        }

        // Prefer full intersection; if empty, allow strong partials (≥ ceil(n*2/3) or n-1).
        let minTokensForPartial: Int = {
            if tokens.count <= 1 { return 1 }
            if tokens.count == 2 { return 2 }
            return max(2, tokens.count - 1)
        }()

        var ranked: [RankedPageHit] = []
        for pageIndex in candidatePages {
            let matched = tokens.filter { pagesByToken[$0]?.contains(pageIndex) == true }
            let matchedCount = matched.count
            guard matchedCount >= minTokensForPartial else { continue }

            let page = doc.page(at: pageIndex - 1)
            let pageText = page?.string ?? ""
            let snippet = multiTokenSnippet(pageText: pageText, tokens: matched, pageIndex: pageIndex)

            // Score: full match >> partial; density of matched tokens; rarity (fewer total hits).
            var score = matchedCount * 1_000
            if matchedCount == tokenCount {
                score += 5_000
            }
            // Prefer pages where tokens cluster (simple window check).
            if matchedCount >= 2, tokenProximityBonus(pageText: pageText, tokens: matched) {
                score += 800
            }
            // Slight boost for rarer multi-token pages (fewer total attribute-only noise).
            score += matchedCount * matchedCount * 50

            ranked.append(RankedPageHit(
                page: pageIndex,
                snippet: snippet,
                score: score,
                matchedTokens: matchedCount,
                tokenCount: tokenCount
            ))
        }

        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.matchedTokens != $1.matchedTokens { return $0.matchedTokens > $1.matchedTokens }
            return $0.page < $1.page
        }
        // Prefer all-token hits first when listing; keep partials only if few full hits.
        let full = ranked.filter { $0.matchedTokens == tokenCount }
        if full.count >= 3 {
            return Array(full.prefix(20))
        }
        return Array(ranked.prefix(20))
    }

    nonisolated private static func tokenizeQuery(_ query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || ",.;:·/\\()[]{}".contains($0) })
            .map(String.init)
            .filter { $0.count >= 3 }
            // Drop ultra-common filler that blows up result sets.
            .filter { !["the", "and", "for", "with", "from", "that", "this", "your"].contains($0) }
    }

    nonisolated private static func snippet(
        from sel: PDFSelection,
        fallback: String,
        page: PDFPage,
        tokens: [String]
    ) -> String {
        let raw = (sel.string ?? fallback)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.count >= 12 {
            return raw.count > 140 ? String(raw.prefix(137)) + "…" : raw
        }
        return multiTokenSnippet(pageText: page.string ?? "", tokens: tokens, pageIndex: 0)
    }

    nonisolated private static func multiTokenSnippet(
        pageText: String,
        tokens: [String],
        pageIndex: Int
    ) -> String {
        let collapsed = pageText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let lower = collapsed.lowercased()
        // Find earliest token occurrence and take a window around it.
        var bestRange: Range<String.Index>?
        for token in tokens {
            if let r = lower.range(of: token) {
                if bestRange == nil || r.lowerBound < bestRange!.lowerBound {
                    bestRange = r
                }
            }
        }
        guard let range = bestRange else {
            let joined = tokens.joined(separator: " · ")
            return pageIndex > 0 ? "p. \(pageIndex): \(joined)" : joined
        }
        let start = collapsed.index(range.lowerBound, offsetBy: -40, limitedBy: collapsed.startIndex)
            ?? collapsed.startIndex
        let end = collapsed.index(range.upperBound, offsetBy: 80, limitedBy: collapsed.endIndex)
            ?? collapsed.endIndex
        var slice = String(collapsed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start != collapsed.startIndex { slice = "…" + slice }
        if end != collapsed.endIndex { slice += "…" }
        return slice.isEmpty ? "Match on page \(pageIndex)" : slice
    }

    /// True if at least two tokens appear within a short character window.
    nonisolated private static func tokenProximityBonus(pageText: String, tokens: [String]) -> Bool {
        let lower = pageText.lowercased()
        var positions: [Int] = []
        for token in tokens {
            if let r = lower.range(of: token) {
                positions.append(lower.distance(from: lower.startIndex, to: r.lowerBound))
            }
        }
        guard positions.count >= 2 else { return false }
        positions.sort()
        for i in 0..<(positions.count - 1) {
            if positions[i + 1] - positions[i] <= 80 { return true }
        }
        return false
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

    private enum DefaultsKey {
        static let mode = "RulesRef.mode"
        static let query = "RulesRef.query"
        static let category = "RulesRef.category"
        static let edition = "RulesRef.edition"
        static let selectedID = "RulesRef.selectedID"
        static let libraryLayout = "RulesRef.libraryLayout"
        static let librarySort = "RulesRef.librarySort"
        static let libraryItem = "RulesRef.libraryItem"
        static let pdfPage = "RulesRef.pdfPage"
        static let zoomMap = "RulesRef.zoomMap"
    }

    private func restoreUIState() {
        guard !didRestoreState else { return }
        didRestoreState = true
        let d = UserDefaults.standard
        if let raw = d.string(forKey: DefaultsKey.mode),
           let m = RulesReferenceMode(rawValue: raw)
        {
            mode = m
        }
        query = d.string(forKey: DefaultsKey.query) ?? ""
        if let raw = d.string(forKey: DefaultsKey.category),
           let c = RuleCategory(rawValue: raw)
        {
            selectedCategory = c
        }
        if let raw = d.string(forKey: DefaultsKey.edition),
           let e = Edition(rawValue: raw)
        {
            editionFilter = e
        }
        if let id = d.string(forKey: DefaultsKey.selectedID), store.entry(id: id) != nil {
            selectedID = id
        }
        if let raw = d.string(forKey: DefaultsKey.libraryLayout),
           let layout = LibraryShelfLayout(rawValue: raw)
        {
            libraryLayout = layout
        }
        if let raw = d.string(forKey: DefaultsKey.librarySort),
           let sort = LibraryShelfSort(rawValue: raw)
        {
            librarySort = sort
        }
        if let uuid = d.string(forKey: DefaultsKey.libraryItem).flatMap(UUID.init(uuidString:)),
           pdfLibrary.item(id: uuid) != nil
        {
            selectedLibraryItemID = uuid
        }
        let page = d.integer(forKey: DefaultsKey.pdfPage)
        if page > 0 { pdfTargetPage = page }
        if let data = d.data(forKey: DefaultsKey.zoomMap),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
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
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: DefaultsKey.mode)
        d.set(query, forKey: DefaultsKey.query)
        d.set(selectedCategory?.rawValue, forKey: DefaultsKey.category)
        d.set(editionFilter?.rawValue, forKey: DefaultsKey.edition)
        d.set(selectedID, forKey: DefaultsKey.selectedID)
        d.set(libraryLayout.rawValue, forKey: DefaultsKey.libraryLayout)
        d.set(librarySort.rawValue, forKey: DefaultsKey.librarySort)
        d.set(selectedLibraryItemID?.uuidString, forKey: DefaultsKey.libraryItem)
        d.set(pdfTargetPage, forKey: DefaultsKey.pdfPage)
        var zoomRaw: [String: String] = [:]
        for (id, preset) in pdfZoomByItemID {
            zoomRaw[id.uuidString] = preset.rawValue
        }
        if let data = try? JSONEncoder().encode(zoomRaw) {
            d.set(data, forKey: DefaultsKey.zoomMap)
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
