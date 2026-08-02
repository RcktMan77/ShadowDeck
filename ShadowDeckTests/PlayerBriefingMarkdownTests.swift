//
//  PlayerBriefingMarkdownTests.swift
//  ShadowDeckTests
//
//  Golden / field-hide rules for player briefing Markdown (Phase 2E).
//

import XCTest
@testable import ShadowDeck

final class PlayerBriefingMarkdownTests: XCTestCase {
    private func sampleRun() -> Run {
        var run = Run.makeDraft(title: "SRM 5A-02: Critic's Choice")
        run.client = "Mr. Johnson"
        run.location = "Downtown Seattle"
        run.tags = ["Extraction", "Quiet"]
        run.status = .planning
        run.playerFacingSummary = "Meet the Johnson at Dante's. Secure the chips. Keep it non-lethal."
        run.knownRisks = "Building security is light after 22:00. Avoid the garage cameras."
        run.expectedPayout = RunPayout(nuyen: 7_050, karma: 6)
        run.gmNotes = "GMONLY_DRAGON: target is a dragon in disguise"
        run.opposition = "GMONLY_SAMURAI: 12 Red Samurai in the basement"
        run.complicationsNotes = "GMONLY_TRAP: family save trap room"
        run.heatDelta = 3
        run.objectives = [
            RunObjective(text: "Secure Dr. Tate's property", isPrimary: true, status: .pending),
            RunObjective(text: "Extract Becky 99's sim chips", isPrimary: true, status: .pending),
            RunObjective(text: "Family Save (optional)", isPrimary: false, status: .pending),
            RunObjective(text: "Failed side goal", isPrimary: false, status: .failed)
        ]
        run.contacts = [
            RunContactLink(
                role: .johnson,
                displayName: "Ms. Myth",
                displayRoleLabel: "Fixer front"
            )
        ]
        return run
    }

    func testRenderIncludesPlayerFacingFields() {
        let md = PlayerBriefingMarkdown.render(sampleRun())

        XCTAssertTrue(md.contains("# SRM 5A-02: Critic's Choice"))
        XCTAssertTrue(md.contains("**Client:** Ms. Myth")) // Johnson link wins over free-text client
        XCTAssertTrue(md.contains("**Location:** Downtown Seattle"))
        XCTAssertTrue(md.contains("## What you know"))
        XCTAssertTrue(md.contains("Meet the Johnson at Dante's"))
        XCTAssertTrue(md.contains("Secure Dr. Tate's property"))
        XCTAssertTrue(md.contains("Family Save (optional)"))
        XCTAssertTrue(md.contains("## Known risks"))
        XCTAssertTrue(md.contains("garage cameras"))
        XCTAssertTrue(md.contains("**Expected:** ¥7,050 + 6 karma") || md.contains("¥7050"))
    }

    func testRenderHidesGMOnlyFields() {
        let md = PlayerBriefingMarkdown.render(sampleRun())

        XCTAssertFalse(md.contains("GMONLY_DRAGON"))
        XCTAssertFalse(md.contains("dragon in disguise"))
        XCTAssertFalse(md.contains("GMONLY_SAMURAI"))
        XCTAssertFalse(md.contains("Red Samurai"))
        XCTAssertFalse(md.contains("GMONLY_TRAP"))
        XCTAssertFalse(md.contains("family save trap room"))
        // Heat internals / award math should not appear as sections
        XCTAssertFalse(md.contains("## Heat"))
        XCTAssertFalse(md.contains("equal split"))
        XCTAssertFalse(md.contains("per runner"))
    }

    func testHideFailedObjectivesOption() {
        let run = sampleRun()
        let hidden = PlayerBriefingMarkdown.render(
            run,
            options: .init(includeSecondaryObjectives: true, hideFailedObjectives: true)
        )
        XCTAssertFalse(hidden.contains("Failed side goal"))

        let shown = PlayerBriefingMarkdown.render(
            run,
            options: .init(includeSecondaryObjectives: true, hideFailedObjectives: false)
        )
        XCTAssertTrue(shown.contains("Failed side goal"))
    }

    func testExcludeSecondaryObjectives() {
        let md = PlayerBriefingMarkdown.render(
            sampleRun(),
            options: .init(includeSecondaryObjectives: false, hideFailedObjectives: true)
        )
        XCTAssertTrue(md.contains("Secure Dr. Tate"))
        XCTAssertFalse(md.contains("Family Save"))
    }

    func testLegacyRunWithoutBriefingFieldsDecodes() throws {
        let json = Data("""
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "schemaVersion": 1,
          "title": "Legacy Job",
          "tags": [],
          "status": "planning",
          "client": "J",
          "location": "Barrens",
          "objectives": [],
          "opposition": "GMONLY_OPP_LEGACY",
          "complicationsNotes": "",
          "expectedPayout": { "nuyen": 100, "karma": 1 },
          "heatDelta": 0,
          "participantCharacterIDs": [],
          "sessionLog": [],
          "outcomeSummary": "",
          "gmNotes": "GMONLY_NOTES_LEGACY",
          "createdAt": "2020-01-01T00:00:00Z",
          "modifiedAt": "2020-01-01T00:00:00Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(Run.self, from: json)
        XCTAssertEqual(run.playerFacingSummary, "")
        XCTAssertEqual(run.knownRisks, "")
        let md = PlayerBriefingMarkdown.render(run)
        XCTAssertTrue(md.contains("Legacy Job"))
        XCTAssertFalse(md.contains("GMONLY_NOTES_LEGACY"))
        XCTAssertFalse(md.contains("GMONLY_OPP_LEGACY"))
    }

    func testActualPayoutIncludedWhenPresent() {
        var run = sampleRun()
        run.actualPayout = RunPayout(nuyen: 8_000, karma: 7)
        let md = PlayerBriefingMarkdown.render(run)
        XCTAssertTrue(md.contains("**Actual:**"))
        XCTAssertTrue(md.contains("8,000") || md.contains("8000"))
    }
}
