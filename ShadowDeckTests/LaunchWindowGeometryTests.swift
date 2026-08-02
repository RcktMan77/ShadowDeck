//
//  LaunchWindowGeometryTests.swift
//  ShadowDeckTests
//
//  Pure helpers for splash vs main frame decisions (no live NSWindow).
//

import XCTest
@testable import ShadowDeck

final class LaunchWindowGeometryTests: XCTestCase {
    func testSplashContentSizeAspectIs3to2() {
        let s = LaunchWindowGeometry.splashContentSize
        XCTAssertEqual(s.width, 840)
        XCTAssertEqual(s.height, 560)
        XCTAssertEqual(s.width / s.height, 1.5, accuracy: 0.001)
    }

    func testIsNearSplashSize() {
        let splash = LaunchWindowGeometry.splashContentSize
        XCTAssertTrue(LaunchWindowGeometry.isNearSplashSize(splash))
        XCTAssertTrue(LaunchWindowGeometry.isNearSplashSize(NSSize(width: splash.width + 20, height: splash.height - 10)))
        XCTAssertFalse(LaunchWindowGeometry.isNearSplashSize(LaunchWindowGeometry.mainContentSize))
    }

    func testIsPlausibleMainFrame() {
        XCTAssertTrue(LaunchWindowGeometry.isPlausibleMainFrame(NSRect(x: 100, y: 100, width: 1100, height: 720)))
        XCTAssertFalse(LaunchWindowGeometry.isPlausibleMainFrame(NSRect(x: 0, y: 0, width: 400, height: 300)))
        XCTAssertFalse(LaunchWindowGeometry.isPlausibleMainFrame(NSRect(x: 0, y: 0, width: 20_000, height: 720)))
    }

    func testClampedFrameKeepsMinimumDeckSize() {
        let vf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let small = NSRect(x: 10, y: 10, width: 500, height: 400)
        let clamped = LaunchWindowGeometry.clampedFrame(small, visibleFrame: vf)
        XCTAssertGreaterThanOrEqual(clamped.width, 900)
        XCTAssertGreaterThanOrEqual(clamped.height, 520)
    }

    func testCenterOrigin() {
        let vf = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let f = NSRect(x: 0, y: 0, width: 200, height: 100)
        let origin = LaunchWindowGeometry.centerOrigin(windowFrame: f, visibleFrame: vf)
        XCTAssertEqual(origin.x, 400, accuracy: 0.5)
        XCTAssertEqual(origin.y, 350, accuracy: 0.5)
    }
}
