//
//  LifestyleTrackerTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class LifestyleTrackerTests: XCTestCase {

    private func baseCharacter(
        nuyen: Int = 10_000,
        reserve: Int = 0,
        lifestyles: [Lifestyle]
    ) -> Character {
        Character(
            name: "Test",
            edition: .sr5,
            generation: GenerationProfile(system: .priority),
            lifestyles: lifestyles,
            nuyen: nuyen,
            lifestyleNuyenReserve: reserve
        )
    }

    // MARK: - Burn summary

    func testBurnSummaryActiveOnly() {
        let c = baseCharacter(lifestyles: [
            Lifestyle(name: "A", monthlyCost: 2_000, monthsPrepaid: 1, isActive: true),
            Lifestyle(name: "B", monthlyCost: 5_000, monthsPrepaid: 0, isActive: true),
            Lifestyle(name: "C", monthlyCost: 100_000, monthsPrepaid: 0, isActive: false),
        ])
        let s = LifestyleTracker.burnSummary(for: c)
        XCTAssertEqual(s.monthlyBurn, 7_000)
        XCTAssertEqual(s.prepaidCoveredBurn, 2_000)
        XCTAssertEqual(s.cashDue, 5_000)
        XCTAssertEqual(s.activeCount, 2)
        XCTAssertEqual(s.overallStatus, .due)
    }

    func testUnderfundedWhenCashDueExceedsLiquidity() {
        let c = baseCharacter(nuyen: 1_000, reserve: 500, lifestyles: [
            Lifestyle(monthlyCost: 5_000, monthsPrepaid: 0),
        ])
        let s = LifestyleTracker.burnSummary(for: c)
        XCTAssertTrue(s.isUnderfundedForOneMonth)
        XCTAssertEqual(s.overallStatus, .underfunded)
    }

    // MARK: - Process months

    func testProcessMonthUsesPrepaidThenCash() throws {
        var c = baseCharacter(nuyen: 10_000, reserve: 0, lifestyles: [
            Lifestyle(name: "Pad", monthlyCost: 2_000, monthsPrepaid: 1),
            Lifestyle(name: "Bolt-hole", monthlyCost: 500, monthsPrepaid: 0),
        ])
        try LifestyleTracker.processMonths(&c, months: 1)
        XCTAssertEqual(c.lifestyles[0].monthsPrepaid, 0)
        XCTAssertEqual(c.lifestyles[1].monthsPrepaid, 0)
        XCTAssertEqual(c.nuyen, 9_500) // only bolt-hole charged
        XCTAssertNotNil(c.lifestyleLastProcessedAt)
        XCTAssertEqual(c.lifestyleLedgerEntries.first?.kind, .processMonth)
    }

    func testProcessMonthReserveBeforeNuyen() throws {
        var c = baseCharacter(nuyen: 1_000, reserve: 4_000, lifestyles: [
            Lifestyle(monthlyCost: 5_000, monthsPrepaid: 0),
        ])
        try LifestyleTracker.processMonths(&c, months: 1)
        XCTAssertEqual(c.lifestyleNuyenReserve, 0)
        XCTAssertEqual(c.nuyen, 0)
    }

    func testProcessMonthShortfallBlocksAllChanges() {
        var c = baseCharacter(nuyen: 100, reserve: 100, lifestyles: [
            Lifestyle(monthlyCost: 5_000, monthsPrepaid: 0),
        ])
        let before = c
        XCTAssertThrowsError(try LifestyleTracker.processMonths(&c, months: 1)) { error in
            guard let err = error as? LifestyleTrackerError,
                  case .shortfall = err
            else {
                return XCTFail("Expected shortfall, got \(error)")
            }
        }
        XCTAssertEqual(c.nuyen, before.nuyen)
        XCTAssertEqual(c.lifestyleNuyenReserve, before.lifestyleNuyenReserve)
        XCTAssertEqual(c.lifestyles[0].monthsPrepaid, 0)
        XCTAssertNil(c.lifestyleLastProcessedAt)
    }

    func testProcessThreeMonthsCatchUp() throws {
        // Month 1: prepaid covers 2k; Month 2–3: pay 2k each from nuyen
        var c = baseCharacter(nuyen: 10_000, reserve: 0, lifestyles: [
            Lifestyle(monthlyCost: 2_000, monthsPrepaid: 1),
        ])
        try LifestyleTracker.processMonths(&c, months: 3)
        XCTAssertEqual(c.lifestyles[0].monthsPrepaid, 0)
        XCTAssertEqual(c.nuyen, 6_000) // 2 months × 2k
    }

    func testProcessMultiMonthShortfallUsesProjectedCash() {
        // 1 prepaid + 2 months cash @ 5k = 10k needed; only 3k liquid
        var c = baseCharacter(nuyen: 3_000, reserve: 0, lifestyles: [
            Lifestyle(monthlyCost: 5_000, monthsPrepaid: 1),
        ])
        XCTAssertEqual(LifestyleTracker.cashRequiredToProcess(character: c, months: 3), 10_000)
        XCTAssertThrowsError(try LifestyleTracker.processMonths(&c, months: 3))
    }

    func testInvalidMonthCount() {
        var c = baseCharacter(lifestyles: [])
        XCTAssertThrowsError(try LifestyleTracker.processMonths(&c, months: 0))
        XCTAssertThrowsError(try LifestyleTracker.processMonths(&c, months: 4))
    }

    // MARK: - Prepay

    func testPrepayFromNuyenNotReserve() throws {
        let id = UUID()
        var c = baseCharacter(nuyen: 10_000, reserve: 50_000, lifestyles: [
            Lifestyle(id: id, monthlyCost: 2_000, monthsPrepaid: 0),
        ])
        try LifestyleTracker.prepay(lifestyleID: id, months: 3, character: &c)
        XCTAssertEqual(c.nuyen, 4_000)
        XCTAssertEqual(c.lifestyleNuyenReserve, 50_000)
        XCTAssertEqual(c.lifestyles[0].monthsPrepaid, 3)
        XCTAssertEqual(c.lifestyleLedgerEntries.first?.kind, .prepay)
    }

    func testPrepayInsufficientNuyen() {
        let id = UUID()
        var c = baseCharacter(nuyen: 1_000, lifestyles: [
            Lifestyle(id: id, monthlyCost: 2_000, monthsPrepaid: 0),
        ])
        XCTAssertThrowsError(try LifestyleTracker.prepay(lifestyleID: id, months: 1, character: &c))
    }

    // MARK: - Reserve

    func testReserveDepositAndWithdraw() throws {
        var c = baseCharacter(nuyen: 5_000, reserve: 0, lifestyles: [])
        try LifestyleTracker.depositToReserve(amount: 2_000, character: &c)
        XCTAssertEqual(c.nuyen, 3_000)
        XCTAssertEqual(c.lifestyleNuyenReserve, 2_000)
        try LifestyleTracker.withdrawFromReserve(amount: 500, character: &c)
        XCTAssertEqual(c.nuyen, 3_500)
        XCTAssertEqual(c.lifestyleNuyenReserve, 1_500)
    }

    // MARK: - Codable

    func testLifestyleLegacyJSONDefaultsIsActive() throws {
        let json = """
        {"id":"AAAAAAAA-0000-4000-8000-000000000001","name":"Pad","level":"low","monthlyCost":2000,"monthsPrepaid":1,"notes":""}
        """.data(using: .utf8)!
        let life = try JSONDecoder().decode(Lifestyle.self, from: json)
        XCTAssertTrue(life.isActive)
        XCTAssertNil(life.nextDueDate)
    }

    func testCharacterRoundTripKeepsLedgerAndLastProcessed() throws {
        var c = SampleCharacters.sr5CombatMage()
        c.lifestyleLastProcessedAt = Date(timeIntervalSince1970: 1_700_000_000)
        c.appendLifestyleLedger(
            LifestyleLedgerEntry(kind: .processMonth, amount: -2000, note: "Test")
        )
        let data = try PortableCharacterCoding.encoder().encode(c)
        let decoded = try PortableCharacterCoding.decoder().decode(Character.self, from: data)
        XCTAssertEqual(decoded.lifestyleLastProcessedAt, c.lifestyleLastProcessedAt)
        XCTAssertEqual(decoded.lifestyleLedgerEntries.count, 1)
        XCTAssertEqual(decoded.lifestyleLedgerEntries.first?.note, "Test")
    }
}
