//
//  RunDraftGeneratorTests.swift
//  ShadowDeckTests
//
//  Heuristic draft + RunDraft → Run mapping (Phase 2F).
//  Includes synthetic SRM-shaped fixtures and optional live tests against
//  the developer’s local Missions PDF folder.
//

import XCTest
@testable import ShadowDeck

final class RunDraftGeneratorTests: XCTestCase {
    // MARK: - Synthetic (always run)

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
        XCTAssertFalse(draft.usedOnDeviceAI)
        XCTAssertFalse(draft.gmNotes.isEmpty)
        XCTAssertFalse(draft.gmNotes.contains("## "))
    }

    /// Fixture shaped like real SRM 5A living-campaign PDF text extraction.
    private var srmShapedFixture: String {
        """
        COVER
        INTRO
        MISSION
        SYNOPSIS
        SCENE 1
        SCENE 2
        PICKING UP
        THE PIECES
        LEGWORK
        CAST OF
        SHADOWS

        5

        PREPARING THE ADVENTURE
        SRM 5A-01: Chasin' the Wind is a Shadowrun Missions living campaign adventure.
        Step 1: Read The Adventure
        Carefully read the adventure from beginning to end.
        GENERAL ADVENTURE RULES
        Paperwork
        After running a Shadowrun Missions adventure, fill out the Debriefing Log.

        MISSION SYNOPSIS
        The runners are hired by Quantum Princess to insert wireless transmitters into
        two Matrix nodes just inside the CZ in Chicago. Meanwhile, Simon Andrews and
        Juan Xihuitl also want the team for conflicting jobs involving a fugitive
        technomancer named Samantha and a secret lab in the Containment Zone.

        SCENE 1: EVERYONE COMES KNOCKING

        Scan This
        In this scene, the runners' respective fixers contact them with a job from Quantum Princess.

        Tell It to Them Straight
        What a surprise. It's snowing in Chicago in January. Then your commlink flashes
        the face of your fixer. "I got a job for you, omae, headed into the CZ. Johnson
        would like to meet in person in two hours. There's a table reserved at Chicago's
        Own Pizzeria in Northside."
        When you arrive, Ms. Johnson is already there. "Thank you for meeting with me.
        Some of you might know me as Quantum Princess. I have a short job for you.
        I'm offering 4,000 nuyen for the job."

        Behind the Scenes
        Quantum Princess wants to hire the runners to insert wireless transmitters into
        two Matrix nodes just inside the CZ. She'll offer the runners 4,000 nuyen each,
        plus 500 nuyen per net hit. The first node is at Midway Airport. Security in the
        Zone includes gangs and Lone Star watching the borders.

        PICKING UP THE PIECES
        Money
        • 4,000 nuyen each, plus 500 nuyen per net hit from Quantum Princess
        Karma
        The maximum adventure award for characters that play this adventure is 6.
        Karma Earned: 6
        Nuyen Earned: 13,000¥
        Reputation
        • +1 Street Cred if the runners complete the task for Quantum Princess.
        • +1 Notoriety if the runners plug Sam back into a tank.
        +1 Public Awareness if the team gets into a fight downtown.

        CAST OF SHADOWS
        B A R S W L I C M EDG ESS
        2 7 8 1 4 4 4 4 2 4 4
        Initiative: 12 + 1D6
        Condition Monitors (P/S): 10/11
        """
    }

    func testSRMShapedFixtureExtractsStructuredFields() {
        let draft = RunDraftGenerator.heuristicDraft(
            from: srmShapedFixture,
            fallbackTitle: "Shadowrun Missions - Chasin' the Wind (5A-01).pdf",
            pageRange: 1...12
        )

        XCTAssertTrue(
            draft.title.localizedCaseInsensitiveContains("Chasin")
                || draft.title.localizedCaseInsensitiveContains("5A-01"),
            "title=\(draft.title)"
        )
        XCTAssertEqual(draft.missionCode, "SRM 5A-01", "code=\(draft.missionCode ?? "nil")")
        XCTAssertTrue(
            draft.client.localizedCaseInsensitiveContains("Quantum")
                || draft.client.localizedCaseInsensitiveContains("Princess")
                || draft.client.localizedCaseInsensitiveContains("Johnson"),
            "client=\(draft.client)"
        )
        XCTAssertTrue(
            draft.location.localizedCaseInsensitiveContains("Chicago")
                || draft.location.localizedCaseInsensitiveContains("CZ")
                || draft.location.localizedCaseInsensitiveContains("Pizzeria"),
            "location=\(draft.location)"
        )
        XCTAssertFalse(draft.playerFacingSummary.isEmpty, "playerFacing empty")
        XCTAssertTrue(
            draft.playerFacingSummary.localizedCaseInsensitiveContains("Quantum")
                || draft.playerFacingSummary.localizedCaseInsensitiveContains("fixer")
                || draft.playerFacingSummary.localizedCaseInsensitiveContains("CZ"),
            "playerFacing should use Scan This / Tell It text"
        )
        // Should not be dominated by PREPARING THE ADVENTURE boilerplate.
        XCTAssertFalse(
            draft.playerFacingSummary.localizedCaseInsensitiveContains("Debriefing Log")
        )
        XCTAssertFalse(draft.objectives.isEmpty, "objectives empty")
        XCTAssertEqual(draft.expectedPayoutNuyen, 13_000, "prefer Nuyen Earned total when present")
        XCTAssertEqual(draft.expectedKarma, 6)
        XCTAssertFalse(draft.gmNotes.isEmpty)
        // No markdown section headers or NPC stat-block soup in GM notes.
        XCTAssertFalse(draft.gmNotes.contains("## "))
        XCTAssertFalse(draft.gmNotes.contains("B A R S W"))
        XCTAssertFalse(draft.gmNotes.contains("EDG ESS"))
        XCTAssertEqual(draft.expectedStreetCred, 1)
        XCTAssertEqual(draft.expectedNotoriety, 1)
        XCTAssertEqual(draft.expectedPublicAwareness, 1)
        XCTAssertTrue(draft.reputationNotes.localizedCaseInsensitiveContains("Street Cred"))
        XCTAssertTrue(
            draft.oppositionSummary.localizedCaseInsensitiveContains("gang")
                || draft.oppositionSummary.localizedCaseInsensitiveContains("Lone Star")
                || draft.oppositionSummary.localizedCaseInsensitiveContains("Security")
                || !draft.oppositionSummary.isEmpty
        )
    }

    func testStripStatBlocksRemovesAttributeRows() {
        let raw = """
        The lab is abandoned.
        B A R S W L I C M EDG ESS
        2 7 8 1 4 4 4 4 2 4 4
        Initiative: 12 + 1D6
        Runners find cloning tanks.
        """
        let stripped = RunDraftHeuristic.stripStatBlocks(raw)
        XCTAssertTrue(stripped.contains("abandoned"))
        XCTAssertTrue(stripped.contains("cloning"))
        XCTAssertFalse(stripped.contains("EDG"))
        XCTAssertFalse(stripped.contains("2 7 8 1"))
    }

    func testProseLeftTrimsPDFPadding() {
        let padded = "        The meet is at noon.\n            Bring guns."
        let out = RunDraftHeuristic.prose(padded)
        XCTAssertTrue(out.hasPrefix("The meet"))
        XCTAssertFalse(out.hasPrefix(" "))
    }

    func testHeuristicKeepsLongPlayerFacingText() {
        let longPara = String(repeating: "The runners are hired to infiltrate a downtown arcology. ", count: 40)
        let text = """
        MISSION SYNOPSIS
        \(longPara)

        Scan This
        The team meets a Johnson who needs an arcology data steal under heavy security drone patrol.

        Tell It to Them Straight
        \(longPara)

        Risks: Lone Star security drones patrol the rooftop.
        """
        let draft = RunDraftGenerator.heuristicDraft(from: text, fallbackTitle: "Arcology Job")
        XCTAssertGreaterThan(draft.playerFacingSummary.count, 200)
        XCTAssertTrue(
            draft.playerFacingSummary.contains("arcology")
                || draft.playerFacingSummary.contains("Johnson")
        )
    }

    func testHeuristicNumberedObjectivesAndSection() {
        let text = """
        MISSION SYNOPSIS
        A facility hit for a prototype.

        Scan This
        The runners enter the facility without raising alarms and extract the prototype.

        Behind the Scenes
        Corporate security teams with two mage support units wait inside.

        1. Enter the facility without raising alarms
        2. Locate the prototype and extract it intact
        3. Deliver the package to the drop site
        """
        let draft = RunDraftGenerator.heuristicDraft(from: text, fallbackTitle: "Facility")
        XCTAssertFalse(draft.objectives.isEmpty)
        XCTAssertTrue(
            draft.oppositionSummary.localizedCaseInsensitiveContains("security")
                || draft.oppositionSummary.localizedCaseInsensitiveContains("mage")
                || !draft.oppositionSummary.isEmpty
        )
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

    func testNormalizePageTextRejoinsHyphenation() {
        let raw = "The corpo-\nration security team\n\npatrols the roof."
        let normalized = PDFMissionTextExtractor.normalizePageText(raw)
        XCTAssertTrue(normalized.contains("corporation"))
        XCTAssertFalse(normalized.contains("corpo-\n"))
    }

    func testHeuristicLimitsAreRelaxedVersusAI() {
        let ai = PDFMissionTextExtractor.Limits.onDeviceAI
        let heuristic = PDFMissionTextExtractor.Limits.heuristic
        XCTAssertGreaterThan(heuristic.hardMaxPages, ai.hardMaxPages)
        XCTAssertGreaterThan(heuristic.maxCharacters, ai.maxCharacters)
        XCTAssertGreaterThan(heuristic.defaultMaxPages, ai.defaultMaxPages)
    }

    func testCleanStripsTOCAndKeepsSynopsis() {
        let cleaned = RunDraftHeuristic.clean(srmShapedFixture)
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("MISSION SYNOPSIS"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("Quantum Princess"))
        // Pure TOC rails should be gone.
        let lines = cleaned.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertFalse(lines.contains("COVER"))
        XCTAssertFalse(lines.contains("LEGWORK"))
        // Section headers must survive for the parser.
        XCTAssertTrue(lines.contains { $0.caseInsensitiveCompare("MISSION SYNOPSIS") == .orderedSame }
            || cleaned.localizedCaseInsensitiveContains("\nMISSION SYNOPSIS\n")
            || cleaned.hasPrefix("MISSION SYNOPSIS"))
    }

}
