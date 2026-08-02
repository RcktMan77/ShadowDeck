//
//  ContactModelTests.swift
//  ShadowDeckTests
//
//  Enriched contacts: Codable defaults, favor/log rules, relationship status.
//

import XCTest
@testable import ShadowDeck

final class ContactModelTests: XCTestCase {
    // MARK: - Codable

    func testLegacyContactJSONDecodesWithDefaults() throws {
        let json = """
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "name": "Fixer Fran",
          "role": "Fixer",
          "loyalty": 3,
          "connection": 5,
          "notes": ""
        }
        """.data(using: .utf8)!
        let contact = try JSONDecoder().decode(Contact.self, from: json)
        XCTAssertEqual(contact.name, "Fixer Fran")
        XCTAssertEqual(contact.loyalty, 3)
        XCTAssertEqual(contact.tags, [])
        XCTAssertEqual(contact.favorState, .none)
        XCTAssertFalse(contact.favorOneTime)
        XCTAssertNil(contact.lastContactAt)
        XCTAssertTrue(contact.interactionLog.isEmpty)
    }

    func testEnrichedContactRoundTrip() throws {
        var contact = Contact(name: "Doc", role: "Street Doc", loyalty: 4, connection: 4)
        contact.tags = ["Street Doc", "Gang"]
        contact.favorState = .owesMe
        contact.favorOneTime = true
        let entry = ContactInteraction(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            summary: "Patched up after Everett job",
            favorDirection: .owesMe,
            relatedRunID: UUID()
        )
        contact.addInteraction(entry)

        let data = try JSONEncoder().encode(contact)
        let decoded = try JSONDecoder().decode(Contact.self, from: data)
        XCTAssertEqual(decoded.tags, ["Street Doc", "Gang"])
        XCTAssertEqual(decoded.favorState, .owesMe)
        XCTAssertTrue(decoded.favorOneTime)
        XCTAssertEqual(decoded.interactionLog.count, 1)
        XCTAssertEqual(decoded.interactionLog.first?.summary, "Patched up after Everett job")
        XCTAssertNotNil(decoded.lastContactAt)
    }

    // MARK: - Interaction / favor

    func testAddInteractionUpdatesLastContactButNotFavorByDefault() {
        var contact = Contact(name: "A", loyalty: 2, favorState: .none)
        let entry = ContactInteraction(
            date: Date(timeIntervalSince1970: 1_600_000_000),
            summary: "Quick call",
            favorDirection: .owesMe
        )
        contact.addInteraction(entry, updateCurrentFavor: false)
        XCTAssertEqual(contact.favorState, .none, "Log snapshot must not overwrite current favor")
        XCTAssertEqual(contact.lastContactAt, entry.date)
        XCTAssertEqual(contact.interactionLog.count, 1)
    }

    func testAddInteractionOptionalFavorUpdate() {
        var contact = Contact(name: "A", favorState: .none)
        let entry = ContactInteraction(summary: "They covered heat", favorDirection: .owesMe)
        contact.addInteraction(entry, updateCurrentFavor: true)
        XCTAssertEqual(contact.favorState, .owesMe)
    }

    func testAddInteractionDoesNotClearFavorWhenDirectionNone() {
        var contact = Contact(name: "A", favorState: .iOweThem)
        let entry = ContactInteraction(summary: "Coffee", favorDirection: ContactFavorState.none)
        contact.addInteraction(entry, updateCurrentFavor: true)
        XCTAssertEqual(contact.favorState, .iOweThem)
    }

    func testLastContactTakesLaterDate() {
        var contact = Contact(name: "A")
        let early = ContactInteraction(date: Date(timeIntervalSince1970: 100), summary: "First")
        let late = ContactInteraction(date: Date(timeIntervalSince1970: 200), summary: "Second")
        contact.addInteraction(early)
        contact.addInteraction(late)
        XCTAssertEqual(contact.lastContactAt, late.date)
        // Adding older after newer should not go backward
        contact.addInteraction(early)
        XCTAssertEqual(contact.lastContactAt, late.date)
    }

    func testRemoveInteraction() {
        var contact = Contact(name: "A")
        let a = ContactInteraction(summary: "A")
        let b = ContactInteraction(summary: "B")
        contact.addInteraction(a)
        contact.addInteraction(b)
        contact.removeInteraction(id: a.id)
        XCTAssertEqual(contact.interactionLog.map(\.summary), ["B"])
    }

    // MARK: - Relationship status

    func testRelationshipUnknownWithoutLastContact() {
        let c = Contact(name: "X", loyalty: 6)
        XCTAssertEqual(ContactHelpers.relationshipStatus(for: c), .unknown)
    }

    func testRelationshipStrong() {
        let now = Date()
        let last = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        let c = Contact(name: "X", loyalty: 4, lastContactAt: last)
        XCTAssertEqual(ContactHelpers.relationshipStatus(for: c, now: now), .strong)
    }

    func testRelationshipWarmByLoyalty() {
        let now = Date()
        let last = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        let c = Contact(name: "X", loyalty: 3, lastContactAt: last)
        XCTAssertEqual(ContactHelpers.relationshipStatus(for: c, now: now), .warm)
    }

    func testRelationshipWarmByRecency() {
        let now = Date()
        let last = Calendar.current.date(byAdding: .day, value: -20, to: now)!
        let c = Contact(name: "X", loyalty: 1, lastContactAt: last)
        // L1 + within 90 days → Warm (recency branch before Cold)
        XCTAssertEqual(ContactHelpers.relationshipStatus(for: c, now: now), .warm)
    }

    func testRelationshipColdStaleAndLowLoyalty() {
        let now = Date()
        let last = Calendar.current.date(byAdding: .day, value: -120, to: now)!
        let c = Contact(name: "X", loyalty: 2, lastContactAt: last)
        XCTAssertEqual(ContactHelpers.relationshipStatus(for: c, now: now), .cold)
    }

    // MARK: - Filter / search

    func testSearchNameRoleTagsNotNotes() {
        var c = Contact(name: "Hex", role: "Deck jockey", notes: "secret keyword")
        c.tags = ["Corp"]
        XCTAssertTrue(ContactHelpers.matchesSearch(c, query: "hex"))
        XCTAssertTrue(ContactHelpers.matchesSearch(c, query: "deck"))
        XCTAssertTrue(ContactHelpers.matchesSearch(c, query: "corp"))
        XCTAssertFalse(ContactHelpers.matchesSearch(c, query: "secret"))
    }

    func testFilterPendingFavorAndTag() {
        let a = Contact(name: "A", tags: ["Fixer"], favorState: .owesMe)
        let b = Contact(name: "B", tags: ["Fixer"], favorState: .none)
        let c = Contact(name: "C", tags: ["Gang"], favorState: .iOweThem)
        let all = [a, b, c]
        let pending = ContactHelpers.filter(all, pendingFavorOnly: true)
        XCTAssertEqual(Set(pending.map(\Contact.name)), ["A", "C"])
        let fixers = ContactHelpers.filter(all, tag: "Fixer")
        XCTAssertEqual(Set(fixers.map(\Contact.name)), ["A", "B"])
    }
}
