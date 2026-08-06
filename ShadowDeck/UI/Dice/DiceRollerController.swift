//
//  DiceRollerController.swift
//  ShadowDeck
//
//  Session state for the character-sheet dice roller (inspector panel).
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class DiceRollerController: ObservableObject {
    static let historyLimit = 10

    @Published var isPresented = false
    @Published var edition: Edition = .sr5
    @Published var diceRules: DiceHouseRules = .coreBook
    @Published var pool: Int = 1
    @Published var modifier: Int = 0
    @Published var sourceLabel: String = "Manual"
    @Published var edgeRating: Int = 0
    @Published var edgeRemaining: Int = 0
    @Published var pushTheLimit = false
    @Published var lastResult: DiceResult?
    /// Preview of Second Chance before Edge is spent.
    @Published var secondChancePreview: DiceResult?
    @Published var history: [DiceResult] = []
    @Published var animateRolls = false

    private var characterID: UUID?

    var effectivePool: Int {
        let base = max(0, pool + modifier)
        if pushTheLimit {
            return DiceRollerEngine.pushTheLimitPool(basePool: base, edgeRating: edgeRating)
        }
        return base
    }

    var ruleOfSixActiveForNextRoll: Bool {
        diceRules.ruleOfSixEnabled(pushingTheLimit: pushTheLimit && canPushTheLimit)
    }

    /// Full SR6 Edge Actions (default for SR6 when house rule simplifiedSR6Edge is off).
    var usesFullSR6Edge: Bool {
        diceRules.usesFullSR6EdgeActions(for: edition)
    }

    var canPushTheLimit: Bool {
        edgeRemaining > 0 && edgeRating > 0
    }

    var canSecondChance: Bool {
        lastResult != nil && edgeRemaining > 0
    }

    var canBuyHit: Bool {
        usesFullSR6Edge && lastResult != nil && edgeRemaining > 0
    }

    var canCloseCall: Bool {
        usesFullSR6Edge
            && edgeRemaining > 0
            && (lastResult?.glitch == true || lastResult?.criticalGlitch == true)
    }

    var edgeModelCaption: String {
        if edition == .sr6 {
            if usesFullSR6Edge {
                return "SR6 Edge Actions · session pool (Refresh between scenes)"
            }
            return "Simplified Edge (SR5-style Push / Second Chance) · house rule"
        }
        return "Session Edge · \(edition.shortName)"
    }

    // MARK: - Presentation

    func present(request: DiceRollRequest, characterID: UUID?, diceRules: DiceHouseRules = .coreBook) {
        let sameCharacter = characterID != nil && characterID == self.characterID
        self.characterID = characterID
        edition = request.edition
        self.diceRules = diceRules
        pool = max(0, request.pool)
        modifier = request.modifier
        sourceLabel = request.sourceLabel ?? "Manual"
        edgeRating = max(0, request.edgeRating)
        if !sameCharacter || edgeRemaining > edgeRating {
            edgeRemaining = edgeRating
        }
        pushTheLimit = false
        lastResult = nil
        secondChancePreview = nil
        isPresented = true
    }

    func presentManual(character: Character) {
        present(
            request: DiceRollRequest(
                pool: 1,
                edition: character.edition,
                sourceLabel: "Manual",
                edgeRating: DicePoolResolver.edgeRating(character: character)
            ),
            characterID: character.id,
            diceRules: character.houseRules.resolvedDice
        )
    }

    func dismiss() {
        isPresented = false
        secondChancePreview = nil
    }

    // MARK: - Edge session

    func refreshEdge() {
        edgeRemaining = edgeRating
    }

    // MARK: - Roll

    func roll() {
        secondChancePreview = nil
        var edgeSpent = 0
        var mode: DiceEdgeMode = .none
        var pushing = false
        var rollPool = max(0, pool + modifier)

        if pushTheLimit, canPushTheLimit {
            rollPool = DiceRollerEngine.pushTheLimitPool(basePool: max(0, pool + modifier), edgeRating: edgeRating)
            edgeSpent = 1
            mode = .pushTheLimit
            pushing = true
            edgeRemaining = max(0, edgeRemaining - 1)
            pushTheLimit = false
        }

        let explode = diceRules.ruleOfSixEnabled(pushingTheLimit: pushing)
        let options = DiceRollOptions(ruleOfSix: explode)

        let result = DiceRollerEngine.roll(
            pool: rollPool,
            edition: edition,
            diceRules: diceRules,
            options: options,
            edgeSpent: edgeSpent,
            edgeMode: mode,
            modifier: modifier,
            sourceLabel: sourceLabel
        )
        // Store base pool (before push) for display consistency of the request
        var stored = result
        stored.pool = max(0, pool + modifier)
        commitResult(stored)
    }

    func previewSecondChance() {
        guard let last = lastResult, canSecondChance else {
            secondChancePreview = nil
            return
        }
        secondChancePreview = DiceRollerEngine.secondChance(previous: last, diceRules: diceRules)
    }

    func commitSecondChance() {
        guard let preview = secondChancePreview, canSecondChance else { return }
        edgeRemaining = max(0, edgeRemaining - 1)
        commitResult(preview)
        secondChancePreview = nil
    }

    func cancelSecondChancePreview() {
        secondChancePreview = nil
    }

    /// SR6: spend 1 Edge for one automatic hit on the last result.
    func buyHit() {
        guard let last = lastResult, canBuyHit else { return }
        let next = DiceRollerEngine.buyHit(previous: last, diceRules: diceRules)
        edgeRemaining = max(0, edgeRemaining - 1)
        secondChancePreview = nil
        commitResult(next)
    }

    /// SR6: spend 1 Edge to clear glitch flags on the last result.
    func closeCall() {
        guard let last = lastResult, canCloseCall,
              let next = DiceRollerEngine.closeCall(previous: last) else { return }
        edgeRemaining = max(0, edgeRemaining - 1)
        secondChancePreview = nil
        commitResult(next)
    }

    func loadFromHistory(_ result: DiceResult) {
        edition = result.edition
        pool = max(0, result.pool)
        modifier = result.modifier
        sourceLabel = result.sourceLabel ?? "Manual"
        lastResult = result
        secondChancePreview = nil
        isPresented = true
    }

    func copyLastResult() {
        let text = (secondChancePreview ?? lastResult)?.copyText ?? ""
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func commitResult(_ result: DiceResult) {
        lastResult = result
        history.insert(result, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
    }
}
