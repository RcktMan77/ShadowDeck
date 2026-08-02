//
//  RulesReferenceTests.swift
//  ShadowDeckTests
//
//  Seed load + search / edition filtering for Rules Reference Increment 1.
//

import XCTest
@testable import ShadowDeck

final class RulesReferenceTests: XCTestCase {

    private var store: RulesReferenceStore!

    override func setUp() {
        super.setUp()
        store = RulesReferenceStore.loadBundled()
    }

    func testBundledSeedLoads() {
        XCTAssertTrue(store.loadErrors.isEmpty, "Load errors: \(store.loadErrors)")
        XCTAssertGreaterThanOrEqual(store.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(
            store.entries.count,
            80,
            "Seed should cover ~80–120 high-frequency mechanical cards (got \(store.entries.count))"
        )
        XCTAssertLessThanOrEqual(store.entries.count, 150, "Keep seed maintainable")
    }

    func testPageRefsSortedByEdition() {
        let refs = [
            PageRef(bookKey: PageRef.BookKey.sr6Core, page: 36, label: "SR6"),
            PageRef(bookKey: PageRef.BookKey.sr5CRB, page: 44, label: "SR5"),
            PageRef(bookKey: PageRef.BookKey.sr4a, page: 60, label: "SR4"),
        ]
        let sorted = PageRef.sortedForDisplay(refs)
        XCTAssertEqual(sorted.map(\.bookKey), [
            PageRef.BookKey.sr4a,
            PageRef.BookKey.sr5CRB,
            PageRef.BookKey.sr6Core,
        ])

        // Character edition first (SR5), then remaining cores in era order.
        let preferred = PageRef.sortedForDisplay(refs, preferEdition: .sr5)
        XCTAssertEqual(preferred.map(\.bookKey), [
            PageRef.BookKey.sr5CRB,
            PageRef.BookKey.sr4a,
            PageRef.BookKey.sr6Core,
        ])

        if let hits = store.entry(id: "dice-hits") {
            let keys = hits.pageRefs.map(\.bookKey)
            let coreKeys = keys.filter {
                $0 == PageRef.BookKey.sr4a
                    || $0 == PageRef.BookKey.sr5CRB
                    || $0 == PageRef.BookKey.sr6Core
            }
            XCTAssertEqual(coreKeys, coreKeys.sorted {
                PageRef(bookKey: $0, page: 1, label: "").editionSortIndex
                    < PageRef(bookKey: $1, page: 1, label: "").editionSortIndex
            })
        }
    }

    func testSeedEntriesHaveRequiredFields() {
        for entry in store.entries {
            XCTAssertFalse(entry.id.isEmpty, "Empty id")
            XCTAssertFalse(entry.title.isEmpty, entry.id)
            XCTAssertFalse(entry.summary.isEmpty, entry.id)
            XCTAssertFalse(entry.summary.count > 800, "Summary too long for \(entry.id) — keep paraphrases short")
        }
        let ids = store.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate rule ids in seed")
    }

    func testSearchFindsGlitch() {
        let results = store.search(query: "glitch")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.entry.id == "dice-glitch" })
        XCTAssertGreaterThan(results.first?.score ?? 0, 0)
    }

    func testSearchRequiresAllTokens() {
        let hits = store.search(query: "glitch xyzzy-not-a-token")
        XCTAssertTrue(hits.isEmpty)
    }

    func testSearchRanksTitleAboveSummary() {
        let results = store.search(query: "hits")
        XCTAssertFalse(results.isEmpty)
        // Title card should outrank a summary-only mention if both match.
        XCTAssertEqual(results.first?.entry.id, "dice-hits")
    }

    func testCategoryFilter() {
        let dice = store.entries(category: .dice)
        XCTAssertFalse(dice.isEmpty)
        XCTAssertTrue(dice.allSatisfy { $0.category == .dice })

        let life = store.entries(category: .lifestyle)
        XCTAssertFalse(life.isEmpty)
        XCTAssertTrue(life.allSatisfy { $0.category == .lifestyle })
    }

    func testEditionFilterSR5Limits() {
        let sr5 = store.entries(edition: .sr5)
        XCTAssertTrue(sr5.contains { $0.id == "combat-limits-sr5" })

        let sr4 = store.entries(edition: .sr4)
        XCTAssertFalse(sr4.contains { $0.id == "combat-limits-sr5" })
        // All-edition cards still appear for SR4
        XCTAssertTrue(sr4.contains { $0.id == "dice-hits" })
    }

    func testSearchWithEditionAndCategory() {
        let results = store.search(query: "limit", category: .combat, edition: .sr5)
        XCTAssertTrue(results.contains { $0.entry.id == "combat-limits-sr5" })

        let sr4 = store.search(query: "limit", category: .combat, edition: .sr4)
        XCTAssertFalse(sr4.contains { $0.entry.id == "combat-limits-sr5" })
    }

    func testEntryByID() {
        let entry = store.entry(id: "adv-skill-raise")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.calculator, .karmaRaise)
        XCTAssertFalse(entry?.pageRefs.isEmpty ?? true)
    }

    func testPageRefAndCalculatorCodableInSeed() throws {
        let file = try RulesReferenceStore.loadSeedFile()
        let glitch = file.entries.first { $0.id == "dice-glitch" }
        XCTAssertEqual(glitch?.calculator, .glitchThreshold)
        XCTAssertFalse(glitch?.pageRefs.isEmpty ?? true)
        // Seed file stores SR4 → SR5 → SR6 order for multi-edition chips.
        XCTAssertEqual(glitch?.pageRefs.first?.bookKey, PageRef.BookKey.sr4a)
        XCTAssertTrue(glitch?.pageRefs.contains { $0.bookKey == PageRef.BookKey.sr5CRB } ?? false)
    }

    func testInMemoryStoreSearch() {
        let custom = RulesReferenceStore(entries: [
            RuleEntry(
                id: "t1",
                title: "Overwatch Score",
                category: .matrix,
                tags: ["OS", "matrix"],
                summary: "Tracks heat on illegal Matrix actions."
            ),
            RuleEntry(
                id: "t2",
                title: "Drain",
                category: .magic,
                tags: ["drain", "spell"],
                summary: "Spellcasting backlash."
            ),
        ])
        let os = custom.search(query: "overwatch")
        XCTAssertEqual(os.map(\.entry.id), ["t1"])
        let matrixTag = custom.search(query: "OS")
        XCTAssertEqual(matrixTag.first?.entry.id, "t1")
    }
}

