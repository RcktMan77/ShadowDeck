//
//  ManagementTests.swift
//  ShadowDeckTests
//
//  Phase 6 — detailed management mutations persist.
//

import XCTest
import SwiftData
@testable import ShadowDeck

@MainActor
final class ManagementTests: XCTestCase {
    private var avatarRoot: URL!
    private var library: CharacterLibrary!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Mgmt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        container = try PersistenceController.makeContainer(inMemory: true)
        library = try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: avatarRoot)
        library = nil
        container = nil
        avatarRoot = nil
        try super.tearDownWithError()
    }

    func testSkillRatingEditPersists() throws {
        var character = SampleCharacters.sr5CombatMage()
        character.skills = [
            SkillRating(catalogKey: "pistols", displayName: "Pistols", category: .active, rating: 4),
        ]
        try library.save(character)

        character.skills[0].rating = 6
        try library.save(character)

        let loaded = try library.require(character.id)
        XCTAssertEqual(loaded.skills.first?.rating, 6)
        XCTAssertEqual(loaded.skills.first?.displayName, "Pistols")
    }

    func testGearEquipAndContactAddPersist() throws {
        var character = SampleCharacters.sr5CombatMage()
        character.gear = [
            GearItem(
                catalogKey: "armor_jacket",
                name: "Armor Jacket",
                category: .armor,
                equipped: false,
                armorRating: 12
            ),
        ]
        character.contacts = []
        try library.save(character)

        character.gear[0].equipped = true
        character.contacts.append(Contact(name: "Fixer Fran", role: "Fixer", loyalty: 3, connection: 5))
        try library.save(character)

        let loaded = try library.require(character.id)
        XCTAssertTrue(loaded.gear.first?.equipped == true)
        XCTAssertEqual(loaded.contacts.count, 1)
        XCTAssertEqual(loaded.contacts.first?.name, "Fixer Fran")
        XCTAssertEqual(loaded.contacts.first?.connection, 5)
    }

    func testQualityAndAdeptPowerPersist() throws {
        var character = SampleCharacters.sr5CombatMage()
        character.qualities.append(
            QualityInstance(catalogKey: "codeslinger", name: "Codeslinger", kind: .positive, karmaValue: 10)
        )
        character.adeptPowers = [
            AdeptPowerInstance(
                catalogKey: "improved_reflexes",
                name: "Improved Reflexes",
                level: 2,
                powerPointCost: Decimal(string: "2.5") ?? 2
            ),
        ]
        try library.save(character)

        let loaded = try library.require(character.id)
        XCTAssertTrue(loaded.qualities.contains { $0.name == "Codeslinger" && $0.karmaValue == 10 })
        XCTAssertEqual(loaded.adeptPowers.first?.level, 2)
    }
}
