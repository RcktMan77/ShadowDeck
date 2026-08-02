//
//  RunModelTests.swift
//  ShadowDeckTests
//
//  Domain tests for Run / Mission tracker (v1).
//

import XCTest
@testable import ShadowDeck

final class RunModelTests: XCTestCase {
    // MARK: - Codable

    func testRunCodableRoundTrip() throws {
        var run = Run.makeDraft(title: "Datasteal on Renraku Arcology")
        run.tags = ["Datasteal", "Corp"]
        run.client = "Mr. Johnson (Ares cut-out)"
        run.location = "Seattle, Downtown"
        run.objectives = [
            RunObjective(text: "Extract paydata", isPrimary: true, status: .pending),
            RunObjective(text: "No civilian casualties", isPrimary: false, status: .pending)
        ]
        run.opposition = "High-threat Matrix IC, two security mage teams"
        run.complicationsNotes = "Johnson may double-cross"
        run.expectedPayout = RunPayout(nuyen: 12_000, karma: 6)
        run.heatDelta = 2
        let a = UUID()
        let b = UUID()
        run.participantCharacterIDs = [a, b]
        run.sessionLog = [
            RunLogEntry(kind: .session, text: "Session 1 — matrix recon"),
            RunLogEntry(kind: .complication, text: "Spider noticed the probe")
        ]
        run.gmNotes = "Keep decker spotlight."
        run.outcomeSummary = ""
        run.applyStatus(.active)

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(Run.self, from: data)

        XCTAssertEqual(decoded.id, run.id)
        XCTAssertEqual(decoded.title, run.title)
        XCTAssertEqual(decoded.tags, ["Datasteal", "Corp"])
        XCTAssertEqual(decoded.status, .active)
        XCTAssertNotNil(decoded.startedAt)
        XCTAssertEqual(decoded.client, run.client)
        XCTAssertEqual(decoded.objectives.count, 2)
        XCTAssertEqual(decoded.expectedPayout.nuyen, 12_000)
        XCTAssertEqual(decoded.participantCharacterIDs, [a, b])
        XCTAssertEqual(decoded.sessionLog.count, 2)
        XCTAssertEqual(decoded.schemaVersion, Run.currentSchemaVersion)
        XCTAssertEqual(decoded.edition, .sr5)
    }