// MARK: - PDF zoom math

final class PDFZoomMathTests: XCTestCase {
    private let letter = CGSize(width: 612, height: 765)

    func testActualSizeIsOne() {
        let canvas = CGSize(width: 400, height: 600)
        XCTAssertEqual(PDFZoomPreset.scale(preset: .actualSize, canvas: canvas, pageSize: letter), 1.0, accuracy: 0.0001)
        XCTAssertEqual(PDFZoomPreset.scale(preset: .percent100, canvas: canvas, pageSize: letter), 1.0, accuracy: 0.0001)
        XCTAssertEqual(PDFZoomPreset.actualSize.fixedScale, 1.0)
        XCTAssertEqual(PDFZoomPreset.percent100.fixedScale, 1.0)
        XCTAssertNil(PDFZoomPreset.fitPage.fixedScale)
        XCTAssertNil(PDFZoomPreset.fitWidth.fixedScale)
    }

    func testPercentScales() {
        let canvas = CGSize(width: 100, height: 100)
        XCTAssertEqual(PDFZoomPreset.scale(preset: .percent75, canvas: canvas, pageSize: letter), 0.75, accuracy: 0.0001)
        XCTAssertEqual(PDFZoomPreset.scale(preset: .percent125, canvas: canvas, pageSize: letter), 1.25, accuracy: 0.0001)
        XCTAssertEqual(PDFZoomPreset.scale(preset: .percent200, canvas: canvas, pageSize: letter), 2.0, accuracy: 0.0001)
    }

