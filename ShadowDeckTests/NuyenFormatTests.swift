//
//  NuyenFormatTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class NuyenFormatTests: XCTestCase {
    func testGroupedIntegersMatchDecimalNumberFormatter() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        for value in [0, 5_000, 50_000, -2_500] {
            let digits = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
            XCTAssertEqual(NuyenFormat.grouped(value), digits)
            XCTAssertEqual(NuyenFormat.format(value), "¥\(digits)")
            XCTAssertEqual(RunSupport.formatNuyen(value), "¥\(digits)")
        }
    }

    func testEssenceAndPowerPointFractions() {
        let essence = NumberFormatter()
        essence.numberStyle = .decimal
        essence.minimumFractionDigits = 1
        essence.maximumFractionDigits = 2
        let points = NumberFormatter()
        points.numberStyle = .decimal
        points.minimumFractionDigits = 0
        points.maximumFractionDigits = 2
        let whole = Decimal(5)
        let quarter = Decimal(525) / 100
        XCTAssertEqual(
            DecimalFormat.essence(whole),
            essence.string(from: NSDecimalNumber(decimal: whole))
        )
        XCTAssertEqual(
            DecimalFormat.essence(quarter),
            essence.string(from: NSDecimalNumber(decimal: quarter))
        )
        XCTAssertEqual(
            DecimalFormat.powerPoints(whole),
            points.string(from: NSDecimalNumber(decimal: whole))
        )
        XCTAssertEqual(
            DecimalFormat.powerPoints(quarter),
            points.string(from: NSDecimalNumber(decimal: quarter))
        )
    }
}
