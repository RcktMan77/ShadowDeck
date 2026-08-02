//
//  PDFLibraryStore.swift
//  ShadowDeck
//
//  Copies user PDFs into Application Support and tracks metadata in library.json.
//  Extracts a first-page cover image for shelf gallery / list thumbnails.
//

import AppKit
import Foundation
import PDFKit

public enum PDFLibraryStoreError: Error, Equatable, LocalizedError {
    case rootUnavailable(String)
    case copyFailed(String)
    case notFound
    case invalidPDF

    public var errorDescription: String? {
        switch self {
        case .rootUnavailable(let d): return "PDF library unavailable: \(d)"
        case .copyFailed(let d): return "Could not add PDF: \(d)"
        case .notFound: return "PDF not found in library."
        case .invalidPDF: return "That file does not appear to be a readable PDF."
        }
    }
}

public struct PDFLibraryStore: Sendable {
    public var items: [PDFLibraryItem]
    public let rootDirectory: URL

    /// `FileManager` is not `Sendable`; never store it — use the process default at call sites.
    private var fm: FileManager { .default }

    private var manifestURL: URL {
        rootDirectory.appendingPathComponent("library.json")
    }

    public static let coverFileName = "cover.jpg"
    /// Long edge for cached cover JPEGs (shelf cards + list thumbs).
    public static let coverLongEdge: CGFloat = 512

    public init(items: [PDFLibraryItem] = [], rootDirectory: URL) {
        self.items = items
        self.rootDirectory = rootDirectory
    }

    // MARK: - Locations