    func testFitWidthUsesPadding() {
        let canvas = CGSize(width: 306 + 2 * PDFZoomPreset.fitPadding, height: 900)
        let s = PDFZoomPreset.scale(preset: .fitWidth, canvas: canvas, pageSize: letter)
        XCTAssertEqual(s, 0.5, accuracy: 0.0001)
        let target = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: .fitWidth)
        XCTAssertEqual(letter.width * s, target.width, accuracy: 0.001)
        XCTAssertLessThan(letter.width * s, canvas.width)
    }

    func testFitPageIsHeightLimitedWhenCanvasIsWide() {
        // Landscape canvas: height is the limiting dimension (after padding).
        let canvas = CGSize(width: 1200, height: 400)
        let s = PDFZoomPreset.scale(preset: .fitPage, canvas: canvas, pageSize: letter)
        let target = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: .fitPage)
        let expected = min(target.width / 612.0, target.height / 765.0)
        XCTAssertEqual(s, expected, accuracy: 0.0001)
        XCTAssertEqual(s, target.height / 765.0, accuracy: 0.0001, "Must be height-limited, not width")
        XCTAssertLessThanOrEqual(letter.width * s, target.width + 0.001)
        XCTAssertLessThanOrEqual(letter.height * s, target.height + 0.001)
    }

    func testFitPageIsWidthLimitedWhenCanvasIsTall() {
        let canvas = CGSize(width: 300, height: 2000)
        let s = PDFZoomPreset.scale(preset: .fitPage, canvas: canvas, pageSize: letter)
        let target = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: .fitPage)
        XCTAssertEqual(s, target.width / 612.0, accuracy: 0.0001, "Must be width-limited")
        XCTAssertLessThanOrEqual(letter.height * s, target.height + 0.001)
    }

    func testFitPageDiffersFromFitWidthWhenHeightConstrained() {
        let canvas = CGSize(width: 900, height: 500)
        let fitPage = PDFZoomPreset.scale(preset: .fitPage, canvas: canvas, pageSize: letter)
        let fitWidth = PDFZoomPreset.scale(preset: .fitWidth, canvas: canvas, pageSize: letter)
        let targetPage = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: .fitPage)
        let targetWidth = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: .fitWidth)
        XCTAssertLessThan(fitPage, fitWidth - 0.01, "Fit Page must shrink more than Fit Width when height constrains")
        XCTAssertEqual(fitWidth, targetWidth.width / 612.0, accuracy: 0.0001)
        XCTAssertEqual(fitPage, targetPage.height / 765.0, accuracy: 0.0001)
    }

    func testFitPaddingLeavesBreathingRoom() {
        let canvas = CGSize(width: 800, height: 600)
        let s = PDFZoomPreset.scale(preset: .fitPage, canvas: canvas, pageSize: letter)
        XCTAssertLessThan(letter.width * s + 1, canvas.width)
        // Fit Page uses a single vertical pad (continuous top-align).
        XCTAssertLessThanOrEqual(letter.height * s, canvas.height - PDFZoomPreset.fitPadding + 0.001)
        XCTAssertEqual(PDFZoomPreset.fitPadding, 8, accuracy: 0.001)
    }

    func testFitPageVerticalPadIsSingleEdge() {
        let canvas = CGSize(width: 2000, height: 800)
        let target = PDFZoomPreset.fitTargetSize(canvas: canvas, preset: .fitPage)
        // One pad on height, two on width.
        XCTAssertEqual(target.height, canvas.height - PDFZoomPreset.fitPadding, accuracy: 0.001)
        XCTAssertEqual(target.width, canvas.width - 2 * PDFZoomPreset.fitPadding, accuracy: 0.001)
    }

    func testActualSizeIgnoresCanvas() {
        let a = PDFZoomPreset.scale(preset: .actualSize, canvas: CGSize(width: 100, height: 100), pageSize: letter)
        let b = PDFZoomPreset.scale(preset: .actualSize, canvas: CGSize(width: 2000, height: 2000), pageSize: letter)
        XCTAssertEqual(a, b, accuracy: 0.0001)
        XCTAssertEqual(a, 1.0, accuracy: 0.0001)
    }
}
