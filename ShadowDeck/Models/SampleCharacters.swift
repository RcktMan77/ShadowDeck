//
//  SampleCharacters.swift
//  ShadowDeck
//
//  Deterministic sample runners for tests and previews. One peer per edition.
//

import Foundation

public enum SampleCharacters {
    /// Fixed UUIDs keep snapshot tests stable.
    public static let sr4ID = UUID(uuidString: "AAAAAAAA-0004-4000-8000-000000000004")!
    public static let sr5ID = UUID(uuidString: "AAAAAAAA-0005-4000-8000-000000000005")!
    public static let sr6ID = UUID(uuidString: "AAAAAAAA-0006-4000-8000-000000000006")!

    public static func makeAll() -> [Character] {
        [sr4StreetSamurai(), sr5CombatMage(), sr6FaceHacker()]
    }

    /// ChargenArt role key for a sample (used when seeding library portraits).
    public static func portraitArchetype(for characterID: UUID) -> RunnerArchetype? {
        switch characterID {
        case sr4ID: return .streetSamurai
        case sr5ID: return .combatMage
        case sr6ID: return .face
        default: return nil
        }
    }

    // MARK: - SR4 (Build Points)

    public static func sr4StreetSamurai() -> Character {
        var attributes = AttributeRatings(
            body: 5, agility: 5, reaction: 5, strength: 4,
            willpower: 3, logic: 3, intuition: 4, charisma: 2,
            edge: 3, magic: 0, resonance: 0, essence: 6
        )
        // Wired reflexes essence loss applied via augmentation list.
        let wired = Augmentation(
            catalogKey: "wired_reflexes_1",
            name: "Wired Reflexes (1)",
            kind: .cyberware,
            grade: .standard,
            rating: 1,
            essenceCost: Decimal(string: "2.0") ?? 2,
            nuyenCost: 11_000
        )
        let dermal = Augmentation(
            catalogKey: "dermal_plating_1",
            name: "Dermal Plating (1)",
            kind: .cyberware,
            grade: .standard,
            rating: 1,
            essenceCost: Decimal(string: "0.5") ?? 0.5,
            nuyenCost: 5_000
        )
        attributes.essence = 6 // rules recompute from augs

        return Character(
            id: sr4ID,
            name: "Marcus Chen",
            streetName: "Iron",
            concept: "Street samurai",
            edition: .sr4,
            metatype: .human,
            awakened: .mundane,
            generation: GenerationProfile(
                system: .buildPoints,
                buildPointBudget: 400,
                buildPointsSpent: 380,
                karmaBudget: 0,
                nuyenBudget: 50_000,
                nuyenSpent: 35_000,
                isFinished: true
            ),
            houseRules: .coreBook,
            attributes: attributes,
            skills: [
                SkillRating(catalogKey: "blades", displayName: "Blades", category: .active, rating: 5, specialized: "Swords"),
                SkillRating(catalogKey: "pistols", displayName: "Pistols", category: .active, rating: 4),
                SkillRating(catalogKey: "dodge", displayName: "Dodge", category: .active, rating: 4),
                SkillRating(catalogKey: "perception", displayName: "Perception", category: .active, rating: 3),
                SkillRating(catalogKey: "infiltration", displayName: "Infiltration", category: .active, rating: 3),
                SkillRating(catalogKey: "shadow_lore", displayName: "Shadow Lore", category: .knowledge, rating: 3, knowledgeType: "Street"),
            ],
            qualities: [
                QualityInstance(catalogKey: "toughness", name: "Toughness", kind: .positive, karmaValue: 10),
                QualityInstance(catalogKey: "guts", name: "Guts", kind: .positive, karmaValue: 10),
                QualityInstance(catalogKey: "distinctive_style", name: "Distinctive Style", kind: .negative, karmaValue: 5),
            ],
            gear: [
                GearItem(catalogKey: "katana", name: "Katana", category: .weapon, nuyenCost: 1_000, equipped: true, damageCode: "(STR+3)P"),
                GearItem(catalogKey: "armor_jacket", name: "Armor Jacket", category: .armor, nuyenCost: 900, equipped: true, armorRating: 8),
                GearItem(catalogKey: "ares_predator", name: "Ares Predator", category: .weapon, nuyenCost: 350, equipped: true, damageCode: "5P"),
            ],
            augmentations: [wired, dermal],
            lifestyles: [Lifestyle(name: "Safehouse", level: .low, monthlyCost: 2_000, monthsPrepaid: 3)],
            contacts: [
                Contact(name: "Doc Wagon Tech", role: "Street Doc", loyalty: 3, connection: 2),
                Contact(name: "Fixer Jax", role: "Fixer", loyalty: 2, connection: 4),
            ],
            karmaTotal: 0,
            karmaAvailable: 0,
            nuyen: 12_450,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - SR5 (Priority)

    public static func sr5CombatMage() -> Character {
        return Character(
            id: sr5ID,
            name: "Elena Voss",
            streetName: "Hex",
            concept: "Combat mage",
            edition: .sr5,
            metatype: .elf,
            awakened: .fullMagician,
            generation: GenerationProfile(
                system: .priority,
                priority: PriorityAssignment(values: [
                    .magicOrResonance: .a,
                    .attributes: .b,
                    .skills: .c,
                    .metatype: .d,
                    .resources: .e,
                ]),
                karmaBudget: 25,
                karmaSpent: 20,
                nuyenBudget: 6_000,
                nuyenSpent: 5_200,
                attributePoints: 20,
                specialAttributePoints: 2,
                skillPoints: 28,
                skillGroupPoints: 2,
                isFinished: true
            ),
            houseRules: .coreBook,
            attributes: AttributeRatings(
                body: 3, agility: 5, reaction: 4, strength: 2,
                willpower: 5, logic: 5, intuition: 4, charisma: 5,
                edge: 2, magic: 6, resonance: 0, essence: 6
            ),
            skills: [
                SkillRating(catalogKey: "spellcasting", displayName: "Spellcasting", category: .active, rating: 6, group: .sorcery),
                SkillRating(catalogKey: "counterspelling", displayName: "Counterspelling", category: .active, rating: 5, group: .sorcery),
                SkillRating(catalogKey: "summoning", displayName: "Summoning", category: .active, rating: 4, group: .conjuring),
                SkillRating(catalogKey: "assensing", displayName: "Assensing", category: .active, rating: 4),
                SkillRating(catalogKey: "perception", displayName: "Perception", category: .active, rating: 3),
                SkillRating(catalogKey: "arcana", displayName: "Arcana", category: .knowledge, rating: 4, knowledgeType: "Academic"),
            ],
            skillGroups: [
                SkillGroupRating(group: .sorcery, rating: 0), // individual skills rated above
            ],
            qualities: [
                QualityInstance(catalogKey: "focused_concentration_1", name: "Focused Concentration I", kind: .positive, karmaValue: 4),
                QualityInstance(catalogKey: "mentor_spirit", name: "Mentor Spirit", kind: .positive, karmaValue: 5),
                QualityInstance(catalogKey: "sinner", name: "SINner (National)", kind: .negative, karmaValue: 5),
            ],
            gear: [
                GearItem(catalogKey: "mage_armor", name: "Actioneer Business Clothes", category: .armor, nuyenCost: 1_500, equipped: true, armorRating: 8),
                GearItem(catalogKey: "mage_staff", name: "Weapon Focus (Staff)", category: .weapon, nuyenCost: 2_000, equipped: true),
            ],
            spells: [
                SpellInstance(catalogKey: "manabolt", name: "Manabolt", category: "Combat"),
                SpellInstance(catalogKey: "armor", name: "Armor", category: "Health"),
                SpellInstance(catalogKey: "heal", name: "Heal", category: "Health"),
                SpellInstance(catalogKey: "improved_invisibility", name: "Improved Invisibility", category: "Illusion"),
                SpellInstance(catalogKey: "stunball", name: "Stunball", category: "Combat"),
            ],
            lifestyles: [Lifestyle(level: .middle, monthlyCost: 5_000, monthsPrepaid: 1)],
            contacts: [
                Contact(name: "Talismonger Wren", role: "Talismonger", loyalty: 3, connection: 3),
            ],
            karmaTotal: 5,
            karmaAvailable: 5,
            nuyen: 800,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    // MARK: - SR6 (Priority + popular house rules demo)

    public static func sr6FaceHacker() -> Character {
        // Sum-to-Ten: A=4, B=3, B=3, C=2, E=0 → 12 is wrong; use A+B+C+D+E unique = 10,
        // or sum-to-ten with duplicates: A(4)+B(3)+C(2)+D(1)+E(0)=10.
        let priority = PriorityAssignment(values: [
            .skills: .a,          // 4
            .attributes: .b,      // 3
            .metatype: .c,        // 2
            .resources: .d,       // 1
            .magicOrResonance: .e // 0
        ])

        var house = HouseRules.popularTable
        house.enable(.sumToTen)

        return Character(
            id: sr6ID,
            name: "Jordan Okonkwo",
            streetName: "Signal",
            concept: "Face / hacker",
            edition: .sr6,
            metatype: .human,
            awakened: .mundane,
            generation: GenerationProfile(
                system: .sumToTen,
                priority: priority,
                karmaBudget: 50 + house.bonusKarma,
                karmaSpent: 30,
                nuyenBudget: 50_000,
                nuyenSpent: 42_000,
                attributePoints: 16,
                specialAttributePoints: 9,
                skillPoints: 32,
                isFinished: true
            ),
            houseRules: house,
            attributes: AttributeRatings(
                body: 3, agility: 4, reaction: 5, strength: 2,
                willpower: 4, logic: 5, intuition: 5, charisma: 6,
                edge: 5, magic: 0, resonance: 0, essence: 6
            ),
            skills: [
                SkillRating(catalogKey: "influence", displayName: "Influence", category: .active, rating: 6),
                SkillRating(catalogKey: "electronics", displayName: "Electronics", category: .active, rating: 5),
                SkillRating(catalogKey: "cracking", displayName: "Cracking", category: .active, rating: 5),
                SkillRating(catalogKey: "stealth", displayName: "Stealth", category: .active, rating: 3),
                SkillRating(catalogKey: "perception", displayName: "Perception", category: .active, rating: 4),
                SkillRating(catalogKey: "corp_tacs", displayName: "Corporate Tactics", category: .knowledge, rating: 3),
            ],
            qualities: [
                QualityInstance(catalogKey: "first_impression", name: "First Impression", kind: .positive, karmaValue: 12),
                QualityInstance(catalogKey: "analytical_mind", name: "Analytical Mind", kind: .positive, karmaValue: 3),
                QualityInstance(catalogKey: "social_stress", name: "Social Stress", kind: .negative, karmaValue: 8),
            ],
            gear: [
                GearItem(catalogKey: "cyberdeck", name: "Spinrad Falcon", category: .cyberdeck, nuyenCost: 28_000, equipped: true),
                GearItem(catalogKey: "armor_clothing", name: "Armor Clothing", category: .armor, nuyenCost: 450, equipped: true, armorRating: 4),
                GearItem(catalogKey: " commlink", name: "Transys Avalon", category: .electronics, nuyenCost: 5_000, equipped: true),
            ],
            augmentations: [
                Augmentation(
                    catalogKey: "datajack",
                    name: "Datajack",
                    kind: .cyberware,
                    essenceCost: Decimal(string: "0.1") ?? 0.1,
                    nuyenCost: 1_000
                ),
                Augmentation(
                    catalogKey: "cerebral_booster_1",
                    name: "Cerebral Booster 1",
                    kind: .bioware,
                    rating: 1,
                    essenceCost: Decimal(string: "0.2") ?? 0.2,
                    nuyenCost: 31_500
                ),
            ],
            lifestyles: [Lifestyle(level: .middle, monthlyCost: 5_000, monthsPrepaid: 2)],
            contacts: [
                Contact(name: "Mr. Johnson (Ares)", role: "Johnson", loyalty: 2, connection: 5),
                Contact(name: "Glitch", role: "Decker", loyalty: 4, connection: 4),
                Contact(name: "Rosa", role: "Bartender", loyalty: 3, connection: 2),
            ],
            karmaTotal: 45,
            karmaAvailable: 20,
            nuyen: 3_200,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
    }
}
