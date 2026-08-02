//
//  CampaignPersistenceTests.swift
//  ShadowDeckTests
//

import XCTest
import SwiftData
@testable import ShadowDeck

@MainActor
final class CampaignPersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var env: LibraryEnvironment!
    private var avatarRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-CampaignTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(inMemory: true)
        let library = try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)
        let runLibrary = PersistenceController.makeRunLibrary(container: container)
        let campaignLibrary = PersistenceController.makeCampaignLibrary(container: container)
        env = LibraryEnvironment(
            container: container,
            library: library,
            runLibrary: runLibrary,
            campaignLibrary: campaignLibrary
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: avatarRoot)
        env = nil
        container = nil
        avatarRoot = nil
        try super.tearDownWithError()
    }

    func testCampaignCRUDRoundTrip() throws {
        var campaign = Campaign.makeDraft(name: "Seattle Shadows", edition: .sr5)
        campaign.houseRuleHints = "Edge on glitches"
        try env.campaignLibrary.save(campaign)

        XCTAssertEqual(try env.campaignLibrary.count(), 1)
        let loaded = try env.campaignLibrary.require(campaign.id)
        XCTAssertEqual(loaded.name, "Seattle Shadows")
        XCTAssertEqual(loaded.edition, .sr5)
        XCTAssertEqual(loaded.houseRuleHints, "Edge on glitches")
        XCTAssertFalse(loaded.isArchived)
    }

    func testEmptyNameRejected() throws {
        let campaign = Campaign(name: "   ")
        XCTAssertThrowsError(try env.campaignLibrary.save(campaign)) { error in
            XCTAssertEqual(error as? CampaignLibraryError, .emptyName)
        }
    }

    func testArchiveHiddenFromDefaultList() throws {
        var campaign = Campaign.makeDraft(name: "Archive Me")
        try env.campaignLibrary.save(campaign)
        campaign = try env.campaignLibrary.require(campaign.id)
        campaign.isArchived = true
        try env.campaignLibrary.save(campaign)

        XCTAssertEqual(try env.campaignLibrary.count(includeArchived: false), 0)
        XCTAssertEqual(try env.campaignLibrary.count(includeArchived: true), 1)
        XCTAssertTrue(try env.campaignLibrary.listSummaries(includeArchived: true)[0].isArchived)
    }

    func testDeleteCampaignUnassignsRuns() throws {
        var campaign = Campaign.makeDraft(name: "Temp Table")
        try env.campaignLibrary.save(campaign)

        var run = Run.makeDraft(title: "Job One", campaignID: campaign.id)
        try env.runLibrary.save(run)

        XCTAssertEqual(try env.runLibrary.require(run.id).campaignID, campaign.id)

        try env.deleteCampaignUnassigningRuns(id: campaign.id)

        XCTAssertNil(try env.campaignLibrary.fetch(id: campaign.id))
        XCTAssertNil(try env.runLibrary.require(run.id).campaignID)
        XCTAssertEqual(try env.runLibrary.count(), 1)
    }

    func testRunSummaryCarriesCampaignID() throws {
        var campaign = Campaign.makeDraft(name: "Grouped")
        try env.campaignLibrary.save(campaign)

        var run = Run.makeDraft(title: "Linked", edition: .sr4, campaignID: campaign.id)
        try env.runLibrary.save(run)

        let summary = try env.runLibrary.listSummaries().first
        XCTAssertEqual(summary?.campaignID, campaign.id)
        XCTAssertEqual(summary?.edition, .sr4)

        let filtered = try env.runLibrary.listSummaries(campaignID: campaign.id)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(try env.runLibrary.listSummaries(campaignID: nil).count, 0)
    }

    func testDuplicateRunClearsAwardsAndGetsNewID() throws {
        var run = Run.makeDraft(title: "Original")
        run.applyStatus(.completed)
        run.awardsAppliedAt = Date()
        run.awardsAppliedNote = "paid"
        try env.runLibrary.save(run)

        let copy = try env.runLibrary.duplicate(run.id)
        XCTAssertNotEqual(copy.id, run.id)
        XCTAssertEqual(copy.title, "Copy of Original")
        XCTAssertEqual(copy.status, .planning)
        XCTAssertNil(copy.awardsAppliedAt)
        XCTAssertEqual(try env.runLibrary.count(), 2)
    }

    func testHouseRuleHintsCodecRoundTrip() {
        let encoded = CampaignHouseRuleHintsCodec.encode(
            selectedLabels: ["Sum-to-Ten Priorities", "Hits on 4+"],
            freeText: "No wireless bonuses"
        )
        let decoded = CampaignHouseRuleHintsCodec.decode(encoded)
        XCTAssertEqual(decoded.selectedLabels, ["Sum-to-Ten Priorities", "Hits on 4+"])
        XCTAssertEqual(decoded.freeText, "No wireless bonuses")

        let freeOnly = CampaignHouseRuleHintsCodec.decode("just a free note")
        XCTAssertTrue(freeOnly.selectedLabels.isEmpty)
        XCTAssertEqual(freeOnly.freeText, "just a free note")
    }
}
