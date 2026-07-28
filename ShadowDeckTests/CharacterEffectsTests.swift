//
//  CharacterEffectsTests.swift
//  ShadowDeckTests
//
//  Phase 7 — dynamic attribute / armor / nuyen effects from gear & augs.
//

import XCTest
@testable import ShadowDeck

final class CharacterEffectsTests: XCTestCase {
    func testEquippedArmorUsesMaxRating() {
        var c = SampleCharacters.sr5CombatMage()
        c.gear = [
            GearItem(
                catalogKey: "armor_jacket",
                name: "Armor Jacket",
                category: .armor,
                equipped: true,
                armorRating: 12
            ),
            GearItem(
                catalogKey: "armor_clothing",
                name: "Armor Clothing",
                category: .armor,
                equipped: true,
                armorRating: 6
            ),
        ]
        let effects = CharacterEffectsEngine.resolve(c)
        XCTAssertEqual(effects.armorBonus, 12)
        let derived = RulesRegistry.rules(for: .sr5).deriveStats(for: c)
        XCTAssertEqual(derived.armor, 12)
    }

    func testUnequippedGearDoesNotApplyModifiers() {
        var c = SampleCharacters.sr5CombatMage()
        c.attributes.agility = 4
        c.gear = [
            GearItem(
                catalogKey: "boost_boots",
                name: "Boost Boots",
                category: .other,
                equipped: false,
                modifiers: [StatModifier(target: .agility, amount: 2)]
            ),
        ]
        XCTAssertEqual(c.effectiveAttributes.agility, 4)
        c.gear[0].equipped = true
        XCTAssertEqual(c.effectiveAttributes.agility, 6)
    }

    func testAugmentationAttributeBonusUsesRating() {
        var c = SampleCharacters.sr5CombatMage()
        c.attributes.strength = 3
        c.attributes.agility = 4
        c.augmentations = [
            Augmentation(
                catalogKey: "muscle_replacement",
                name: "Muscle Replacement",
                kind: .cyberware,
                rating: 2,
                essenceCost: 2,
                modifiers: [
                    StatModifier(target: .strength, amount: 1, usesRating: true),
                    StatModifier(target: .agility, amount: 1, usesRating: true),
                ]
            ),
        ]
        let eff = c.effectiveAttributes
        XCTAssertEqual(eff.strength, 5) // 3 + 2
        XCTAssertEqual(eff.agility, 6) // 4 + 2
        XCTAssertEqual(c.effects.attributeBonus(for: .strength), 2)
    }

    func testWiredReflexesAddsInitiativeDice() {
        var c = SampleCharacters.sr5CombatMage()
        c.attributes.reaction = 4
        c.attributes.intuition = 5
        c.augmentations = [
            Augmentation(
                catalogKey: "wired_reflexes",
                name: "Wired Reflexes",
                kind: .cyberware,
                rating: 2,
                essenceCost: 3,
                modifiers: [
                    StatModifier(target: .reaction, amount: 1, usesRating: true),
                    StatModifier(target: .initiativeDice, amount: 1, usesRating: true),
                ]
            ),
        ]
        let derived = RulesRegistry.rules(for: .sr5).deriveStats(for: c)
        // Base REA 4 +2 = 6; INT 5 → init base 11; dice 1+2 = 3
        XCTAssertEqual(derived.initiativeBase, 11)
        XCTAssertEqual(derived.initiativeDice, 3)
        XCTAssertEqual(c.effectiveAttributes.reaction, 6)
    }

    func testQualitySkillBonusAffectsDicePool() {
        var c = SampleCharacters.sr5CombatMage()
        c.attributes.agility = 5
        c.skills = [
            SkillRating(catalogKey: "pistols", displayName: "Pistols", category: .active, rating: 4),
        ]
        c.qualities = [
            QualityInstance(
                catalogKey: "sharpshooter",
                name: "Sharpshooter",
                kind: .positive,
                karmaValue: 4,
                modifiers: [StatModifier(target: .skill, amount: 2, skillKey: "Pistols")]
            ),
        ]
        let derived = RulesRegistry.rules(for: .sr5).deriveStats(for: c)
        // AGI 5 + skill 4 + quality 2 = 11
        XCTAssertEqual(derived.dicePools["pistols"], 11)
    }

