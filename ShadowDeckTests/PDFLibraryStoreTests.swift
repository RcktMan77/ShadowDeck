//
//  PDFLibraryStoreTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class PDFLibraryStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-PDFLib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try super.tearDownWithError()
    }

    func testAddCopyBindAndReload() throws {
        let source = root.appendingPathComponent("sample.pdf")
        // Minimal PDF-ish bytes that PDFKit may or may not fully parse; header is required.
        // Use a tiny real PDF stream.
        let pdf = minimalPDFData()
        try pdf.write(to: source)

        var store = PDFLibraryStore(items: [], rootDirectory: root)
        let item = try store.addPDF(from: source, title: "SR5 Test", bookKey: "sr5-crb")
        XCTAssertEqual(item.title, "SR5 Test")
        XCTAssertEqual(item.bookKey, "sr5-crb")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: item).path))

        let reloaded = PDFLibraryStore.load(rootDirectory: root)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.item(bookKey: "sr5-crb")?.title, "SR5 Test")

        var store2 = reloaded
        try store2.setBookKey(id: item.id, bookKey: "sr6-core")
        XCTAssertEqual(store2.item(id: item.id)?.bookKey, "sr6-core")
        XCTAssertNil(store2.item(bookKey: "sr5-crb"))

        try store2.setLastOpenedPage(id: item.id, page: 42)
        XCTAssertEqual(store2.item(id: item.id)?.lastOpenedPage, 42)

        try store2.setTitle(id: item.id, title: "  Renamed Core  ")
        XCTAssertEqual(store2.item(id: item.id)?.title, "Renamed Core")

        // Cover extracted on add when page 0 is renderable.
        if store2.item(id: item.id)?.coverFileName != nil {
            XCTAssertNotNil(store2.coverURL(for: store2.item(id: item.id)!))
        }

        try store2.setShelfSection(id: item.id, section: .sourcebook)
        XCTAssertEqual(store2.item(id: item.id)?.shelfSection, .sourcebook)

        try store2.remove(id: item.id)
        XCTAssertTrue(store2.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: item).path))
    }

    func testRejectNonPDF() throws {
        let source = root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: source)
        var store = PDFLibraryStore(items: [], rootDirectory: root)
        XCTAssertThrowsError(try store.addPDF(from: source)) { error in
            XCTAssertEqual(error as? PDFLibraryStoreError, .invalidPDF)
        }
    }

    func testShelfSectionInferenceAndLegacyDecode() throws {
        XCTAssertEqual(PDFShelfSection.inferred(bookKey: "sr5-crb", title: "Anything"), .coreRulebook)
        XCTAssertEqual(PDFShelfSection.inferred(bookKey: nil, title: "SRM 05-01 Chasin' the Wind"), .mission)
        XCTAssertEqual(PDFShelfSection.inferred(bookKey: nil, title: "Run & Gun"), .sourcebook)

        // Legacy JSON without shelfSection / coverFileName still loads.
        let legacy = """
        {"schemaVersion":1,"items":[{"id":"\(UUID().uuidString)","title":"SR5 Core Rulebook","bookKey":"sr5-crb","editionTags":[],"fileName":"document.pdf","pageCount":400,"lastOpenedPage":1,"addedAt":"2020-01-01T00:00:00Z","notes":"","byteCount":10}]}
        """
        let data = Data(legacy.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(PDFLibraryFile.self, from: data)
        XCTAssertEqual(file.items.count, 1)
        XCTAssertEqual(file.items[0].shelfSection, .coreRulebook)
        XCTAssertNil(file.items[0].coverFileName)
        XCTAssertEqual(file.items[0].pageOffset, 0)
    }

    func testPageOffsetPrintToPDFMapping() throws {
        // 2 pages of front matter: printed p.2 → PDF page 4.
        var item = PDFLibraryItem(title: "SR5", pageOffset: 2)
        XCTAssertEqual(item.pdfPage(forPrintedPage: 1), 3)
        XCTAssertEqual(item.pdfPage(forPrintedPage: 2), 4)
        XCTAssertEqual(item.pdfPage(forPrintedPage: 44), 46)
        XCTAssertNil(item.printedPage(forPDFPage: 1))
        XCTAssertNil(item.printedPage(forPDFPage: 2))
        XCTAssertEqual(item.printedPage(forPDFPage: 3), 1)
        XCTAssertEqual(item.printedPage(forPDFPage: 4), 2)

        let source = root.appendingPathComponent("sample.pdf")
        try minimalPDFData().write(to: source)
        var store = PDFLibraryStore(items: [], rootDirectory: root)
        let added = try store.addPDF(from: source, title: "SR5")
        try store.setPageOffset(id: added.id, pageOffset: 2)
        XCTAssertEqual(store.item(id: added.id)?.pageOffset, 2)
        XCTAssertEqual(store.item(id: added.id)?.pdfPage(forPrintedPage: 2), 4)
    }

    /// Tiny valid-enough PDF for file copy tests.
    private func minimalPDFData() -> Data {
        // 1-page blank PDF (public domain minimal).
        let s = """
        %PDF-1.1
        1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj
        2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj
        3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>endobj
        xref
        0 4
        0000000000 65535 f \
        0000000010 00000 n \
        0000000060 00000 n \
        0000000117 00000 n \
        trailer<< /Size 4 /Root 1 0 R >>
        startxref
        190
        %%EOF
        """
        return Data(s.utf8)
    }
}
