//
//  ChargenHelpCatalog.swift
//  ShadowDeck
//
//  Player-facing explanations grounded in core Shadowrun attribute/skill concepts.
//  Wording is paraphrased for clarity and multi-edition use (not a verbatim reprint of
//  any single printing). Tone matches official rulebook teaching style.
//

import Foundation

public enum ChargenHelpCatalog {
    // MARK: - Attributes

    public static func attributeTitle(_ id: AttributeID) -> String {
        id.displayName
    }

    public static func attributeDescription(_ id: AttributeID) -> String {
        switch id {
        case .body:
            "Body measures your physical toughness and endurance. It determines how much damage you can soak, how large your Physical Condition Monitor is, and how well you resist toxins, pathogens, and fatigue."
        case .agility:
            "Agility is your coordination, balance, and fine motor control. It drives most combat skills (firearms, blades, stealth movement) and anything requiring precise physical action."
        case .reaction:
            "Reaction is your reflexes and response time. It feeds Initiative, driving, piloting, and dodging. High Reaction keeps you acting before the opposition."
        case .strength:
            "Strength is raw muscle power. It affects melee damage, lifting/carrying, climbing, and tests of brute force."
        case .willpower:
            "Willpower is mental fortitude. It resists magic, interrogation, and fear; feeds Stun Condition Monitor size; and supports spellcasting Drain and social composure."
        case .logic:
            "Logic is analytical intellect. It powers Matrix skills (hacking, electronics), technical knowledge, and many problem-solving tests."
        case .intuition:
            "Intuition is gut instinct and perception. It drives Initiative (with Reaction), noticing ambushes, assensing vibes, and street smarts."
        case .charisma:
            "Charisma is force of personality. It drives Influence skills, leadership, negotiations, and how well spirits or people respond to you."
        case .edge:
            "Edge is luck, grit, and narrative favor. Spending Edge can re-roll dice, seize initiative, or shrug off catastrophe. Humans often start with higher natural Edge maxima."
        case .magic:
            "Magic measures awakened power. Magicians, adepts, and mystic adepts use it for spellcasting, powers, and astral ability. Essence loss from cyberware can reduce Magic."
        case .resonance:
            "Resonance is a technomancer’s living connection to the Matrix. It powers complex forms, sprites, and living persona attributes in place of a cyberdeck."
        case .essence:
            "Essence is the integrity of your living spirit. Cyberware and some bioware reduce Essence. At 0 Essence a character dies; Magic/Resonance are often capped by current Essence."
        case .initiative:
            "Initiative determines turn order in combat. It is usually derived from Reaction + Intuition (plus initiative dice), not purchased as a primary attribute."
        }
    }

    public static func attributeInfluences(_ id: AttributeID) -> String {
        switch id {
        case .body: "Condition monitors, damage resistance, toxin resistance"
        case .agility: "Firearms, stealth, athletics, many combat tests"
        case .reaction: "Initiative, vehicles, defense, reaction-based skills"
        case .strength: "Melee damage, lift/carry, feats of strength"
        case .willpower: "Drain, stun track, composure, magical resistance"
        case .logic: "Matrix, technical skills, knowledge, memory"
        case .intuition: "Initiative, perception, surprise, street instincts"
        case .charisma: "Social tests, contacts, conjuring rapport"
        case .edge: "Edge actions, luck spends, special human advantage"
        case .magic: "Spells, adept powers, astral projection limits"
        case .resonance: "Complex forms, sprites, living persona"
        case .essence: "Caps Magic/Resonance; tracks augmentation load"
        case .initiative: "Combat turn order"
        }
    }

    // MARK: - Metatype

    public static func metatypeBlurb(_ id: MetatypeID) -> String {
        switch id {
        case .human:
            "Humans are the most numerous metatype and the baseline for many rules. They typically enjoy a higher natural maximum Edge, reflecting adaptability and luck under fire."
        case .elf:
            "Elves are lithe and charismatic, with natural advantages in Agility and Charisma. They often excel as faces, infiltrators, and precision combatants."
        case .dwarf:
            "Dwarfs are stocky, resilient, and strong-willed. Higher Body, Strength, and Willpower trade against slightly lower Reaction ceilings in core tables."
        case .ork:
            "Orks are powerful and tough, with strong Body and Strength. They face social prejudice in many settings but dominate physical confrontations."
        case .troll:
            "Trolls are massive, with the highest Body and Strength ranges. Reach, armor-like dermal deposits (in lore), and intimidation come at the cost of lower mental/social maxima."
        }
    }