    func testKnowledgeSkillsGetDicePools() {
        var c = SampleCharacters.sr5CombatMage()
        c.attributes.intuition = 5
        c.attributes.logic = 4
        c.skills = [
            SkillRating(
                catalogKey: "data_havens",
                displayName: "Data Havens",
                category: .knowledge,
                rating: 4,
                knowledgeType: "Street"
            ),
            SkillRating(
                catalogKey: "underworld",
                displayName: "Underworld",
                category: .knowledge,
                rating: 3,
                knowledgeType: "Street"
            ),
            SkillRating(
                catalogKey: "corporate_politics",
                displayName: "Corporate Politics",
                category: .knowledge,
                rating: 2,
                knowledgeType: "Professional"
            ),
        ]
        let derived = RulesRegistry.rules(for: .sr5).deriveStats(for: c)
        // Street knowledge → INT + rank
        XCTAssertEqual(derived.dicePools["data_havens"], 5 + 4)
        XCTAssertEqual(derived.dicePools["underworld"], 5 + 3)
        // Professional → LOG + rank
        XCTAssertEqual(derived.dicePools["corporate_politics"], 4 + 2)
    }

    func testChargeAndRefundNuyen() {
        var c = SampleCharacters.sr5CombatMage()
        c.nuyen = 10_000
        let charge = CharacterEffectsEngine.chargeNuyen(
            &c,
            unitCost: 1500,
            itemName: "Armor Jacket"
        )
        XCTAssertEqual(charge.charged, 1500)
        XCTAssertEqual(c.nuyen, 8500)

        let short = CharacterEffectsEngine.chargeNuyen(
            &c,
            unitCost: 100_000,
            itemName: "Luxury Yacht"
        )
        XCTAssertEqual(short.charged, 0)
        XCTAssertEqual(c.nuyen, 8500)
        XCTAssertTrue(short.message.contains("Not enough nuyen"))

        let refund = CharacterEffectsEngine.refundNuyen(
            &c,
            unitCost: 1500,
            itemName: "Armor Jacket"
        )
        XCTAssertEqual(c.nuyen, 10_000)
        XCTAssertTrue(refund.contains("Refunded"))
    }

    func testCustomModifiersOnGearAndAugs() {
        var c = SampleCharacters.sr5CombatMage()
        c.attributes.body = 3
        c.gear = [
            GearItem(
                catalogKey: "custom_plate",
                name: "Custom Plate",
                category: .armor,
                equipped: true,
                armorRating: 10,
                modifiers: [StatModifier(target: .armor, amount: 2)]
            ),
        ]
        c.augmentations = [
            Augmentation(
                catalogKey: "custom_bone",
                name: "Custom Bone Lace",
                kind: .cyberware,
                essenceCost: 0.5,
                modifiers: [StatModifier(target: .body, amount: 1)]
            ),
        ]
        let effects = c.effects
        XCTAssertEqual(effects.armorBonus, 12) // 10 + 2
        XCTAssertEqual(effects.effectiveAttributes.body, 4)
    }

    func testCatalogLookupMuscleReplacement() {
        let entry = CatalogLookup.entry(named: "Muscle Replacement")
        XCTAssertNotNil(entry, "Bundled catalog should include Muscle Replacement")
        let mods = CatalogLookup.modifiers(named: "Muscle Replacement")
        XCTAssertFalse(mods.isEmpty)
        XCTAssertTrue(mods.contains { $0.target == .agility && $0.usesRating })
        XCTAssertTrue(mods.contains { $0.target == .strength && $0.usesRating })
    }

    func testLegacyGearJSONDecodesWithoutNewFields() throws {
        // Pre–Phase 7 gear payload (no rating/modifiers/purchasedInApp).
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "catalogKey": "armor_jacket",
          "name": "Armor Jacket",
          "category": "armor",
          "quantity": 1,
          "nuyenCost": 1000,
          "availability": "2",
          "equipped": true,
          "notes": "",
          "armorRating": 12
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(GearItem.self, from: json)
        XCTAssertEqual(item.armorRating, 12)
        XCTAssertEqual(item.rating, 1)
        XCTAssertTrue(item.modifiers.isEmpty)
        XCTAssertFalse(item.purchasedInApp)
    }
}
