//
//  ShadowDeckTests.swift
//  ShadowDeckTests
//
//  Module smoke tests — keeps the test target linked to the app host.
//

import XCTest
@testable import ShadowDeck

final class ShadowDeckTests: XCTestCase {
    func testAppModuleLoadsRulesSeed() {
        let store = RulesReferenceStore.loadBundled()
        XCTAssertTrue(store.loadErrors.isEmpty, "Seed load errors: \(store.loadErrors)")
        XCTAssertGreaterThanOrEqual(store.entries.count, 80, "Expected ~80–120 seed cards")
        XCTAssertLessThanOrEqual(store.entries.count, 200)
    }

    func testCatalogLookupSmoke() {
        // Import / effects path uses CatalogLookup (not CatalogStore UI singleton).
        let entry = CatalogLookup.entry(named: "Muscle Replacement")
        XCTAssertNotNil(entry, "Bundled catalog should resolve a well-known cyberware name")
    }
}