    public static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("ShadowDeck", isDirectory: true)
            .appendingPathComponent("PDFLibrary", isDirectory: true)
    }

    public static func loadDefault(fileManager: FileManager = .default) -> Self {
        do {
            let root = try defaultRoot(fileManager: fileManager)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            return load(rootDirectory: root, fileManager: fileManager)
        } catch {
            // Ephemeral empty store if Application Support is blocked.
            let tmp = fileManager.temporaryDirectory
                .appendingPathComponent("ShadowDeck-PDFLibrary-Empty", isDirectory: true)
            try? fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
            return Self(items: [], rootDirectory: tmp)
        }
    }

    public static func load(rootDirectory: URL, fileManager: FileManager = .default) -> Self {
        let manifest = rootDirectory.appendingPathComponent("library.json")
        guard fileManager.fileExists(atPath: manifest.path),
              let data = try? Data(contentsOf: manifest)
        else {
            return Self(items: [], rootDirectory: rootDirectory)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(PDFLibraryFile.self, from: data) else {
            return Self(items: [], rootDirectory: rootDirectory)
        }
        return Self(items: file.items, rootDirectory: rootDirectory)
    }

    // MARK: - Query

    public func item(id: UUID) -> PDFLibraryItem? {
        items.first { $0.id == id }
    }

    public func item(bookKey: String) -> PDFLibraryItem? {
        let key = bookKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return items.first { ($0.bookKey ?? "").lowercased() == key }
    }

    public func itemDirectory(for item: PDFLibraryItem) -> URL {
        rootDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
    }

    public func fileURL(for item: PDFLibraryItem) -> URL {
        itemDirectory(for: item).appendingPathComponent(item.fileName)
    }

    public func coverURL(for item: PDFLibraryItem) -> URL? {
        guard let name = item.coverFileName, !name.isEmpty else { return nil }
        let url = itemDirectory(for: item).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Mutating

    @discardableResult
    public mutating func addPDF(
        from sourceURL: URL,
        title: String? = nil,
        bookKey: String? = nil,
        editionTags: [String] = [],
        shelfSection: PDFShelfSection? = nil
    ) throws -> PDFLibraryItem {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw PDFLibraryStoreError.copyFailed(error.localizedDescription)
        }

        // Validate PDF header / PDFKit open.
        guard data.starts(with: Data("%PDF".utf8)) || PDFDocument(data: data) != nil else {
            throw PDFLibraryStoreError.invalidPDF
        }
        let document = PDFDocument(data: data)
        let pageCount = document?.pageCount

        let id = UUID()
        let fileName = "document.pdf"
        let dir = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(fileName)
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try data.write(to: dest, options: .atomic)
        } catch {
            throw PDFLibraryStoreError.copyFailed(error.localizedDescription)
        }

        let resolvedTitle: String = {
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return sourceURL.deletingPathExtension().lastPathComponent
        }()

        var coverName: String?
        if let document {
            let coverDest = dir.appendingPathComponent(Self.coverFileName)
            if Self.writeCoverJPEG(from: document, to: coverDest) {
                coverName = Self.coverFileName
            }
        }

        let section = shelfSection ?? .inferred(bookKey: bookKey, title: resolvedTitle)
        let item = PDFLibraryItem(
            id: id,
            title: resolvedTitle,
            bookKey: bookKey,
            editionTags: editionTags,
            shelfSection: section,
            fileName: fileName,
            coverFileName: coverName,
            pageCount: pageCount,
            lastOpenedPage: 1,
            byteCount: data.count
        )
        items.append(item)
        try saveManifest()
        return item
    }

    public mutating func remove(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw PDFLibraryStoreError.notFound
        }
        items.remove(at: index)
        let dir = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fm.removeItem(at: dir)
        try saveManifest()
    }

    public mutating func update(_ item: PDFLibraryItem) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            throw PDFLibraryStoreError.notFound
        }
        items[index] = item
        try saveManifest()
    }

    public mutating func setBookKey(id: UUID, bookKey: String?) throws {
        guard var item = item(id: id) else { throw PDFLibraryStoreError.notFound }
        // Unique book keys: clear others with same key.
        if let bookKey, !bookKey.isEmpty {
            for i in items.indices where items[i].id != id && items[i].bookKey == bookKey {
                items[i].bookKey = nil
            }
            item.bookKey = bookKey
        } else {
            item.bookKey = nil
        }
        try update(item)
    }

    public mutating func setTitle(id: UUID, title: String) throws {
        guard var item = item(id: id) else { throw PDFLibraryStoreError.notFound }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = trimmed.isEmpty ? "Untitled PDF" : trimmed
        try update(item)
    }

    public mutating func setShelfSection(id: UUID, section: PDFShelfSection) throws {
        guard var item = item(id: id) else { throw PDFLibraryStoreError.notFound }
        item.shelfSection = section
        try update(item)
    }

    /// Unnumbered PDF pages before printed page 1 (for chip → PDF mapping).
    public mutating func setPageOffset(id: UUID, pageOffset: Int) throws {
        guard var item = item(id: id) else { throw PDFLibraryStoreError.notFound }
        item.pageOffset = max(0, pageOffset)
        try update(item)
    }

    public mutating func setLastOpenedPage(id: UUID, page: Int) throws {
        guard var item = item(id: id) else { throw PDFLibraryStoreError.notFound }
        item.lastOpenedPage = max(1, page)
        try update(item)
    }

    /// Ensure a cover JPEG exists (for items imported before cover support).
    @discardableResult
    public mutating func ensureCover(id: UUID) -> Bool {
        guard var item = item(id: id) else { return false }
        if let url = coverURL(for: item) {
            _ = url
            return true
        }
        let pdfURL = fileURL(for: item)
        guard let document = PDFDocument(url: pdfURL) else { return false }
        let dir = itemDirectory(for: item)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Self.coverFileName)
        guard Self.writeCoverJPEG(from: document, to: dest) else { return false }
        item.coverFileName = Self.coverFileName
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = item
            try? saveManifest()
        }
        return true
    }

    /// Re-render cover from page 1 (e.g. after user request).
    @discardableResult
    public mutating func refreshCover(id: UUID) -> Bool {
        guard var item = item(id: id) else { return false }
        guard let document = PDFDocument(url: fileURL(for: item)) else { return false }
        let dest = itemDirectory(for: item).appendingPathComponent(Self.coverFileName)
        guard Self.writeCoverJPEG(from: document, to: dest) else { return false }
        item.coverFileName = Self.coverFileName
        try? update(item)
        return true
    }

    // MARK: - Cover rendering

    /// Render page 0 to a JPEG on disk. Returns false if render/write fails.
    public static func writeCoverJPEG(
        from document: PDFDocument,
        to destination: URL,
        longEdge: CGFloat = coverLongEdge
    ) -> Bool {
        guard let page = document.page(at: 0) else { return false }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return false }
        let scale = longEdge / max(bounds.width, bounds.height)
        let size = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else {
            return false
        }
        do {
            try jpeg.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func saveManifest() throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let file = PDFLibraryFile(items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: manifestURL, options: .atomic)
    }
}
