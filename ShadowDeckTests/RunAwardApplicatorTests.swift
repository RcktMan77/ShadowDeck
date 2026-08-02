//
//  RunAwardApplicatorTests.swift
//  ShadowDeckTests
//
//  Pure engine tests for applying run nuyen/karma awards.
//

import XCTest
@testable import ShadowDeck

final class RunAwardApplicatorTests: XCTestCase {
    // MARK: - Fixtures

    private func makeCharacter(
        id: UUID = UUID(),
        name: String = "Runner",
        nuyen: Int = 1_000,
        karmaAvailable: Int = 10,
        karmaTotal: Int = 10
    ) -> Character {
        Character(
            id: id,
            name: name,
            edition: .sr5,
            metatype: .human,
            awakened: .mundane,
            generation: GenerationProfile(system: .priority),
            houseRules: .coreBook,
            attributes: AttributeRatings(
                body: 3,
                agility: 3,
                reaction: 3,
                strength: 3,
                willpower: 3,
                logic: 3,
                intuition: 3,
                charisma: 3,
                edge: 2,
                magic: 0,
                resonance: 0
            ),
            karmaTotal: karmaTotal,
            karmaAvailable: karmaAvailable,
            nuyen: nuyen
        )
    }

    private func finishedRun(
        title: String = "SRM Test Job",
        status: RunStatus = .completed,
        participantIDs: [UUID],
        expected: RunPayout = .zero,
        actual: RunPayout? = nil
    ) -> Run {
        var run = Run.makeDraft(title: title)
        run.status = status
        if status.isTerminal {
            run.completedAt = Date()
        }
        run.participantCharacterIDs = participantIDs
        run.expectedPayout = expected
        run.actualPayout = actual
        return run
    }

    // MARK: - Preview split

    func testPreviewEqualSplitRemainderToFirstAvailable() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let chars: [UUID: Character] = [
            a: makeCharacter(id: a, name: "Alpha"),
            b: makeCharacter(id: b, name: "Bravo"),
            c: makeCharacter(id: c, name: "Charlie")
        ]
        let run = finishedRun(
            participantIDs: [a, b, c],
            expected: RunPayout(nuyen: 10_000, karma: 5)
        )

