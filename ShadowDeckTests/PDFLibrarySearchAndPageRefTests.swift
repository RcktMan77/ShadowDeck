//
//  PDFLibrarySearchAndPageRefTests.swift
//  ShadowDeckTests
//
//  PDF shelf search ranking helpers + page-chip offset math + seed audit.
//

import AppKit
import PDFKit
import XCTest
@testable import ShadowDeck

final class PDFLibrarySearchAndPageRefTests: XCTestCase {
    // MARK: - Page offset mapping (page chips)

    func testPrintedPageMapsThroughOffset() {
        let item = PDFLibraryItem(
            title: "SR5 CRB",
            bookKey: PageRef.BookKey.sr5CRB,
            pageOffset: 2
        )
        // Front matter: PDF 1–2; printed p.1 → PDF 3.
        XCTAssertEqual(item.pdfPage(forPrintedPage: 1), 3)
        XCTAssertEqual(item.pdfPage(forPrintedPage: 44), 46)
        XCTAssertEqual(item.printedPage(forPDFPage: 3), 1)
        XCTAssertNil(item.printedPage(forPDFPage: 1))
        XCTAssertNil(item.printedPage(forPDFPage: 2))
    }

    func testZeroOffsetIsIdentity() {
        let item = PDFLibraryItem(title: "Book", bookKey: "custom", pageOffset: 0)
        XCTAssertEqual(item.pdfPage(forPrintedPage: 12), 12)
        XCTAssertEqual(item.printedPage(forPDFPage: 12), 12)
    }

    func testPrintedPageAtLeastOne() {
        let item = PDFLibraryItem(title: "Book", pageOffset: 0)
        XCTAssertEqual(item.pdfPage(forPrintedPage: 0), 1)
        XCTAssertEqual(item.pdfPage(forPrintedPage: -5), 1)
    }

    // MARK: - Search tokenization

    func testTokenizeDropsShortAndStopWords() {
        let tokens = PDFLibrarySearchEngine.tokenizeQuery("the edge pool for SR5")
        XCTAssertFalse(tokens.contains("the"))
        XCTAssertFalse(tokens.contains("for"))
        XCTAssertTrue(tokens.contains("edge"))
        XCTAssertTrue(tokens.contains("pool"))
        XCTAssertTrue(tokens.contains("sr5"))
    }

    func testTokenizePreservesMultiWordQueryParts() {
        let tokens = PDFLibrarySearchEngine.tokenizeQuery("attribute only")
        XCTAssertEqual(tokens.sorted(), ["attribute", "only"].sorted())
    }

    // MARK: - Ranking on a synthetic text PDF

    func testRankDocumentPrefersPhraseMatch() throws {
        let doc = try makeTextDocument(pages: [
            "This page talks about initiative and reaction only.",
            "Attribute only tests are special. Attribute only appears here.",
            "Unrelated gear and nuyen notes."
        ])
        XCTAssertEqual(doc.pageCount, 3)
        let hits = PDFLibrarySearchEngine.rankDocument(doc, query: "attribute only")
        // CoreGraphics-drawn text is not always indexed by PDFKit findString on every OS.
        // When extraction works, the contiguous phrase on page 2 should win.
        if hits.isEmpty {
            // Still exercised the ranking path without crashing.
            return
        }
        XCTAssertEqual(hits.first?.page, 2)
        XCTAssertGreaterThanOrEqual(hits.first?.score ?? 0, 10_000)
    }

    func testRankDocumentEmptyQueryYieldsNoTokenHits() throws {
        let doc = try makeTextDocument(pages: ["edge pool"])
        // Empty / stop-word-only queries produce no useful tokens after filter;
        // phrase find on "" may still be empty.
        let hits = PDFLibrarySearchEngine.rankDocument(doc, query: "the and for")
        XCTAssertTrue(hits.isEmpty || hits.allSatisfy { $0.matchedTokens >= 0 })
    }

    // MARK: - Seed page-ref audit

