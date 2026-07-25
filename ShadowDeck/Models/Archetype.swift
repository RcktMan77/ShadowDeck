//
//  Archetype.swift
//  ShadowDeck
//
//  Playstyle “roles” for the generation wizard showcase (not mechanical classes).
//  Summaries help players compare options before priorities/points.
//

import Foundation
import SwiftUI

public enum RunnerArchetype: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case streetSamurai
    case adept
    case combatMage
    case face
    case decker
    case rigger
    case technomancer
    case spy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .streetSamurai: "Street Samurai"
        case .adept: "Physical Adept"
        case .combatMage: "Combat Mage"
        case .face: "Face"
        case .decker: "Decker"
        case .rigger: "Rigger"
        case .technomancer: "Technomancer"
        case .spy: "Infiltrator"
        }
    }

    public var tagline: String {
        switch self {
        case .streetSamurai: "Chrome, combat, and cold precision."
        case .adept: "Magic in the muscle — no spells, all motion."
        case .combatMage: "Astral firepower and battlefield control."
        case .face: "Words as weapons; doors open before you knock."
        case .decker: "Own the Matrix, sell the secrets."
        case .rigger: "Drones, wheels, and remote supremacy."
        case .technomancer: "Born to the Resonance; no deck required."
        case .spy: "Ghost in the vents — silent, sharp, gone."
        }
    }

    public var summary: String {
        switch self {
        case .streetSamurai:
            "Prioritize Attributes and Resources for ware and weapons. Edge and Reaction keep you alive when plans break."
        case .adept:
            "Invest Magic/Resonance priority in Adept powers. Agility and combat skills carry the run."
        case .combatMage:
            "High Magic priority, Sorcery skills, and Willpower. Resources can stay lean if you summon and spellcast."
        case .face:
            "Charisma, Influence, and contacts. Social limit (SR5) or Edge (SR6) matters as much as a gun."
        case .decker:
            "Logic, cracking/electronics, and a serious deck budget. Often pairs with secondary infiltration skills."
        case .rigger:
            "Reaction, piloting, and vehicle/drone nuyen. Command the battlefield from a safe distance."
        case .technomancer:
            "Resonance priority and Tasking skills. Complex forms instead of cyberdecks."
        case .spy:
            "Agility, Stealth, and Perception. Light gear, heavy preparation, escape routes."
        }
    }

    /// Suggested priority lean (informational only — not auto-applied).
    public var suggestedFocus: [String] {
        switch self {
        case .streetSamurai: ["Attributes", "Resources", "Skills"]
        case .adept: ["Magic", "Attributes", "Skills"]
        case .combatMage: ["Magic", "Skills", "Attributes"]
        case .face: ["Attributes", "Skills", "Resources"]
        case .decker: ["Skills", "Resources", "Attributes"]
        case .rigger: ["Resources", "Skills", "Attributes"]
        case .technomancer: ["Resonance", "Skills", "Attributes"]
        case .spy: ["Skills", "Attributes", "Resources"]
        }
    }

    public var defaultAwakened: AwakenedPath {
        switch self {
        case .combatMage: .fullMagician
        case .adept: .adept
        case .technomancer: .technomancer
        default: .mundane
        }
    }

    public var symbolName: String {
        switch self {
        case .streetSamurai: "shield.lefthalf.filled"
        case .adept: "figure.martial.arts"
        case .combatMage: "sparkles"
        case .face: "person.wave.2.fill"
        case .decker: "laptopcomputer"
        case .rigger: "car.side.fill"
        case .technomancer: "waveform.path.ecg"
        case .spy: "eye.slash.fill"
        }
    }

    /// Backdrop palette for animated showcase (cyberpunk-inspired, not official art).
    public var backdropColors: [Color] {
        switch self {
        case .streetSamurai:
            [Color(red: 0.15, green: 0.05, blue: 0.08), Color(red: 0.55, green: 0.08, blue: 0.12), Color(red: 0.9, green: 0.35, blue: 0.15)]
        case .adept:
            [Color(red: 0.05, green: 0.12, blue: 0.18), Color(red: 0.1, green: 0.45, blue: 0.55), Color(red: 0.4, green: 0.95, blue: 0.85)]
        case .combatMage:
            [Color(red: 0.08, green: 0.02, blue: 0.18), Color(red: 0.35, green: 0.1, blue: 0.55), Color(red: 0.75, green: 0.35, blue: 0.95)]
        case .face:
            [Color(red: 0.12, green: 0.08, blue: 0.05), Color(red: 0.45, green: 0.28, blue: 0.1), Color(red: 0.95, green: 0.75, blue: 0.35)]
        case .decker:
            [Color(red: 0.02, green: 0.1, blue: 0.08), Color(red: 0.05, green: 0.4, blue: 0.25), Color(red: 0.2, green: 0.95, blue: 0.55)]
        case .rigger:
            [Color(red: 0.08, green: 0.08, blue: 0.1), Color(red: 0.25, green: 0.3, blue: 0.45), Color(red: 0.55, green: 0.7, blue: 0.95)]
        case .technomancer:
            [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.15, green: 0.25, blue: 0.7), Color(red: 0.4, green: 0.85, blue: 1.0)]
        case .spy:
            [Color(red: 0.05, green: 0.06, blue: 0.07), Color(red: 0.2, green: 0.22, blue: 0.25), Color(red: 0.55, green: 0.6, blue: 0.65)]
        }
    }
}