        let preview = RunAwardApplicator.preview(run: run, charactersByID: chars)

        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.sourceLabel, "expected")
        XCTAssertEqual(preview.totalNuyen, 10_000)
        XCTAssertEqual(preview.totalKarma, 5)
        XCTAssertEqual(preview.perCharacter.count, 3)
        XCTAssertEqual(preview.perCharacter[0].characterID, a)
        XCTAssertEqual(preview.perCharacter[0].nuyen, 3334)
        XCTAssertEqual(preview.perCharacter[0].karma, 3)
        XCTAssertEqual(preview.perCharacter[1].nuyen, 3333)
        XCTAssertEqual(preview.perCharacter[1].karma, 1)
        XCTAssertEqual(preview.perCharacter[2].nuyen, 3333)
        XCTAssertEqual(preview.perCharacter[2].karma, 1)
        XCTAssertEqual(preview.perCharacter.map(\.nuyen).reduce(0, +), 10_000)
        XCTAssertEqual(preview.perCharacter.map(\.karma).reduce(0, +), 5)
        XCTAssertTrue(preview.skipped.isEmpty)
    }

    func testPreviewPrefersActualPayout() {
        let id = UUID()
        let chars = [id: makeCharacter(id: id)]
        let run = finishedRun(
            participantIDs: [id],
            expected: RunPayout(nuyen: 5_000, karma: 2),
            actual: RunPayout(nuyen: 8_000, karma: 4)
        )

        let preview = RunAwardApplicator.preview(run: run, charactersByID: chars)

        XCTAssertEqual(preview.sourceLabel, "actual")
        XCTAssertEqual(preview.totalNuyen, 8_000)
        XCTAssertEqual(preview.totalKarma, 4)
        XCTAssertEqual(preview.perCharacter.first?.nuyen, 8_000)
        XCTAssertEqual(preview.perCharacter.first?.karma, 4)
    }

    func testPreviewSkipsMissingAndResplitsAmongAvailable() {
        let a = UUID()
        let missing = UUID()
        let c = UUID()
        let chars: [UUID: Character] = [
            a: makeCharacter(id: a, name: "Alpha"),
            c: makeCharacter(id: c, name: "Charlie")
        ]
        // 10_000 / 2 = 5000; 5 / 2 = 2 rem 1 → first gets 3 karma
        let run = finishedRun(
            participantIDs: [a, missing, c],
            expected: RunPayout(nuyen: 10_000, karma: 5)
        )

        let preview = RunAwardApplicator.preview(run: run, charactersByID: chars)

        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.perCharacter.count, 2)
        XCTAssertEqual(preview.perCharacter[0].characterID, a)
        XCTAssertEqual(preview.perCharacter[0].nuyen, 5_000)
        XCTAssertEqual(preview.perCharacter[0].karma, 3)
        XCTAssertEqual(preview.perCharacter[1].characterID, c)
        XCTAssertEqual(preview.perCharacter[1].nuyen, 5_000)
        XCTAssertEqual(preview.perCharacter[1].karma, 2)
        XCTAssertEqual(preview.skipped.count, 1)
        XCTAssertEqual(preview.skipped[0].characterID, missing)
        XCTAssertTrue(preview.skipped[0].reason.contains("Missing"))
    }

    func testPreviewAllMissingBlocksApply() {
        let a = UUID()
        let b = UUID()
        let run = finishedRun(
            participantIDs: [a, b],
            expected: RunPayout(nuyen: 1_000, karma: 1)
        )

        let preview = RunAwardApplicator.preview(run: run, charactersByID: [:])

        XCTAssertFalse(preview.canApply)
        XCTAssertTrue(preview.perCharacter.isEmpty)
        XCTAssertEqual(preview.skipped.count, 2)
        XCTAssertTrue(preview.blockReason.contains("library") || preview.blockReason.contains("None"))
    }

    func testPreviewAlreadyAppliedBlocks() {
        let id = UUID()
        var run = finishedRun(
            participantIDs: [id],
            expected: RunPayout(nuyen: 1_000, karma: 1)
        )
        run.awardsAppliedAt = Date()

        let preview = RunAwardApplicator.preview(
            run: run,
            charactersByID: [id: makeCharacter(id: id)]
        )

        XCTAssertFalse(preview.canApply)
        XCTAssertTrue(preview.blockReason.lowercased().contains("already"))
    }

    func testPreviewNonTerminalBlocks() {
        let id = UUID()
        let run = finishedRun(
            status: .active,
            participantIDs: [id],
            expected: RunPayout(nuyen: 1_000, karma: 1)
        )

        let preview = RunAwardApplicator.preview(
            run: run,
            charactersByID: [id: makeCharacter(id: id)]
        )

        XCTAssertFalse(preview.canApply)
        XCTAssertFalse(preview.blockReason.isEmpty)
    }

    func testPreviewZeroPayoutBlocks() {
        let id = UUID()
        let run = finishedRun(
            participantIDs: [id],
            expected: .zero
        )

        let preview = RunAwardApplicator.preview(
            run: run,
            charactersByID: [id: makeCharacter(id: id)]
        )

        XCTAssertFalse(preview.canApply)
        let reason = preview.blockReason.lowercased()
        XCTAssertTrue(
            reason.contains("payout")
                || reason.contains("zero")
                || reason.contains("non-zero")
        )
    }

    func testPreviewFailedStatusEligible() {
        let id = UUID()
        let run = finishedRun(
            status: .failed,
            participantIDs: [id],
            expected: RunPayout(nuyen: 500, karma: 1)
        )

        let preview = RunAwardApplicator.preview(
            run: run,
            charactersByID: [id: makeCharacter(id: id)]
        )

        XCTAssertTrue(preview.canApply)
    }

    // MARK: - Apply

    func testApplyCreditsNuyenAndKarmaAndLedger() throws {
        let a = UUID()
        let b = UUID()
        var chars = [
            makeCharacter(id: a, name: "Alpha", nuyen: 100, karmaAvailable: 5, karmaTotal: 20),
            makeCharacter(id: b, name: "Bravo", nuyen: 200, karmaAvailable: 3, karmaTotal: 10)
        ]
        var run = finishedRun(
            title: "Critic's Choice",
            participantIDs: [a, b],
            expected: RunPayout(nuyen: 1_000, karma: 3)
        )
        // 1000/2 = 500; 3/2 = 1 rem 1 → first gets 2 karma

        let appliedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let result = try RunAwardApplicator.apply(
            run: &run,
            characters: &chars,
            note: "Good run",
            at: appliedAt
        )

        XCTAssertEqual(result.applied.count, 2)
        XCTAssertEqual(result.appliedAt, appliedAt)
        XCTAssertEqual(run.awardsAppliedAt, appliedAt)
        XCTAssertEqual(run.awardsAppliedNote, "Good run")

        let alpha = chars.first { $0.id == a }!
        let bravo = chars.first { $0.id == b }!

        XCTAssertEqual(alpha.nuyen, 100 + 500)
        XCTAssertEqual(alpha.karmaAvailable, 5 + 2)
        XCTAssertEqual(alpha.karmaTotal, 20 + 2)
        XCTAssertEqual(bravo.nuyen, 200 + 500)
        XCTAssertEqual(bravo.karmaAvailable, 3 + 1)
        XCTAssertEqual(bravo.karmaTotal, 10 + 1)

        let ledger = alpha.advancementLedgerEntries.first
        XCTAssertEqual(ledger?.kind, .runAward)
        XCTAssertEqual(ledger?.karmaSpent, -2) // gain
        XCTAssertEqual(ledger?.nuyenDelta, 500)
        XCTAssertEqual(ledger?.relatedRunID, run.id)
        XCTAssertTrue(ledger?.summary.contains("Critic") == true)
        XCTAssertTrue(ledger?.summary.contains("500") == true || ledger?.summary.contains("¥500") == true)

        // Session log note
        XCTAssertTrue(run.sessionLog.contains { $0.text.contains("Awards applied") })
    }

    func testApplyDoubleApplyThrows() throws {
        let id = UUID()
        var chars = [makeCharacter(id: id)]
        var run = finishedRun(
            participantIDs: [id],
            expected: RunPayout(nuyen: 100, karma: 1)
        )

        _ = try RunAwardApplicator.apply(run: &run, characters: &chars)
        XCTAssertThrowsError(try RunAwardApplicator.apply(run: &run, characters: &chars)) { error in
            XCTAssertEqual(error as? RunAwardApplicatorError, .alreadyApplied)
        }
    }

    func testApplyNonTerminalThrows() {
        let id = UUID()
        var chars = [makeCharacter(id: id)]
        var run = finishedRun(
            status: .planning,
            participantIDs: [id],
            expected: RunPayout(nuyen: 100, karma: 1)
        )

        XCTAssertThrowsError(try RunAwardApplicator.apply(run: &run, characters: &chars)) { error in
            XCTAssertEqual(error as? RunAwardApplicatorError, .runNotTerminal)
        }
    }

    func testApplyNoParticipantsThrows() {
        var chars: [Character] = []
        var run = finishedRun(
            participantIDs: [],
            expected: RunPayout(nuyen: 100, karma: 1)
        )

        XCTAssertThrowsError(try RunAwardApplicator.apply(run: &run, characters: &chars)) { error in
            XCTAssertEqual(error as? RunAwardApplicatorError, .noParticipants)
        }
    }

    func testApplyNoAwardsThrows() {
        let id = UUID()
        var chars = [makeCharacter(id: id)]
        var run = finishedRun(participantIDs: [id], expected: .zero)

        XCTAssertThrowsError(try RunAwardApplicator.apply(run: &run, characters: &chars)) { error in
            XCTAssertEqual(error as? RunAwardApplicatorError, .noAwards)
        }
    }

    func testApplyAllMissingThrows() {
        let a = UUID()
        var chars: [Character] = [] // none of the linked IDs
        var run = finishedRun(
            participantIDs: [a],
            expected: RunPayout(nuyen: 100, karma: 1)
        )

        XCTAssertThrowsError(try RunAwardApplicator.apply(run: &run, characters: &chars)) { error in
            XCTAssertEqual(error as? RunAwardApplicatorError, .noAvailableParticipants)
        }
    }

    func testApplySkipsMissingParticipants() throws {
        let a = UUID()
        let missing = UUID()
        var chars = [makeCharacter(id: a, name: "Solo", nuyen: 0, karmaAvailable: 0, karmaTotal: 0)]
        var run = finishedRun(
            participantIDs: [a, missing],
            expected: RunPayout(nuyen: 900, karma: 2)
        )

        let result = try RunAwardApplicator.apply(run: &run, characters: &chars)

        XCTAssertEqual(result.applied.count, 1)
        XCTAssertEqual(result.applied[0].nuyen, 900)
        XCTAssertEqual(result.applied[0].karma, 2)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped[0].characterID, missing)
        XCTAssertEqual(chars[0].nuyen, 900)
        XCTAssertEqual(chars[0].karmaAvailable, 2)
        XCTAssertEqual(chars[0].karmaTotal, 2)
    }

    func testApplyBlankNoteBecomesNil() throws {
        let id = UUID()
        var chars = [makeCharacter(id: id)]
        var run = finishedRun(
            participantIDs: [id],
            expected: RunPayout(nuyen: 10, karma: 0)
        )

        _ = try RunAwardApplicator.apply(run: &run, characters: &chars, note: "   ")
        XCTAssertNil(run.awardsAppliedNote)
    }

    // MARK: - Codable fields

    func testRunAwardsFieldsCodableRoundTrip() throws {
        var run = finishedRun(
            participantIDs: [UUID()],
            expected: RunPayout(nuyen: 1, karma: 1)
        )
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        run.awardsAppliedAt = date
        run.awardsAppliedNote = "Paid out"

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(Run.self, from: data)

        XCTAssertEqual(decoded.awardsAppliedAt, date)
        XCTAssertEqual(decoded.awardsAppliedNote, "Paid out")
    }

    func testLegacyRunJSONWithoutAwardsFieldsDecodes() throws {
        let json = Data("""
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "schemaVersion": 1,
          "title": "Legacy Job",
          "tags": [],
          "status": "completed",
          "client": "",
          "location": "",
          "objectives": [],
          "opposition": "",
          "complicationsNotes": "",
          "expectedPayout": { "nuyen": 100, "karma": 1 },
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
        XCTAssertNil(run.awardsAppliedAt)
        XCTAssertNil(run.awardsAppliedNote)
    }

    func testAdvancementLedgerEntryRunAwardCodable() throws {
        let runID = UUID()
        let entry = AdvancementLedgerEntry(
            kind: .runAward,
            summary: "Job — ¥500 + 2 karma",
            karmaSpent: -2,
            nuyenDelta: 500,
            relatedRunID: runID
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AdvancementLedgerEntry.self, from: data)
        XCTAssertEqual(decoded.kind, .runAward)
        XCTAssertEqual(decoded.karmaSpent, -2)
        XCTAssertEqual(decoded.nuyenDelta, 500)
        XCTAssertEqual(decoded.relatedRunID, runID)
    }

    func testLegacyLedgerEntryWithoutNuyenDeltaDecodes() throws {
        let id = UUID()
        let json = Data("""
        {
          "id": "\(id.uuidString)",
          "date": "2020-01-01T00:00:00Z",
          "kind": "skillRaise",
          "summary": "Pistols 4 → 5 (8 karma)",
          "karmaSpent": 8,
          "targetKey": "pistols"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(AdvancementLedgerEntry.self, from: json)
        XCTAssertEqual(entry.nuyenDelta, 0)
        XCTAssertNil(entry.relatedRunID)
        XCTAssertEqual(entry.karmaSpent, 8)
    }
}