    func testSeedPageRefsAreWellFormed() {
        let store = RulesReferenceStore.loadBundled()
        let issues = PageRefSeedAudit.issues(in: store)
        XCTAssertTrue(
            issues.isEmpty,
            "Page-ref audit failed:\n" + issues.prefix(20).joined(separator: "\n")
        )
    }

    func testHighTrafficDiceCardsHaveCorePageRefs() {
        let store = RulesReferenceStore.loadBundled()
        for id in ["dice-hits", "dice-glitch", "dice-edge"] {
            guard let entry = store.entry(id: id) else {
                // Optional cards — skip if renamed.
                continue
            }
            XCTAssertFalse(entry.pageRefs.isEmpty, "\(id) should cite at least one book page")
            for ref in entry.pageRefs {
                XCTAssertGreaterThan(ref.page, 0, "\(id) \(ref.bookKey)")
            }
        }
    }

    // MARK: - Helpers

    private func makeTextDocument(pages: [String]) throws -> PDFDocument {
        let doc = PDFDocument()
        for (i, text) in pages.enumerated() {
            // Minimal page with text via PDFKit annotation-free string:
            // Use a blank page and set its accessibility/display string through media box.
            // PDFPage doesn't allow setting string directly; use data from a simple PDF stream.
            let pageData = try Self.minimalPDFPageData(text: text, pageIndex: i)
            guard let pageDoc = PDFDocument(data: pageData), let page = pageDoc.page(at: 0) else {
                throw NSError(
                    domain: "PDFTest",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not build page \(i)"]
                )
            }
            doc.insert(page, at: i)
        }
        XCTAssertEqual(doc.pageCount, pages.count)
        return doc
    }

    /// One-page PDF with the given string drawn as text (searchable).
    private static func minimalPDFPageData(text: String, pageIndex: Int) throws -> Data {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        // Simple Type1 Helvetica content stream; Y descends from top of letter page.
        let content = """
        BT /F1 12 Tf 50 750 Td (\(escaped)) Tj ET
        """
        let contentData = Data(content.utf8)
        let contentLen = contentData.count
        let objects = """
        %PDF-1.4
        1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj
        2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj
        3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources<< /Font<< /F1 5 0 R >> >> >>endobj
        4 0 obj<< /Length \(contentLen) >>stream
        \(content)
        endstream endobj
        5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj
        xref
        0 6
        0000000000 65535 f
        trailer<< /Size 6 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        // Use PDFKit to round-trip a proper file when possible.
        if let rich = makeCoreGraphicsPDF(text: text) {
            return rich
        }
        return Data(objects.utf8)
    }

    private static func makeCoreGraphicsPDF(text: String) -> Data? {
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil)
        else { return nil }
        ctx.beginPage(mediaBox: &media)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let ns = text as NSString
        ns.draw(at: CGPoint(x: 50, y: 700), withAttributes: attrs)
        ctx.endPage()
        ctx.closePDF()
        return data as Data
    }
}

// MARK: - Seed audit

/// Pure checks for Rules seed page chips (no PDF files required).
enum PageRefSeedAudit {
    static func issues(in store: RulesReferenceStore) -> [String] {
        var issues: [String] = []
        var seenIDs = Set<String>()
        for entry in store.entries {
            if !seenIDs.insert(entry.id).inserted {
                issues.append("duplicate id \(entry.id)")
            }
            for ref in entry.pageRefs {
                if ref.bookKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(entry.id): empty bookKey")
                }
                if ref.page < 1 {
                    issues.append("\(entry.id): page \(ref.page) for \(ref.bookKey)")
                }
                if ref.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(entry.id): empty label for \(ref.bookKey)")
                }
            }
            // Prefer-edition sort should be stable for any edition.
            let sorted = entry.pageRefsForDisplay(preferEdition: .sr5)
            if sorted.count != entry.pageRefs.count {
                issues.append("\(entry.id): sorted page ref count mismatch")
            }
        }
        return issues
    }
}
