//
//  CharacterModelTests.swift
//  ShadowDeckTests
//

import XCTest
@testable import ShadowDeck

final class CharacterModelTests: XCTestCase {

    func testSampleCharactersExistForEachEdition() {
        let samples = SampleCharacters.makeAll()
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(Set(samples.map(\.edition)), Set(Edition.allCases))
    }

    func testSR4SampleInvariants() {
        let character = SampleCharacters.sr4StreetSamurai()
        let rules = RulesRegistry.rules(for: .sr4)

        XCTAssertEqual(character.edition, .sr4)
        XCTAssertEqual(character.generation.system, .buildPoints)
        XCTAssertEqual(character.metatype, .human)
        XCTAssertEqual(character.awakened, .mundane)

        let derived = rules.deriveStats(for: character)
        XCTAssertNil(derived.physicalLimit, "SR4 should not use SR5-style limits")
        XCTAssertEqual(derived.condition.physicalBoxes, DerivedStatsCalculator.physicalBoxes(body: character.attributes.body))
        XCTAssertEqual(derived.condition.stunBoxes, DerivedStatsCalculator.stunBoxes(willpower: character.attributes.willpower))

        // 2.0 + 0.5 essence from augs
        XCTAssertEqual(derived.currentEssence, Decimal(string: "3.5"))

        let validation = rules.validate(character)
        XCTAssertTrue(validation.isValid, "SR4 sample errors: \(validation.errors.map(\.message))")
        XCTAssertFalse(character.skills.isEmpty)
        XCTAssertFalse(character.augmentations.isEmpty)
        XCTAssertTrue(character.gear.contains(where: \.equipped))
    }

    func testSR5SampleInvariants() {
        let character = SampleCharacters.sr5CombatMage()
        let rules = RulesRegistry.rules(for: .sr5)

        XCTAssertEqual(character.edition, .sr5)
        XCTAssertEqual(character.generation.system, .priority)
        XCTAssertEqual(character.awakened, .fullMagician)
        XCTAssertGreaterThanOrEqual(character.attributes.magic, 1)
        XCTAssertTrue(character.generation.priority.usesUniqueLetters)
        XCTAssertEqual(character.generation.priority.sumToTenTotal, 10)

        let derived = rules.deriveStats(for: character)
        XCTAssertNotNil(derived.physicalLimit)
        XCTAssertNotNil(derived.mentalLimit)
        XCTAssertNotNil(derived.socialLimit)
        XCTAssertEqual(derived.magicOrResonanceEffective, character.attributes.magic)
        XCTAssertEqual(derived.currentEssence, 6)

        let validation = rules.validate(character)
        XCTAssertTrue(validation.isValid, "SR5 sample errors: \(validation.errors.map(\.message))")
        XCTAssertFalse(character.spells.isEmpty)
    }

    func testSR6SampleInvariants() {
        let character = SampleCharacters.sr6FaceHacker()
        let rules = RulesRegistry.rules(for: .sr6)

        XCTAssertEqual(character.edition, .sr6)
        XCTAssertEqual(character.generation.system, .sumToTen)
        XCTAssertTrue(character.houseRules.isEnabled(.sumToTen))
        XCTAssertEqual(character.generation.priority.sumToTenTotal, 10)
        XCTAssertGreaterThanOrEqual(character.attributes.edge, 2)

        let derived = rules.deriveStats(for: character)
        XCTAssertNil(derived.physicalLimit, "SR6 should not use classic limits")
        XCTAssertNil(derived.mentalLimit)
        XCTAssertNil(derived.socialLimit)
        XCTAssertLessThan(derived.currentEssence, 6)

        let validation = rules.validate(character)
        XCTAssertTrue(validation.isValid, "SR6 sample errors: \(validation.errors.map(\.message))")
        XCTAssertGreaterThanOrEqual(character.contacts.count, 2)
    }

    func testAttributeBoundsEnforcedPerMetatype() {
        let rules = SR5Rules()
        var character = SampleCharacters.sr5CombatMage()
        // Elf agility max 7 — force illegal 9
        character.attributes.agility = 9
        let result = rules.validate(character)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.code == "attribute.bounds" })
    }

    func testExceptionalAttributeHouseRuleRelaxesMax() {
        let rules = SR5Rules()
        var character = SampleCharacters.sr5CombatMage()
        character.houseRules.enable(.exceptionalAttributeAtChargen)
        // Elf agility natural max 7; with house rule allow 8
        character.attributes.agility = 8
        let result = rules.validate(character)
        XCTAssertFalse(result.errors.contains { $0.code == "attribute.bounds" && $0.field == "agility" })
    }

    func testPositiveQualityCap() {
        let rules = SR5Rules()
        var character = SampleCharacters.sr5CombatMage()
        character.qualities.append(
            QualityInstance(catalogKey: "too_much", name: "Too Much", kind: .positive, karmaValue: 50)
        )
        let result = rules.validate(character)
        XCTAssertTrue(result.errors.contains { $0.code == "qualities.positive_cap" })
    }

    func testDisplayTitle() {
        var c = SampleCharacters.sr4StreetSamurai()
        XCTAssertTrue(c.displayTitle.contains("Iron"))
        c.streetName = ""
        XCTAssertEqual(c.displayTitle, c.name)
    }

    func testMetatypeCatalogCoversAllEditions() {
        for edition in Edition.allCases {
            let profiles = MetatypeCatalog.allProfiles(for: edition)
            XCTAssertEqual(profiles.count, MetatypeID.allCases.count)
            for profile in profiles {
                XCTAssertEqual(profile.edition, edition)
                let body = profile.bounds(for: .body)
                XCTAssertLessThanOrEqual(body.minimum, body.maximum)
            }
        }
    }
}
