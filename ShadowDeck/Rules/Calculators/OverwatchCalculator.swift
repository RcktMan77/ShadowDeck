//
//  OverwatchCalculator.swift
//  ShadowDeck
//
//  Simplified Overwatch Score (OS) session helper for Matrix play.
//  Not a full Matrix resolution engine. Label as quick aid.
//

import Foundation

public struct OverwatchAction: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// OS gained when the action is performed (simplified table).
    public var osCost: Int
    public var note: String

    public init(id: String, name: String, osCost: Int, note: String = "") {
        self.id = id
        self.name = name
        self.osCost = max(0, osCost)
        self.note = note
    }
}

public struct OverwatchSnapshot: Sendable, Hashable {
    public var score: Int
    public var threshold: Int
    public var converged: Bool
    public var remainingToConvergence: Int

    public init(score: Int, threshold: Int) {
        let s = max(0, score)
        let t = max(1, threshold)
        self.score = s
        self.threshold = t
        self.converged = s >= t
        self.remainingToConvergence = max(0, t - s)
    }
}

public enum OverwatchCalculator {
    /// Common table simplification (not edition-complete). Values are illustrative quick aids.
    public static let defaultGODThreshold = 40

    public static let defaultActions: [OverwatchAction] = [
        OverwatchAction(id: "enter_host", name: "Enter host / grid", osCost: 1, note: "Light footprint"),
        OverwatchAction(id: "probe", name: "Probe / matrix perception", osCost: 1),
        OverwatchAction(id: "snoop", name: "Snoop / data spike (minor)", osCost: 2),
        OverwatchAction(id: "hack_on_fly", name: "Hack on the fly", osCost: 3),
        OverwatchAction(id: "brute_force", name: "Brute force", osCost: 4),
        OverwatchAction(id: "crash", name: "Crash program / device", osCost: 4),
        OverwatchAction(id: "edit_file", name: "Edit file", osCost: 2),
        OverwatchAction(id: "spoof", name: "Spoof command", osCost: 3),
        OverwatchAction(id: "dump_shock_event", name: "Dumpshock / loud fail", osCost: 6, note: "Messy exit")
    ]

    public static func apply(score: Int, action: OverwatchAction) -> Int {
        max(0, score) + action.osCost
    }

    public static func apply(score: Int, delta: Int) -> Int {
        max(0, score + delta)
    }

    public static func snapshot(score: Int, threshold: Int = defaultGODThreshold) -> OverwatchSnapshot {
        OverwatchSnapshot(score: score, threshold: threshold)
    }

    public static func action(id: String) -> OverwatchAction? {
        defaultActions.first { $0.id == id }
    }
}
