//
//  PDFLibrary.swift
//  ShadowDeck
//
//  User-owned PDF rulebook shelf (local only — never bundled or uploaded).
//

import Foundation

// MARK: - Shelf section

/// High-level grouping on the Library shelf (core, missions, etc.).
public enum PDFShelfSection: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case coreRulebook
    case mission
    case sourcebook
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .coreRulebook: "Core Rulebooks"
        case .mission: "Missions & Adventures"
        case .sourcebook: "Sourcebooks"
        case .other: "Other"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .coreRulebook: 0
        case .mission: 1
        case .sourcebook: 2
        case .other: 3
        }
    }

    public var systemImage: String {
        switch self {
        case .coreRulebook: "book.closed.fill"
        case .mission: "flag.fill"
        case .sourcebook: "books.vertical.fill"
        case .other: "doc.richtext.fill"
        }
    }

    /// Best-effort default from a book key / title (user can override).
    public static func inferred(bookKey: String?, title: String) -> Self {
        let key = (bookKey ?? "").lowercased()
        let t = title.lowercased()
        if key == PageRef.BookKey.sr4a
            || key == PageRef.BookKey.sr5CRB
            || key == PageRef.BookKey.sr6Core
            || key.contains("crb")
            || key.contains("core")
            || t.contains("core rulebook")
            || t.contains("core book")
            || t.hasSuffix(" core")
            || t.contains("20th anniversary") {
            return .coreRulebook
        }
        if key.hasPrefix("srm")
            || key.contains("mission")
            || t.contains("mission")
            || t.contains("adventure")
            || t.contains("chasin")
            || t.contains("campaign") {
            return .mission
        }
        if key.contains("run")
            || t.contains("run & gun")
            || t.contains("run faster")
            || t.contains("data trails")
            || t.contains("street grimoire")
            || t.contains("chrome flesh")
            || t.contains("sourcebook")
            || t.contains("companion") {
            return .sourcebook
        }
        return .other
    }
}

// MARK: - Library item

public struct PDFLibraryItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    /// Role binding for page-ref chips (e.g. `sr5-crb`).
    public var bookKey: String?
    public var editionTags: [String]
    /// Shelf grouping (core / mission / sourcebook / other).
    public var shelfSection: PDFShelfSection
    /// File name inside `PDFLibrary/<id>/` (usually `document.pdf`).
    public var fileName: String
    /// Cached cover filename inside the item folder (`cover.jpg`), if extracted.
    public var coverFileName: String?
    public var pageCount: Int?
    public var lastOpenedPage: Int
    /// Unnumbered PDF pages before printed page 1 (covers, title leaf, etc.).
    /// Page chips use printed numbers; PDF index = printPage + pageOffset.
    /// Example: 2 pages of front matter → printed p.2 is PDF page 4.
    public var pageOffset: Int
    public var addedAt: Date
    public var notes: String
    public var byteCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        bookKey: String? = nil,
        editionTags: [String] = [],
        shelfSection: PDFShelfSection? = nil,
        fileName: String = "document.pdf",
        coverFileName: String? = nil,
        pageCount: Int? = nil,
        lastOpenedPage: Int = 1,
        pageOffset: Int = 0,
        addedAt: Date = Date(),
        notes: String = "",
        byteCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.bookKey = bookKey
        self.editionTags = editionTags
        self.shelfSection = shelfSection ?? .inferred(bookKey: bookKey, title: title)
        self.fileName = fileName
        self.coverFileName = coverFileName
        self.pageCount = pageCount
        self.lastOpenedPage = max(1, lastOpenedPage)
        self.pageOffset = max(0, pageOffset)
        self.addedAt = addedAt
        self.notes = notes
        self.byteCount = max(0, byteCount)
    }

    public var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled PDF" : t
    }

    public var hasCover: Bool {
        coverFileName != nil && !(coverFileName?.isEmpty ?? true)
    }

    /// Convert a printed page number (as on the page / in rule chips) to a 1-based PDF index.
    public func pdfPage(forPrintedPage printed: Int) -> Int {
        max(1, printed + pageOffset)
    }

    /// Convert a 1-based PDF index to a printed page number (nil when still in front matter).
    public func printedPage(forPDFPage pdfPage: Int) -> Int? {
        let printed = pdfPage - pageOffset
        return printed >= 1 ? printed : nil
    }

    // Backward-compatible decode for libraries saved before shelfSection / cover / offset.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        bookKey = try c.decodeIfPresent(String.self, forKey: .bookKey)
        editionTags = try c.decodeIfPresent([String].self, forKey: .editionTags) ?? []
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? "document.pdf"
        coverFileName = try c.decodeIfPresent(String.self, forKey: .coverFileName)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        lastOpenedPage = max(1, try c.decodeIfPresent(Int.self, forKey: .lastOpenedPage) ?? 1)
        pageOffset = max(0, try c.decodeIfPresent(Int.self, forKey: .pageOffset) ?? 0)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        byteCount = max(0, try c.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0)
        if let section = try c.decodeIfPresent(PDFShelfSection.self, forKey: .shelfSection) {
            shelfSection = section
        } else {
            shelfSection = .inferred(bookKey: bookKey, title: title)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(bookKey, forKey: .bookKey)
        try c.encode(editionTags, forKey: .editionTags)
        try c.encode(shelfSection, forKey: .shelfSection)
        try c.encode(fileName, forKey: .fileName)
        try c.encodeIfPresent(coverFileName, forKey: .coverFileName)
        try c.encodeIfPresent(pageCount, forKey: .pageCount)
        try c.encode(lastOpenedPage, forKey: .lastOpenedPage)
        try c.encode(pageOffset, forKey: .pageOffset)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encode(notes, forKey: .notes)
        try c.encode(byteCount, forKey: .byteCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, bookKey, editionTags, shelfSection, fileName, coverFileName
        case pageCount, lastOpenedPage, pageOffset, addedAt, notes, byteCount
    }
}

public struct PDFLibraryFile: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var items: [PDFLibraryItem]

    public init(schemaVersion: Int = 1, items: [PDFLibraryItem] = []) {
        self.schemaVersion = schemaVersion
        self.items = items
    }
}

/// Well-known book keys offered when binding a PDF.
public enum PDFBookKeyCatalog {
    public static let curated: [(key: String, label: String)] = [
        (PageRef.BookKey.sr4a, "SR4A Core"),
        (PageRef.BookKey.sr5CRB, "SR5 Core Rulebook"),
        (PageRef.BookKey.sr6Core, "SR6 Core")
    ]
}
