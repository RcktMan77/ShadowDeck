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
}
