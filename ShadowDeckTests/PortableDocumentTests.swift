//
//  PortableDocumentTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class PortableDocumentTests: XCTestCase {
    func testRoundTripAllSampleCharacters() throws {
        for character in SampleCharacters.makeAll() {
            let data = try PortableCharacterCoding.encodeCharacter(character)
            let decoded = try PortableCharacterCoding.decode(from: data)
            XCTAssertEqual(decoded.formatVersion, ShadowDeckFormat.currentFormatVersion)
            XCTAssertEqual(decoded.character.id, character.id)
            XCTAssertEqual(decoded.character.edition, character.edition)
            XCTAssertEqual(decoded.character.name, character.name)
            XCTAssertEqual(decoded.character.attributes, character.attributes)
            XCTAssertEqual(decoded.character.skills.count, character.skills.count)
            XCTAssertEqual(decoded.character.houseRules, character.houseRules)
            XCTAssertEqual(decoded.character.generation.system, character.generation.system)
        }
    }

    func testManifestFromCharacter() {
        let character = SampleCharacters.sr5CombatMage()
        let manifest = PortableManifest(from: character)
        XCTAssertEqual(manifest.characterID, character.id)
        XCTAssertEqual(manifest.edition, .sr5)
        XCTAssertEqual(manifest.schemaVersion, Character.currentSchemaVersion)
        XCTAssertFalse(manifest.hasAvatar)
    }

    func testFormatConstants() {
        XCTAssertEqual(ShadowDeckFormat.fileExtension, "shadowdeck")
        XCTAssertEqual(ShadowDeckFormat.characterJSONFileName, "character.json")
    }

    func testHouseRulesPresets() {
        XCTAssertTrue(HouseRules.coreBook.enabled.isEmpty)
        XCTAssertTrue(HouseRules.popularTable.isEnabled(.sumToTen))
        XCTAssertTrue(HouseRules.popularTable.isEnabled(.bonusStartingKarma))
        XCTAssertTrue(HouseRules.primeRunner.isEnabled(.primeRunnerPackage))
        XCTAssertEqual(HouseRuleID.allCases.count, 10)
    }

    func testCodableHouseRulesWithSet() throws {
        let rules = HouseRules.popularTable
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode(HouseRules.self, from: data)
        XCTAssertEqual(decoded, rules)
    }
}
