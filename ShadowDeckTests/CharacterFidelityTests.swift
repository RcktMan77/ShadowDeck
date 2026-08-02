//
//  CharacterFidelityTests.swift
//  ShadowDeckTests
//
//  Full-domain round-trip coverage for library save, .shadowdeck package, and
//  best-effort Chummer regenerate. Ensures features added after initial I/O
//  still survive import/export/save.
//

import XCTest
import SwiftData
@testable import ShadowDeck

@MainActor
final class CharacterFidelityTests: XCTestCase {
    // MARK: - Fixtures

    /// Character packed with post-v1 domain state that must survive `.shadowdeck` / library JSON.
    private func maximalCharacter() -> Character {
        let runID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let ledgerDate = Date(timeIntervalSince1970: 1_700_000_000) // second precision for ISO-8601
        let contactDate = Date(timeIntervalSince1970: 1_700_100_000)

        var c = SampleCharacters.sr5CombatMage()
        c.background = "Born in the Barrens. Long form backstory for fidelity."
        c.notes = "Table notes — session 12."
        c.karmaTotal = 40
        c.karmaAvailable = 12
        c.nuyen = 15_000
        c.lifestyleNuyenReserve = 2_500
        c.lifestyleLastProcessedAt = ledgerDate
        c.houseRules = HouseRules.popularTable // includes dice
        c.conditionTrack = ConditionTrack(physicalDamage: 3, stunDamage: 1)

        c.lifestyles = [
            Lifestyle(
                name: "Bolt-hole",
                level: .low,
                monthlyCost: 2_000,
                monthsPrepaid: 2,
                notes: "Near Snohomish",
                isActive: true,
                nextDueDate: ledgerDate
            )
        ]
        c.lifestyleLedger = [
            LifestyleLedgerEntry(
                date: ledgerDate,
                kind: .processMonth,
                amount: -2_000,
                note: "Processed 1 month"
            )
        ]

        c.advancementPlan = [
            AdvancementPlanItem(
                kind: .skillRaise,
                targetKey: "pistols",
                displayName: "Pistols",
                fromRating: 4,
                toRating: 5,
                karmaCost: 10,
                skillCategory: .active
            )
        ]
        c.advancementLedger = [
            AdvancementLedgerEntry(
                date: ledgerDate,
                kind: .skillRaise,
                summary: "Pistols 3 → 4 (8 karma)",
                karmaSpent: 8,
                targetKey: "pistols"
            ),
            AdvancementLedgerEntry(
                date: ledgerDate,
                kind: .runAward,
                summary: "Critic’s Choice — ¥1,000 + 2 karma",
                karmaSpent: -2,
                nuyenDelta: 1_000,
                relatedRunID: runID
            )
        ]

        c.contacts = [
            Contact(
                name: "Fixer Fox",
                role: "Fixer",
                loyalty: 3,
                connection: 5,
                notes: "Prefers certified cred.",
                contactType: "Fixer",
                metatype: "Elf",
                gender: "Female",
                age: "34",
                location: "Downtown",
                preferredPayment: "Nuyen",
                hobbiesVice: "Jazz",
                personalLife: "Quiet",
                tags: ["Johnson", "Ares"],
                favorState: .owesMe,
                favorOneTime: true,
                lastContactAt: contactDate,
                interactionLog: [
                    ContactInteraction(
                        date: contactDate,
                        summary: "Set up a datasteal",
                        favorDirection: .owesMe,
                        relatedRunID: runID,
                        createdAt: contactDate
                    )
                ]
            )
        ]

        // Ensure at least one specialized skill for Chummer path.
        if let idx = c.skills.firstIndex(where: { $0.catalogKey == "pistols" || $0.displayName.localizedCaseInsensitiveContains("pistol") }) {
            c.skills[idx].specialized = "Semi-Automatics"
            c.skills[idx].rating = max(1, c.skills[idx].rating)
        } else {
            c.skills.append(
                SkillRating(
                    catalogKey: "pistols",
                    displayName: "Pistols",
                    category: .active,
                    rating: 5,
                    specialized: "Semi-Automatics"
                )
            )
        }

        c.skillGroups = [
            SkillGroupRating(group: .fireArarms, rating: 2)
        ]

        c.importProvenance = ImportProvenance(
            sourceFormat: "shadowdeck-test",
            originalFileName: "maximal_test.shadowdeck",
            importedAt: ledgerDate,
            originalPayload: Data("not-chummer-xml".utf8)
        )

        return c
    }