    // MARK: - Priority columns

    public static func priorityColumnDescription(_ column: PriorityColumn) -> String {
        switch column {
        case .metatype:
            "Metatype priority determines which metatypes you may choose and how many special/adjustment points you receive to raise Edge, Magic, or Resonance (depending on edition and path)."
        case .attributes:
            "Attribute priority grants a pool of points to raise your eight standard attributes (Body through Charisma) above your metatype minimums, up to natural maximums."
        case .magicOrResonance:
            "Magic/Resonance priority sets whether you are mundane or awakened/emerged, and how strong your starting Magic or Resonance can be (full magician, adept, technomancer, etc.)."
        case .skills:
            "Skills priority grants skill points (and often skill group points) to train active, knowledge, and language skills that define what your runner actually does on a job."
        case .resources:
            "Resources priority is your starting nuyen budget for gear, cyberware, vehicles, lifestyles, and false identities. High Resources buys chrome and tools; low Resources means hustling."
        }
    }

    public static var specialAdjustmentPointsHelp: String {
        "Special (or adjustment) points from Metatype priority are spent on Edge, Magic, or Resonance—not on the eight standard attributes. Mundane characters typically pour these into Edge."
    }

    public static var attributePointsHelp: String {
        "Attribute points raise Body, Agility, Reaction, Strength, Willpower, Logic, Intuition, and Charisma from metatype minimum toward metatype maximum during character generation."
    }

    public static var skillPointsHelp: String {
        "Skill points buy ranks in individual skills. Higher ranks cost more of the pool (one point per rank at chargen in this wizard’s simplified model). Skill groups train a bundle of related skills at once when available."
    }

    public static var magicResonancePriorityHelp: String {
        "This column decides magical or Resonance capability. Higher letters unlock full Magicians, Mystic Adepts, or strong Technomancers; lower letters may limit you to Adepts, Aspected Magicians, or mundane life."
    }

    public static var resourcesHelp: String {
        "Nuyen from Resources buys almost everything that isn’t paid with Karma: weapons, armor, cyberdecks, vehicles, bioware/cyberware, and lifestyle prepay."
    }

    // MARK: - Awakened paths

    public static func pathTitle(_ path: AwakenedPath) -> String {
        path.displayName
    }

    public static func pathDescription(_ path: AwakenedPath) -> String {
        switch path {
        case .mundane:
            "Mundane means you have no Magic or Resonance attribute—you are neither a spellcaster nor a technomancer. Most runners are mundane. You still use Edge, skills, gear, and cyberware; you simply do not access the astral plane or Resonance."
        case .fullMagician:
            "A Magician channels mana to cast spells, summon spirits, and project astrally. You need a Magic attribute and typically a tradition. Magicians often prioritize Magic/Resonance and Skills (Sorcery/Conjuring) over heavy cyberware, since Essence loss hurts Magic."
        case .aspectedMagician:
            "An Aspected Magician is limited to one magical skill category (for example only Sorcery, Conjuring, or Enchanting, depending on edition/rules). Cheaper to create than a full Magician, with a narrower toolbox."
        case .mysticAdept:
            "A Mystic Adept splits power between spellcasting and adept powers. Flexible but expensive in priority and Karma; you juggle Magic for both spells and power points."
        case .adept:
            "A Physical Adept spends Magic on adept powers (improved reflexes, combat sense, attribute boosts) instead of spells. No traditional spellcasting—your body is the focus."
        case .technomancer:
            "A Technomancer is emerged, not awakened: Resonance replaces a cyberdeck. You thread complex forms, compile sprites, and live in the Matrix with a living persona. Cyberware that burns Essence can cripple Resonance."
        }
    }

