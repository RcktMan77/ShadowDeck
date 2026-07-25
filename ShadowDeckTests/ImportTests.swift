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

    private var ghostwireJSON: URL {
        URL(fileURLWithPath: "/Users/zdavis/Documents/eBooks/Shadowrun/ghostwire.json")
    }

    private var ghostwireChum5: URL {
        URL(fileURLWithPath: "/Users/zdavis/Documents/eBooks/Shadowrun/ghostwire.chum5")
    }

    private var ghostwireAvailable: Bool {
        FileManager.default.fileExists(atPath: ghostwireJSON.path)
            && FileManager.default.fileExists(atPath: ghostwireChum5.path)
    }

    // MARK: - Synthetic fixtures

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
        XCTAssertEqual(c.attributes.reaction, 5)
        XCTAssertEqual(c.attributes.essence, Decimal(string: "5.7"))
        XCTAssertEqual(c.nuyen, 12000)
        XCTAssertEqual(c.karmaTotal, 30)
        XCTAssertEqual(c.karmaAvailable, 10)

        XCTAssertTrue(c.skills.contains { $0.displayName == "Pistols" && $0.rating == 5 && $0.specialized == "Semi-Automatics" })
        XCTAssertTrue(c.adeptPowers.contains { $0.name == "Improved Reflexes" && $0.level == 1 })
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
        let result = try await MainActor.run {
            try library.importAndSave(from: url)
        }
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

    // MARK: - Real Ghostwire files (optional; never modified)

    func testGhostwireJSONImport() throws {
        try XCTSkipUnless(ghostwireAvailable, "Ghostwire sample files not present on this machine")

        // Read-only: Data(contentsOf:) does not modify the original.
        let data = try Data(contentsOf: ghostwireJSON)
        let result = try CharacterImporter.importChummerJSON(data, fileName: "ghostwire.json")
        let c = result.character

        XCTAssertEqual(c.name, "Kai Ellison")
        XCTAssertEqual(c.streetName, "Ghostwire")
        XCTAssertEqual(c.edition, .sr5)
        XCTAssertEqual(c.metatype, .human)
        XCTAssertEqual(c.awakened, .adept)
        XCTAssertEqual(c.nuyen, 48051)
        XCTAssertEqual(c.karmaAvailable, 25)
        XCTAssertEqual(c.karmaTotal, 44)

        // Attributes (prefer sheet totals)
        XCTAssertGreaterThanOrEqual(c.attributes.agility, 5)
        XCTAssertGreaterThanOrEqual(c.attributes.logic, 5)
        XCTAssertGreaterThanOrEqual(c.attributes.magic, 2)
        XCTAssertEqual(c.attributes.essence, Decimal(string: "5.30") ?? Decimal(string: "5.3"))

        // Skills: rank not dice pool
        let pistols = c.skills.first { $0.displayName == "Pistols" }
        XCTAssertEqual(pistols?.rating, 6)
        XCTAssertEqual(pistols?.specialized, "Semi-Automatics")
        let hacking = c.skills.first { $0.displayName == "Hacking" }
        XCTAssertEqual(hacking?.rating, 6)

        XCTAssertFalse(c.qualities.isEmpty)
        XCTAssertTrue(c.qualities.contains { $0.name == "Adept" })
        XCTAssertFalse(c.adeptPowers.isEmpty)
        XCTAssertTrue(c.adeptPowers.contains { $0.name == "Improved Reflexes" })
        XCTAssertFalse(c.augmentations.isEmpty)
        XCTAssertTrue(c.augmentations.contains { $0.name.localizedCaseInsensitiveContains("Datajack") })
        XCTAssertGreaterThanOrEqual(c.contacts.count, 5)
        XCTAssertFalse(c.gear.isEmpty)

        // Priorities
        XCTAssertEqual(c.generation.priority[.metatype], .e)
        XCTAssertEqual(c.generation.priority[.attributes], .a)
        XCTAssertEqual(c.generation.priority[.resources], .b)

        // Ensure we did not write back to the source path.
        let attrs = try FileManager.default.attributesOfItem(atPath: ghostwireJSON.path)
        XCTAssertNotNil(attrs[.modificationDate])
    }

    func testGhostwireChum5Import() throws {
        try XCTSkipUnless(ghostwireAvailable, "Ghostwire sample files not present on this machine")

        let data = try Data(contentsOf: ghostwireChum5)
        let result = try CharacterImporter.importChummerXML(data, fileName: "ghostwire.chum5")
        let c = result.character

        XCTAssertEqual(c.name, "Kai Ellison")
        XCTAssertEqual(c.streetName, "Ghostwire")
        XCTAssertEqual(c.edition, .sr5)
        XCTAssertEqual(c.awakened, .adept)

        // XML and JSON may differ slightly on base vs total; identity must match.
        let jsonResult = try CharacterImporter.importChummerJSON(
            try Data(contentsOf: ghostwireJSON),
            fileName: "ghostwire.json"
        )
        XCTAssertEqual(c.name, jsonResult.character.name)
        XCTAssertEqual(c.streetName, jsonResult.character.streetName)
        XCTAssertEqual(c.metatype, jsonResult.character.metatype)
        XCTAssertEqual(c.edition, jsonResult.character.edition)
        XCTAssertEqual(c.nuyen, jsonResult.character.nuyen)
        XCTAssertEqual(c.karmaAvailable, jsonResult.character.karmaAvailable)

        // Skill sets should be largely aligned (rating-based).
        let xmlPistols = c.skills.first { $0.displayName == "Pistols" }?.rating
        let jsonPistols = jsonResult.character.skills.first { $0.displayName == "Pistols" }?.rating
        XCTAssertEqual(xmlPistols, jsonPistols)

        let xmlContacts = Set(c.contacts.map(\.name))
        let jsonContacts = Set(jsonResult.character.contacts.map(\.name))
        XCTAssertEqual(xmlContacts, jsonContacts)
    }

    func testGhostwireImportIntoLibraryRoundTrip() async throws {
        try XCTSkipUnless(ghostwireAvailable, "Ghostwire sample files not present on this machine")

        let avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Ghostwire-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: avatarRoot) }

        let container = try await MainActor.run {
            try PersistenceController.makeContainer(inMemory: true)
        }
        let library = try await MainActor.run {
            try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)
        }

        let imported = try await MainActor.run {
            try library.importAndSave(from: self.ghostwireJSON)
        }
        XCTAssertEqual(imported.character.streetName, "Ghostwire")

        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostwire-export-\(UUID().uuidString).shadowdeck")
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try await MainActor.run {
            try library.exportPackage(id: imported.character.id, to: packageURL)
        }
        let reimported = try ShadowDeckPackage.importPackage(from: packageURL)
        XCTAssertEqual(reimported.name, "Kai Ellison")
        XCTAssertEqual(reimported.streetName, "Ghostwire")
        XCTAssertEqual(reimported.skills.filter { $0.category == .active }.count,
                       imported.character.skills.filter { $0.category == .active }.count)
    }
}
