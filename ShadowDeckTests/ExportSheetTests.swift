//
//  ExportSheetTests.swift
//  ShadowDeckTests
//
//  Phase 9B — PDF sheet + Chummer export (original + regenerated).
//

import XCTest
@testable import ShadowDeck

final class ExportSheetTests: XCTestCase {
    func testPDFRendersForSampleCharacter() throws {
        let character = SampleCharacters.sr5CombatMage()
        let report = CampaignSheetReport.build(for: character)
        let data = try CharacterSheetPDF.render(report: report)
        XCTAssertGreaterThan(data.count, 500)
        let prefix = String(data: data.prefix(5), encoding: .ascii)
        XCTAssertEqual(prefix, "%PDF-")
    }

    func testPDFWithPortraitStillRenders() throws {
        var character = SampleCharacters.sr5CombatMage()
        // 1x1 PNG
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        character.avatar.inlineData = png
        character.avatar.mimeType = "image/png"
        let data = try CharacterSheetPDF.render(report: .build(for: character))
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
    }

    func testChummerExportRoundTripCoreFields() throws {
        let original = SampleCharacters.sr5CombatMage()
        let result = try ChummerXMLExporter.export(original, mode: .regeneratedOnly)
        XCTAssertFalse(result.usedOriginalPayload)
        XCTAssertFalse(result.fidelity.included.isEmpty)

        let imported = try CharacterImporter.importChummerXML(
            result.xmlData,
            fileName: "export_test.chum5"
        )
        let c = imported.character
        XCTAssertEqual(c.name, original.name)
        XCTAssertEqual(c.streetName, original.streetName)
        XCTAssertEqual(c.edition, original.edition)
        XCTAssertEqual(c.nuyen, original.nuyen)
        XCTAssertEqual(c.attributes.body, original.attributes.body)
        XCTAssertFalse(c.skills.isEmpty)
        XCTAssertNotNil(c.importProvenance?.originalPayload)
    }

    func testOriginalPayloadExportIsByteFaithful() throws {
        let source = try Data(contentsOf: URL(fileURLWithPath:
            "/Users/zdavis/Documents/eBooks/Shadowrun/ghostwire.chum5"
        ))
        let imported = try CharacterImporter.importChummerXML(source, fileName: "ghostwire.chum5")
        var character = imported.character
        XCTAssertNotNil(character.importProvenance?.originalPayload)

        let result = try ChummerXMLExporter.export(character, mode: .preferOriginal)
        XCTAssertTrue(result.usedOriginalPayload)
        XCTAssertEqual(result.xmlData, source)
    }

    func testCampaignReportValidationPresent() {
        let character = SampleCharacters.sr5CombatMage()
        let report = CampaignSheetReport.build(for: character)
        XCTAssertEqual(report.character.id, character.id)
        _ = report.isCampaignReady
        XCTAssertFalse(report.houseRulesSummary.isEmpty)
    }
}