    /// Compare domain state ignoring timestamps that library save rewrites.
    private func assertDomainEqual(
        _ a: Character,
        _ b: Character,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(a.id, b.id, file: file, line: line)
        XCTAssertEqual(a.schemaVersion, b.schemaVersion, file: file, line: line)
        XCTAssertEqual(a.name, b.name, file: file, line: line)
        XCTAssertEqual(a.streetName, b.streetName, file: file, line: line)
        XCTAssertEqual(a.concept, b.concept, file: file, line: line)
        XCTAssertEqual(a.background, b.background, file: file, line: line)
        XCTAssertEqual(a.notes, b.notes, file: file, line: line)
        XCTAssertEqual(a.edition, b.edition, file: file, line: line)
        XCTAssertEqual(a.metatype, b.metatype, file: file, line: line)
        XCTAssertEqual(a.awakened, b.awakened, file: file, line: line)
        XCTAssertEqual(a.generation, b.generation, file: file, line: line)
        XCTAssertEqual(a.houseRules, b.houseRules, file: file, line: line)
        XCTAssertEqual(a.attributes, b.attributes, file: file, line: line)
        XCTAssertEqual(a.skills, b.skills, file: file, line: line)
        XCTAssertEqual(a.skillGroups, b.skillGroups, file: file, line: line)
        XCTAssertEqual(a.qualities, b.qualities, file: file, line: line)
        XCTAssertEqual(a.gear, b.gear, file: file, line: line)
        XCTAssertEqual(a.augmentations, b.augmentations, file: file, line: line)
        XCTAssertEqual(a.spells, b.spells, file: file, line: line)
        XCTAssertEqual(a.adeptPowers, b.adeptPowers, file: file, line: line)
        XCTAssertEqual(a.complexForms, b.complexForms, file: file, line: line)
        XCTAssertEqual(a.lifestyles, b.lifestyles, file: file, line: line)
        XCTAssertEqual(a.contacts, b.contacts, file: file, line: line)
        XCTAssertEqual(a.karmaTotal, b.karmaTotal, file: file, line: line)
        XCTAssertEqual(a.karmaAvailable, b.karmaAvailable, file: file, line: line)
        XCTAssertEqual(a.nuyen, b.nuyen, file: file, line: line)
        XCTAssertEqual(a.lifestyleNuyenReserve, b.lifestyleNuyenReserve, file: file, line: line)
        XCTAssertEqual(a.lifestyleLastProcessedAt, b.lifestyleLastProcessedAt, file: file, line: line)
        XCTAssertEqual(a.lifestyleLedger, b.lifestyleLedger, file: file, line: line)
        XCTAssertEqual(a.advancementLedger, b.advancementLedger, file: file, line: line)
        XCTAssertEqual(a.advancementPlan, b.advancementPlan, file: file, line: line)
        XCTAssertEqual(a.conditionTrack, b.conditionTrack, file: file, line: line)
        XCTAssertEqual(a.importProvenance, b.importProvenance, file: file, line: line)
        // Avatar metadata (bytes compared separately when needed)
        XCTAssertEqual(a.avatar.mimeType, b.avatar.mimeType, file: file, line: line)
        XCTAssertEqual(a.avatar.isAnimated, b.avatar.isAnimated, file: file, line: line)
    }

    // MARK: - Portable JSON / package

    func testPortableCodingRoundTripsMaximalCharacter() throws {
        let original = maximalCharacter()
        let data = try PortableCharacterCoding.encodeCharacter(original)
        let decoded = try PortableCharacterCoding.decode(from: data).character
        assertDomainEqual(original, decoded)
        XCTAssertEqual(decoded.houseRules.dice, HouseRules.popularTable.dice)
        XCTAssertEqual(decoded.advancementLedgerEntries.count, 2)
        XCTAssertEqual(decoded.advancementLedgerEntries.first { $0.kind == .runAward }?.nuyenDelta, 1_000)
        XCTAssertEqual(decoded.contacts.first?.tags, ["Johnson", "Ares"])
        XCTAssertEqual(decoded.contacts.first?.interactionLog.count, 1)
    }

    func testShadowDeckPackageRoundTripsMaximalCharacter() throws {
        let original = maximalCharacter()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Fidelity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let packageURL = dir.appendingPathComponent("runner.shadowdeck", isDirectory: true)
        try ShadowDeckPackage.export(character: original, avatarData: nil, to: packageURL)
        let imported = try ShadowDeckPackage.importPackage(from: packageURL)

        assertDomainEqual(original, imported)
    }