    func testLegacyRunJSONWithoutEditionDefaultsToSR5() throws {
        // Minimal payload shaped like pre-edition runs.
        let json = Data("""
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "schemaVersion": 1,
          "title": "Legacy Job",
          "tags": [],
          "status": "planning",
          "client": "",
          "location": "",
          "objectives": [],
          "opposition": "",
          "complicationsNotes": "",
          "expectedPayout": { "nuyen": 0, "karma": 0 },
          "heatDelta": 0,
          "participantCharacterIDs": [],
          "sessionLog": [],
          "outcomeSummary": "",
          "gmNotes": "",
          "createdAt": "2020-01-01T00:00:00Z",
          "modifiedAt": "2020-01-01T00:00:00Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(Run.self, from: json)
        XCTAssertEqual(run.edition, .sr5)
        XCTAssertEqual(run.title, "Legacy Job")
    }

    func testPruneIneligibleParticipantsOnEditionChange() {
        let sr4 = UUID()
        let sr5 = UUID()
        var run = Run.makeDraft(title: "Mixed", edition: .sr5)
        run.participantCharacterIDs = [sr4, sr5]
        run.pruneIneligibleParticipants(characterEditions: [sr4: .sr4, sr5: .sr5])
        XCTAssertEqual(run.participantCharacterIDs, [sr5])
        run.edition = .sr4
        run.pruneIneligibleParticipants(characterEditions: [sr4: .sr4, sr5: .sr5])
        XCTAssertEqual(run.participantCharacterIDs, [])
        // After re-add only SR4
        run.participantCharacterIDs = [sr4]
        run.pruneIneligibleParticipants(characterEditions: [sr4: .sr4, sr5: .sr5])
        XCTAssertEqual(run.participantCharacterIDs, [sr4])
    }

    func testAcceptsParticipantByEdition() {
        let run = Run.makeDraft(title: "SR6 job", edition: .sr6)
        XCTAssertTrue(run.acceptsParticipant(edition: .sr6))
        XCTAssertFalse(run.acceptsParticipant(edition: .sr5))
        XCTAssertFalse(run.acceptsParticipant(edition: nil))
    }

    func testNestedTypesRoundTrip() throws {
        let objective = RunObjective(text: "Breach", isPrimary: true, status: .complete)
        let entry = RunLogEntry(kind: .heat, text: "+1 heat from messy exit")
        let payout = RunPayout(nuyen: 500, karma: 1)

        let oData = try JSONEncoder().encode(objective)
        let eData = try JSONEncoder().encode(entry)
        let pData = try JSONEncoder().encode(payout)

        XCTAssertEqual(try JSONDecoder().decode(RunObjective.self, from: oData), objective)
        XCTAssertEqual(try JSONDecoder().decode(RunLogEntry.self, from: eData).kind, .heat)
        XCTAssertEqual(try JSONDecoder().decode(RunPayout.self, from: pData).nuyen, 500)
    }

    // MARK: - Title validation

    func testHasValidTitleRequiresNonEmptyTrimmed() {
        var run = Run(title: "")
        XCTAssertFalse(run.hasValidTitle)
        run.title = "   "
        XCTAssertFalse(run.hasValidTitle)
        run.title = " Night on the town "
        XCTAssertTrue(run.hasValidTitle)
    }

    // MARK: - Status dates

    func testApplyStatusActiveSetsStartedAtOnce() {
        var run = Run.makeDraft(title: "Test")
        XCTAssertNil(run.startedAt)
        let t1 = Date(timeIntervalSince1970: 1_000)
        run.applyStatus(.active, at: t1)
        XCTAssertEqual(run.startedAt, t1)

        let t2 = Date(timeIntervalSince1970: 2_000)
        run.applyStatus(.planning, at: t2)
        run.applyStatus(.active, at: t2)
        // Do not overwrite existing startedAt
        XCTAssertEqual(run.startedAt, t1)
    }

    func testApplyStatusTerminalSetsCompletedAt() {
        var run = Run.makeDraft(title: "Test")
        run.applyStatus(.active)
        let done = Date(timeIntervalSince1970: 5_000)
        run.applyStatus(.completed, at: done)
        XCTAssertEqual(run.completedAt, done)
        XCTAssertTrue(run.shouldRemindEmptyOutcome)

        run.outcomeSummary = "Got the paydata, burned the safehouse."
        XCTAssertFalse(run.shouldRemindEmptyOutcome)
    }

    func testBlankNoteTreatsEmptyRTFAsEmpty() {
        XCTAssertTrue(Run.isBlankNote(""))
        XCTAssertTrue(Run.isBlankNote("   "))
        // Minimal empty RTF document (no real text content).
        XCTAssertTrue(Run.isBlankNote(#"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24}"#))
        XCTAssertFalse(Run.isBlankNote("Got away clean."))
    }

    func testLeavingTerminalClearsCompletedAt() {
        var run = Run.makeDraft(title: "Test")
        run.applyStatus(.failed, at: Date(timeIntervalSince1970: 9_000))
        XCTAssertNotNil(run.completedAt)
        run.applyStatus(.planning)
        XCTAssertNil(run.completedAt)
        XCTAssertEqual(run.status, .planning)
    }

    // MARK: - Suggested awards

    func testSuggestedAwardsEmptyWithoutParticipants() {
        var run = Run.makeDraft(title: "Solo job that isn't")
        run.expectedPayout = RunPayout(nuyen: 10_000, karma: 4)
        XCTAssertTrue(run.suggestedAwards().isEmpty)
    }

    func testSuggestedAwardsEqualSplitWithRemainderToFirst() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        var run = Run.makeDraft(title: "Three runners")
        run.participantCharacterIDs = [a, b, c]
        run.expectedPayout = RunPayout(nuyen: 10_000, karma: 5)
        // 10000/3 = 3333 rem 1; 5/3 = 1 rem 2

        let awards = run.suggestedAwards()
        XCTAssertEqual(awards.count, 3)
        XCTAssertEqual(awards[0].characterID, a)
        XCTAssertEqual(awards[0].nuyen, 3334) // 3333 + 1
        XCTAssertEqual(awards[0].karma, 3)    // 1 + 2
        XCTAssertEqual(awards[1].nuyen, 3333)
        XCTAssertEqual(awards[1].karma, 1)
        XCTAssertEqual(awards[2].nuyen, 3333)
        XCTAssertEqual(awards[2].karma, 1)
        XCTAssertEqual(awards.map(\.nuyen).reduce(0, +), 10_000)
        XCTAssertEqual(awards.map(\.karma).reduce(0, +), 5)
        XCTAssertTrue(awards[0].note.contains("suggestions only"))
    }

    func testSuggestedAwardsPrefersActualPayout() {
        let id = UUID()
        var run = Run.makeDraft(title: "Paid")
        run.participantCharacterIDs = [id]
        run.expectedPayout = RunPayout(nuyen: 5_000, karma: 2)
        run.actualPayout = RunPayout(nuyen: 8_000, karma: 4)

        let awards = run.suggestedAwards()
        XCTAssertEqual(awards.count, 1)
        XCTAssertEqual(awards[0].nuyen, 8_000)
        XCTAssertEqual(awards[0].karma, 4)
        XCTAssertTrue(awards[0].note.contains("actual"))
    }

    func testPrimarySecondaryObjectiveFilters() {
        var run = Run.makeDraft(title: "Obj")
        run.objectives = [
            RunObjective(text: "A", isPrimary: true),
            RunObjective(text: "B", isPrimary: false),
            RunObjective(text: "C", isPrimary: true)
        ]
        XCTAssertEqual(run.primaryObjectives.map(\.text), ["A", "C"])
        XCTAssertEqual(run.secondaryObjectives.map(\.text), ["B"])
    }

    func testSessionLogNewestFirst() {
        var run = Run.makeDraft(title: "Log")
        let older = RunLogEntry(
            createdAt: Date(timeIntervalSince1970: 100),
            kind: .note,
            text: "first"
        )
        let newer = RunLogEntry(
            createdAt: Date(timeIntervalSince1970: 200),
            kind: .note,
            text: "second"
        )
        run.sessionLog = [older, newer]
        XCTAssertEqual(run.sessionLogNewestFirst.map(\.text), ["second", "first"])
    }
}
