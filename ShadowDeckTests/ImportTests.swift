//
//  ImportTests.swift
//  ShadowDeckTests
//

import XCTest
import SwiftData
@testable import ShadowDeck

final class ImportTests: XCTestCase {
    // MARK: - Fixture helpers

    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = fixturesDirectory.appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    // MARK: - Synthetic fixtures (repo Fixtures/ only — no host-local paths)

    func testMinimalJSONImportCoreFields() throws {
        let data = try fixtureData("minimal_sr5.json")
        let result = try CharacterImporter.importChummerJSON(data, fileName: "minimal_sr5.json")
        let c = result.character

        XCTAssertEqual(result.sourceFormat, .chummerJSON)
        XCTAssertEqual(c.name, "Test Runner")
        XCTAssertEqual(c.streetName, "Fixture")
        XCTAssertEqual(c.edition, .sr5)
        XCTAssertEqual(c.metatype, .elf)
        XCTAssertEqual(c.awakened, .fullMagician)
        XCTAssertEqual(c.attributes.magic, 6)
        XCTAssertEqual(c.attributes.agility, 5)
        XCTAssertEqual(c.nuyen, 6000)
        XCTAssertEqual(c.karmaAvailable, 25)
        XCTAssertEqual(c.generation.system, .priority)
        XCTAssertEqual(c.generation.priority[.attributes], .b)
        XCTAssertEqual(c.generation.priority[.magicOrResonance], .a)

        XCTAssertTrue(c.skills.contains { $0.displayName == "Spellcasting" && $0.rating == 6 })
        XCTAssertTrue(c.skills.contains { $0.displayName == "Arcana" && $0.category == .knowledge })
        // Dice pool total must not be used as rating.
        XCTAssertFalse(c.skills.contains { $0.displayName == "Spellcasting" && $0.rating == 11 })

        XCTAssertEqual(c.spells.count, 2)
        XCTAssertEqual(c.contacts.count, 1)
        XCTAssertTrue(c.gear.contains { $0.name == "Armor Jacket" && $0.armorRating == 12 })
        XCTAssertTrue(c.gear.contains { $0.name == "Defiance EX Shocker" })
        XCTAssertFalse(c.gear.contains { $0.name.localizedCaseInsensitiveContains("Unarmed") })
    }

    func testMinimalChum5ImportCoreFields() throws {
        let data = try fixtureData("minimal_sr5.chum5")
        let result = try CharacterImporter.importChummerXML(data, fileName: "minimal_sr5.chum5")
        let c = result.character

        XCTAssertEqual(result.sourceFormat, .chummerChum5)
        XCTAssertEqual(c.name, "XML Fixture")
        XCTAssertEqual(c.streetName, "Wiremock")
        XCTAssertEqual(c.edition, .sr5)
        XCTAssertEqual(c.metatype, .human)
        XCTAssertEqual(c.awakened, .adept)
        XCTAssertEqual(c.attributes.magic, 6)
        // Prefer Chummer base (fixture REA base 4 / total 5 from Improved Reflexes).
        XCTAssertEqual(c.attributes.reaction, 4)
        XCTAssertEqual(c.attributes.essence, Decimal(string: "5.7"))
        XCTAssertEqual(c.nuyen, 12000)
        XCTAssertEqual(c.karmaTotal, 30)
        XCTAssertEqual(c.karmaAvailable, 10)

        XCTAssertTrue(c.skills.contains { $0.displayName == "Pistols" && $0.rating == 5 && $0.specialized == "Semi-Automatics" })
        XCTAssertTrue(c.adeptPowers.contains { $0.name == "Improved Reflexes" && $0.level == 1 })
        // Catalog modifiers on Improved Reflexes restore effective REA to sheet total.
        XCTAssertEqual(c.effectiveAttributes.reaction, 5)
        XCTAssertTrue(c.augmentations.contains { $0.name == "Datajack" })
        XCTAssertEqual(c.contacts.first?.name, "Fixer Jax")
        XCTAssertEqual(c.lifestyles.first?.level, .low)
    }

    func testJSONAndXMLFormatDetection() throws {
        let json = try fixtureData("minimal_sr5.json")
        let xml = try fixtureData("minimal_sr5.chum5")
        XCTAssertEqual(CharacterImporter.detectFormat(fileExtension: "json", data: json), .chummerJSON)
        XCTAssertEqual(CharacterImporter.detectFormat(fileExtension: "chum5", data: xml), .chummerChum5)
        XCTAssertEqual(CharacterImporter.detectFormat(fileExtension: "", data: xml), .chummerChum5)
    }

    func testImportSavesToLibrary() async throws {
        let avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: avatarRoot) }

        let container = try await MainActor.run {
            try PersistenceController.makeContainer(inMemory: true)
        }
        let library = try await MainActor.run {
            try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)
        }

        let url = fixturesDirectory.appendingPathComponent("minimal_sr5.json")
        let result = try await library.importAndSave(from: url)
        let count = try await MainActor.run { try library.count() }
        XCTAssertEqual(count, 1)
        let loaded = try await MainActor.run { try library.require(result.character.id) }
        XCTAssertEqual(loaded.streetName, "Fixture")
        XCTAssertEqual(loaded.spells.count, 2)
    }

    func testBOMStrippingJSON() throws {
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(try fixtureData("minimal_sr5.json"))
        let result = try CharacterImporter.importChummerJSON(bom)
        XCTAssertEqual(result.character.name, "Test Runner")
    }

}
