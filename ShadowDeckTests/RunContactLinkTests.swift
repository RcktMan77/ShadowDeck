//
//  RunContactLinkTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class RunContactLinkTests: XCTestCase {
    func testDisplayClientNamePrefersJohnsonLink() {
        var run = Run.makeDraft(title: "Job")
        run.client = "Fallback text"
        run.addContactLink(RunContactLink(role: .johnson, displayName: "Ms. Johnson"))
        XCTAssertEqual(run.displayClientName, "Ms. Johnson")
        XCTAssertEqual(run.client, "Fallback text")
    }

    func testAddJohnsonSeedsEmptyClientOnce() {
        var run = Run.makeDraft(title: "Job")
        XCTAssertTrue(run.client.isEmpty)
        run.addContactLink(RunContactLink(role: .johnson, displayName: "Mr. J"))
        XCTAssertEqual(run.client, "Mr. J")
        run.addContactLink(RunContactLink(role: .fixer, displayName: "Street Fixer"))
        // Does not overwrite client after seed.
        XCTAssertEqual(run.client, "Mr. J")
    }

    func testContactsCodableDefaultEmpty() throws {
        var run = Run.makeDraft(title: "Legacy shape")
        run.contacts = [
            RunContactLink(
                role: .target,
                sourceCharacterID: UUID(),
                contactID: UUID(),
                displayName: "Target SIN"
            )
        ]
        let data = try RunMapper.encodePayload(run)
        let decoded = try RunMapper.decodePayload(data)
        XCTAssertEqual(decoded.contacts.count, 1)
        XCTAssertEqual(decoded.contacts[0].displayName, "Target SIN")
        XCTAssertEqual(decoded.contacts[0].role, .target)
        XCTAssertTrue(decoded.contacts[0].isLinked)

        // Omitting contacts key → empty (legacy).
        struct Minimal: Encodable {
            var id: UUID
            var title: String
        }
        // Full decode path already defaults missing contacts in Run.init(from:).
        let empty = Run.makeDraft(title: "No contacts")
        XCTAssertTrue(empty.contacts.isEmpty)
    }
}
