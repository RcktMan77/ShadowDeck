//
//  Edition.swift
//  ShadowDeck
//
//  First-class edition peers: SR4, SR5, and SR6 are equal citizens.
//

import Foundation

/// Supported Shadowrun rule editions. Each edition has a full rules strategy.
public enum Edition: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case sr4 = "SR4"
    case sr5 = "SR5"
    case sr6 = "SR6"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sr4: "Shadowrun 4th Edition"
        case .sr5: "Shadowrun 5th Edition"
        case .sr6: "Shadowrun 6th Edition"
        }
    }

    public var shortName: String { rawValue }

    /// Core rulebook short labels used in UI and docs.
    public var coreBookLabel: String {
        switch self {
        case .sr4: "SR4A Core"
        case .sr5: "SR5 Core"
        case .sr6: "SR6 Core (Sixth World)"
        }
    }

    /// Whether this edition uses the classic A–E priority table for default generation.
    public var usesPriorityGenerationByDefault: Bool {
        switch self {
        case .sr4: false
        case .sr5, .sr6: true
        }
    }

    /// Whether Physical / Mental / Social limits are a core derived mechanic.
    public var usesLimits: Bool {
        switch self {
        case .sr4: false
        case .sr5: true
        case .sr6: false // SR6 dropped classic limits in favor of Edge-centric design
        }
    }

    /// Whether Edge is a depleting session resource that refreshes (SR6 style).
    public var usesSessionEdgePool: Bool {
        self == .sr6
    }
}
