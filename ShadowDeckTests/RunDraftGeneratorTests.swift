//
//  RunDraftGeneratorTests.swift
//  ShadowDeckTests
//
//  Heuristic draft + RunDraft → Run mapping (Phase 2F).
//

import XCTest
@testable import ShadowDeck

final class RunDraftGeneratorTests: XCTestCase {
    func testHeuristicExtractsMissionCodeAndObjectives() {
        let text = """
        SRM 05-01: Chasing the Wind
        Client: Mr. Johnson of the Downtown Fixer Network
        Location: Seattle, Touristville

        Objectives:
        - Recover the data chip from the warehouse
        - Avoid Lone Star patrols on exit
        - Optional: free the captive runner

        Payout: ¥12,000 and 4 karma
        """
        let draft = RunDraftGenerator.heuristicDraft(from: text, fallbackTitle: "Fallback")
        XCTAssertTrue(draft.title.contains("Chasing") || draft.title.contains("SRM"))
        XCTAssertNotNil(draft.missionCode)
        XCTAssertFalse(draft.objectives.isEmpty)
        XCTAssertEqual(draft.expectedPayoutNuyen, 12_000)
        XCTAssertEqual(draft.expectedKarma, 4)
        XCTAssertFalse(draft.usedOnDeviceAI)
    }

    func testMakeRunMapsFields() {
        var draft = RunDraft(
            title: "Test Job",
            missionCode: "SRM-X",
            client: "Ms. Myth",
            location: "Bellevue",
            objectives: ["Get in", "Get out"],
            oppositionSummary: "Security drones",
            expectedPayoutNuyen: 5000,
            expectedKarma: 3,
            playerFacingSummary: "Meet at Dante's",
            knownRisks: "Cameras",
            gmNotes: "Secret twist",
            sourcePDFTitle: "Mission.pdf",
            sourcePageRange: 2...5
        )
        draft.usedOnDeviceAI = false
        let run = draft.makeRun(edition: .sr5, campaignID: nil)
        XCTAssertEqual(run.title, "Test Job")
        XCTAssertEqual(run.client, "Ms. Myth")
        XCTAssertEqual(run.location, "Bellevue")
        XCTAssertEqual(run.objectives.count, 2)
        XCTAssertTrue(run.objectives[0].isPrimary)
        XCTAssertFalse(run.objectives[1].isPrimary)
        XCTAssertEqual(run.expectedPayout.nuyen, 5000)
        XCTAssertEqual(run.expectedPayout.karma, 3)
        XCTAssertEqual(run.playerFacingSummary, "Meet at Dante's")
        XCTAssertEqual(run.knownRisks, "Cameras")
        XCTAssertTrue(run.opposition.contains("drone") || run.opposition == "Security drones")
        XCTAssertTrue(run.gmNotes.contains("Mission.pdf"))
        XCTAssertTrue(run.tags.contains("SRM-X"))
        XCTAssertEqual(run.status, .planning)
    }

    func testEmptyTextDraftStillHasTitle() {
        let draft = RunDraftGenerator.heuristicDraft(from: "", fallbackTitle: "My PDF")
        XCTAssertEqual(draft.title, "My PDF")
    }
}
