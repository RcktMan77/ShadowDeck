//
//  CatalogEditionTests.swift
//  ShadowDeckTests
//
//  Edition-scoped bundled catalogs (SR4A / SR5 / SR6).
//

import XCTest
@testable import ShadowDeck

final class CatalogEditionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CatalogLookup.resetCache()
    }

    func testBundledResourceNames() {
        XCTAssertEqual(ChummerCatalogLoader.bundledResourceName(for: .sr4), "sr4_catalog")
        XCTAssertEqual(ChummerCatalogLoader.bundledResourceName(for: .sr5), "sr5_catalog")
        XCTAssertEqual(ChummerCatalogLoader.bundledResourceName(for: .sr6), "sr6_catalog")
    }

    func testSR6CatalogLoadsExactBookSpotChecks() {
        let result = ChummerCatalogLoader.load(edition: .sr6)
        XCTAssertTrue(result.errors.isEmpty, result.errors.joined(separator: "; "))
        XCTAssertFalse(result.entries.isEmpty)
        XCTAssertTrue(result.loadedFiles.contains { $0.contains("sr6_catalog") })

        func entry(_ name: String) -> CatalogEntry? {
            result.entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        // Spot-checks aligned with Scripts/build_sr6_catalog_from_pdf.py EXACT_CHECKS.
        XCTAssertEqual(entry("Combat Axe")?.costNuyen, 500)
        XCTAssertEqual(entry("Combat Axe")?.kind, .weapon)
        XCTAssertEqual(entry("Katana")?.costNuyen, 350)
        XCTAssertEqual(entry("Ares Predator VI")?.costNuyen, 750)
        XCTAssertEqual(entry("Colt America L36")?.costNuyen, 230)
        XCTAssertEqual(entry("Armor Jacket")?.costNuyen, 1000)
        XCTAssertEqual(entry("Armor Vest")?.costNuyen, 750)
        XCTAssertEqual(entry("Datajack")?.costNuyen, 1000)
        XCTAssertEqual(entry("Datajack")?.essenceText, "0.1")
        XCTAssertEqual(entry("Smartlink")?.costNuyen, 4000)
        XCTAssertEqual(entry("Smartlink")?.essenceText, "0.2")
    }

    func testSR4CatalogLoadsWhenPresent() {
        let result = ChummerCatalogLoader.load(edition: .sr4)
        XCTAssertFalse(result.entries.isEmpty)
        XCTAssertTrue(result.loadedFiles.contains { $0.contains("sr4_catalog") })
    }

    func testSR5CatalogStillLoads() {
        let result = ChummerCatalogLoader.load(edition: .sr5)
        XCTAssertFalse(result.entries.isEmpty)
        XCTAssertTrue(result.loadedFiles.contains { $0.contains("sr5_catalog") })
    }

    func testCatalogLookupEditionScoped() {
        let sr6 = CatalogLookup.entry(named: "Ares Predator VI", edition: .sr6)
        XCTAssertNotNil(sr6)
        XCTAssertEqual(sr6?.costNuyen, 750)

        // SR5 catalog should not be required to contain SR6-only names.
        let sr5PredatorVI = CatalogLookup.entry(named: "Ares Predator VI", edition: .sr5)
        // May or may not exist in Chummer SR5 data; must not crash.
        _ = sr5PredatorVI
    }
}
