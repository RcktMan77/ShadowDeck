//
//  RunPersistenceTests.swift
//  ShadowDeckTests
//

import XCTest
import SwiftData
@testable import ShadowDeck

@MainActor
final class RunPersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var runLibrary: RunLibrary!
    private var characterLibrary: CharacterLibrary!
    private var avatarRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-RunTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(inMemory: true)
        characterLibrary = try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)
        runLibrary = PersistenceController.makeRunLibrary(container: container)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: avatarRoot)
        runLibrary = nil
        characterLibrary = nil
        container = nil
        avatarRoot = nil
        try super.tearDownWithError()
    }

    func testCRUDRoundTrip() throws {
        var run = Run.makeDraft(title: "Extraction at Everett docks")
        run.tags = ["Extraction"]
        run.client = "Johnson"
        run.expectedPayout = RunPayout(nuyen: 9_000, karma: 4)
        try runLibrary.save(run)

        XCTAssertEqual(try runLibrary.count(), 1)
        let summaries = try runLibrary.listSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].title, "Extraction at Everett docks")
        XCTAssertEqual(summaries[0].status, .planning)

        var loaded = try runLibrary.require(run.id)
        loaded.applyStatus(.active)
        loaded.location = "Everett"
        try runLibrary.save(loaded)

        let again = try runLibrary.require(run.id)
        XCTAssertEqual(again.status, .active)
        XCTAssertNotNil(again.startedAt)
        XCTAssertEqual(again.location, "Everett")

        try runLibrary.delete(id: run.id)
        XCTAssertEqual(try runLibrary.count(), 0)
        XCTAssertNil(try runLibrary.fetch(id: run.id))
    }

    func testEmptyTitleRejected() throws {
        let run = Run(title: "   ")
        XCTAssertThrowsError(try runLibrary.save(run)) { error in
            XCTAssertEqual(error as? RunLibraryError, .emptyTitle)
        }
    }

    func testParticipantIDsSurviveRoundTrip() throws {
        let char = SampleCharacters.sr5CombatMage()
        try characterLibrary.save(char)

        var run = Run.makeDraft(title: "With team")
        run.participantCharacterIDs = [char.id]
        try runLibrary.save(run)

        let summary = try runLibrary.listSummaries().first
        XCTAssertEqual(summary?.participantCharacterIDs, [char.id])

        let loaded = try runLibrary.require(run.id)
        XCTAssertEqual(loaded.participantCharacterIDs, [char.id])
        XCTAssertEqual(loaded.suggestedAwards().first?.characterID, char.id)
    }

    func testCoexistsWithCharactersInSameContainer() throws {
        try characterLibrary.save(SampleCharacters.sr4StreetSamurai())
        try runLibrary.save(Run.makeDraft(title: "Job A"))
        try runLibrary.save(Run.makeDraft(title: "Job B"))
        XCTAssertEqual(try characterLibrary.count(), 1)
        XCTAssertEqual(try runLibrary.count(), 2)
    }

    func testDeleteBlocksDeferredResave() throws {
        var run = Run.makeDraft(title: "Doomed")
        try runLibrary.save(run)
        XCTAssertEqual(try runLibrary.count(), 1)

        try runLibrary.delete(id: run.id)
        XCTAssertEqual(try runLibrary.count(), 0)
        XCTAssertNil(try runLibrary.fetch(id: run.id))

        // Simulate a late NotesEditor / onDisappear commit after delete.
        run.outcomeSummary = "Should not come back"
        try runLibrary.save(run)
        XCTAssertEqual(try runLibrary.count(), 0, "Deleted run must not be re-inserted by a deferred save")
        XCTAssertNil(try runLibrary.fetch(id: run.id))
    }

    func testListSummariesStableOldestCreatedFirst() throws {
        var older = Run.makeDraft(title: "Oldest")
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        older.modifiedAt = Date(timeIntervalSince1970: 1_000)
        try runLibrary.save(older)

        var newer = Run.makeDraft(title: "Newest")
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        newer.modifiedAt = Date(timeIntervalSince1970: 2_000)
        try runLibrary.save(newer)

        // Touch the older run so modifiedAt is later — must not reorder the list.
        var loaded = try runLibrary.require(older.id)
        loaded.client = "Updated Johnson"
        try runLibrary.save(loaded)

        let titles = try runLibrary.listSummaries().map(\.title)
        XCTAssertEqual(titles, ["Oldest", "Newest"])
    }
}