    public static func pathStory(_ path: AwakenedPath) -> String {
        switch path {
        case .mundane:
            "You survived the Sixth World the old-fashioned way: training, chrome, contacts, and nerve. Magic is someone else’s problem—or your next bullet’s."
        case .fullMagician:
            "The Awakening touched you hard. Mana answers when you call; spirits listen. Corps want you as asset or specimen. Shadows want your fire support."
        case .aspectedMagician:
            "Your gift is narrow but deep—one discipline, mastered. Specialists live longer when they know exactly what they’re for."
        case .mysticAdept:
            "You walk two paths: spell and sinew. Every point of Magic is a choice between a spell formula and a power etched into flesh."
        case .adept:
            "Magic lives in your muscles and nerves. You don’t throw fireballs—you are the weapon, refined by will."
        case .technomancer:
            "You never needed a deck. The Resonance sings; the Matrix is a living ocean you swim without drowning—usually."
        }
    }

    // MARK: - Skills

    public static func skillDescription(catalogKey: String) -> String {
        switch catalogKey {
        case "pistols":
            "Firearms skill for pistols and similar sidearms (edition naming varies). Used to attack with personal firearms; specialization can focus on semi-autos, revolvers, etc."
        case "unarmed":
            "Close combat without (or with improvised) weapons—punches, kicks, cyber-implants. Strength and Agility both matter for effect."
        case "sneaking":
            "Moving unseen and unheard. Opposes Perception; critical for infiltration runs and ambush setup."
        case "perception":
            "Noticing details, ambushes, clues, and Matrix icons. High Perception keeps you from walking into the wrong room."
        case "athletics":
            "Running, climbing, swimming, gymnastics—broad physical motion. Escapes, chases, and parkour live here."
        case "negotiation":
            "Making deals, haggling pay, and social leverage. Faces live on Negotiation and related Influence skills."
        case "hacking":
            "Attacking and exploiting hosts, devices, and personas in the Matrix (Cracking/Hacking depending on edition). Deckers’ bread and butter."
        case "electronics":
            "Hardware, software, and device operation—repair, configuration, and non-attack Matrix work."
        case "piloting":
            "Controlling ground craft, aircraft, or watercraft (split by edition). Riggers and getaway drivers invest heavily here."
        case "spellcasting":
            "Casting spells. Requires Magic and an appropriate magical path. Drain resists with Willpower (+ attribute by tradition)."
        case "summoning":
            "Calling spirits to serve. Magician territory; opposed by spirit Force and limited by Magic."
        case "first_aid":
            "Patching wounds in the field. Stabilizes allies and treats physical damage between real medical care."
        default:
            "Trained capability used with a linked attribute to form a dice pool. Higher ranks mean more reliable professional performance."
        }
    }

    // MARK: - Qualities

    public static func qualityDescription(catalogKey: String) -> String {
        switch catalogKey {
        case "toughness":
            "Represents exceptional physical resilience—extra ability to shrug damage or push through injury (exact bonus depends on edition quality text)."
        case "guts":
            "Courage under fire; resistance to intimidation and fear effects that would freeze a lesser runner."
        case "first_impression":
            "You make a strong first impression—social tests against new contacts or first meetings tilt in your favor."
        case "sinner":
            "You have a legal SIN (System Identification Number). Easier legitimate travel and banking; worse privacy and corp tracking."
        case "allergy":
            "A common mild allergy—mechanical vulnerability or social inconvenience when the trigger is present."
        case "distinctive":
            "A memorable look or tell. Easier for enemies to describe and track you; style has a price."
        default:
            "A lasting trait that modifies your character’s capabilities or story complications."
        }
    }

    public static var karmaBudgetGuidance: String {
        """
        Karma is the flexible currency of character improvement. During generation, leftover or quality Karma is commonly spent on:
        • Buying positive qualities (or offsetting them with negative qualities that grant Karma)
        • Raising skills or attributes after priority/BP spending (edition-dependent)
        • Spells, complex forms, bindings, or initiation (for awakened/emerged characters)
        • Contacts and lifestyle flourishes in some tables

        If you skip optional qualities, that Karma stays available for post-gen advancement or other chargen purchases your table allows. Negative qualities grant Karma now but create lasting complications in play.
        """
    }

    public static var mundanePathLabel: String {
        "Mundane (no Magic/Resonance)"
    }

    public static var conceptFieldHelp: String {
        "This is the free-text concept on your character sheet (what you write under “concept”), not a locked class. It defaults to the role name so the sheet isn’t blank—edit it to something personal (e.g. “Ex-Renraku security mage”)."
    }
}