    func testLibrarySaveRoundTripsMaximalCharacter() throws {
        let avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Lib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: avatarRoot) }

        let container = try PersistenceController.makeContainer(inMemory: true)
        let library = try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)

        let original = maximalCharacter()
        try library.save(original)
        let loaded = try library.require(original.id)

        // Library save touches modifiedAt — compare domain without timestamps.
        assertDomainEqual(original, loaded)
    }

    func testLibraryExportImportPackagePreservesDomain() throws {
        let avatarRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Pkg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: avatarRoot) }

        let container = try PersistenceController.makeContainer(inMemory: true)
        let library = try PersistenceController.makeLibrary(container: container, avatarRoot: avatarRoot)

        let original = maximalCharacter()
        try library.save(original)

        let packageURL = avatarRoot.appendingPathComponent("export.shadowdeck", isDirectory: true)
        try library.exportPackage(id: original.id, to: packageURL)

        // Import into a fresh library (simulates transfer to another machine).
        let avatarRoot2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowDeck-Pkg2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: avatarRoot2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: avatarRoot2) }
        let container2 = try PersistenceController.makeContainer(inMemory: true)
        let library2 = try PersistenceController.makeLibrary(container: container2, avatarRoot: avatarRoot2)
        let reimported = try library2.importPackage(from: packageURL)

        assertDomainEqual(original, reimported)
    }

    // MARK: - Chummer best-effort regenerate

    func testChummerRegeneratePreservesCoreAndExtendedImportFields() throws {
        let original = maximalCharacter()
        // Clear provenance so export regenerates (not original payload).
        var forExport = original
        forExport.importProvenance = nil

        let result = try ChummerXMLExporter.export(forExport, mode: .regeneratedOnly)
        XCTAssertFalse(result.usedOriginalPayload)

        let imported = try CharacterImporter.importChummerXML(
            result.xmlData,
            fileName: "regen.chum5"
        ).character

        XCTAssertEqual(imported.name, original.name)
        XCTAssertEqual(imported.streetName, original.streetName)
        XCTAssertEqual(imported.nuyen, original.nuyen)
        XCTAssertEqual(imported.karmaAvailable, original.karmaAvailable)
        XCTAssertEqual(imported.karmaTotal, original.karmaTotal)
        XCTAssertEqual(imported.attributes.body, original.attributes.body)

        // Specialization survives nested <specs><spec><name>
        let pistols = imported.skills.first {
            $0.displayName.localizedCaseInsensitiveContains("pistol")
        }
        XCTAssertEqual(pistols?.specialized, "Semi-Automatics")

        // Condition track
        XCTAssertEqual(imported.conditionTrack?.physicalDamage, 3)
        XCTAssertEqual(imported.conditionTrack?.stunDamage, 1)

        // Lifestyle months prepaid
        XCTAssertEqual(imported.lifestyles.first?.monthsPrepaid, 2)

        // Contact enrichment Chummer can hold
        let contact = imported.contacts.first { $0.name == "Fixer Fox" }
        XCTAssertNotNil(contact)
        XCTAssertEqual(contact?.notes, "Prefers certified cred.")
        XCTAssertEqual(contact?.location, "Downtown")
        XCTAssertEqual(contact?.preferredPayment, "Nuyen")

        // Skill groups
        XCTAssertFalse(imported.skillGroups.isEmpty)

        // ShadowDeck-only campaign state is intentionally not in Chummer:
        XCTAssertTrue(imported.advancementLedgerEntries.isEmpty)
        XCTAssertNil(imported.houseRules.dice)
        XCTAssertTrue(imported.contacts.first?.tags.isEmpty != false)
    }

    func testChummerXMLParsesNestedSpecName() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <character>
          <name>Spec Nested</name>
          <alias>Nest</alias>
          <metatype>Human</metatype>
          <gameedition>SR5</gameedition>
          <buildmethod>Priority</buildmethod>
          <nuyen>0</nuyen>
          <karma>0</karma>
          <totalkarma>0</totalkarma>
          <adept>False</adept>
          <magician>False</magician>
          <technomancer>False</technomancer>
          <attributes>
            <attribute><name>BOD</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>AGI</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>REA</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>STR</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>CHA</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>INT</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>LOG</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>WIL</name><base>3</base><totalvalue>3</totalvalue></attribute>
            <attribute><name>EDG</name><base>2</base><totalvalue>2</totalvalue></attribute>
          </attributes>
          <newskills>
            <skills>
              <skill>
                <name>Pistols</name>
                <base>4</base>
                <karma>0</karma>
                <specs>
                  <spec>
                    <name>Semi-Automatics</name>
                  </spec>
                </specs>
              </skill>
            </skills>
            <knoskills/>
          </newskills>
        </character>
        """
        let data = Data(xml.utf8)
        let imported = try CharacterImporter.importChummerXML(data, fileName: "nested_spec.chum5").character
        let pistols = imported.skills.first { $0.displayName == "Pistols" }
        XCTAssertEqual(pistols?.specialized, "Semi-Automatics")
        XCTAssertEqual(pistols?.rating, 4)
    }
}
