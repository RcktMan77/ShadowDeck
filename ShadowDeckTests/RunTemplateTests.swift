//
//  RunTemplateTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

@MainActor
final class RunTemplateTests: XCTestCase {
    func testResolvedTitleSubstitutesLocation() {
        let t = RunTemplate(
            name: "Extraction",
            titlePattern: "Extraction — {location}",
            isBuiltin: true
        )
        XCTAssertEqual(t.resolvedTitle(location: "Downtown"), "Extraction — Downtown")
        XCTAssertEqual(t.resolvedTitle(location: "  "), "Extraction — TBD")
    }

    func testMakeDraftFromTemplate() {
        let t = RunTemplate.builtins.first { $0.name == "Data steal" }!
        let run = Run.makeDraft(from: t, location: "Renraku Arcology")
        XCTAssertEqual(run.title, "Data steal — Renraku Arcology")
        XCTAssertEqual(run.location, "Renraku Arcology")
        XCTAssertEqual(run.tags, t.tags)
        XCTAssertEqual(run.objectives.count, t.objectives.count)
        XCTAssertEqual(run.expectedPayout, t.expectedPayout)
        XCTAssertEqual(run.status, .planning)
    }

    func testUserTemplateStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-TemplateTest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = RunTemplateStore(fileURL: url)
        XCTAssertEqual(store.allTemplates().count, RunTemplate.builtins.count)

        var seed = Run.makeDraft(title: "My Job")
        seed.location = "Tacoma"
        let custom = seed.asTemplate(name: "Tacoma job")
        try store.saveUserTemplate(custom)
        XCTAssertEqual(store.allTemplates().count, RunTemplate.builtins.count + 1)

        let reloaded = RunTemplateStore(fileURL: url)
        XCTAssertEqual(reloaded.allTemplates().filter { !$0.isBuiltin }.count, 1)
        XCTAssertEqual(reloaded.allTemplates().first { !$0.isBuiltin }?.name, "Tacoma job")

        try reloaded.deleteUserTemplate(id: custom.id)
        XCTAssertEqual(reloaded.allTemplates().count, RunTemplate.builtins.count)

        XCTAssertThrowsError(try store.deleteUserTemplate(id: RunTemplate.builtins[0].id)) { err in
            XCTAssertEqual(err as? RunTemplateStoreError, .builtinImmutable)
        }
    }

    func testAsTemplateReplacesLocationInTitle() {
        var run = Run.makeDraft(title: "Courier — Bellevue")
        run.location = "Bellevue"
        run.tags = ["Courier"]
        let template = run.asTemplate(name: "Courier pattern")
        XCTAssertEqual(template.titlePattern, "Courier — {location}")
        XCTAssertFalse(template.isBuiltin)
    }
}
