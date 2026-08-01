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

    var canPushTheLimit: Bool {
        edgeRemaining > 0 && edgeRating > 0
    }

    var canSecondChance: Bool {
        lastResult != nil && edgeRemaining > 0
    }

    // MARK: - Presentation

    func present(request: DiceRollRequest, characterID: UUID?) {
        let sameCharacter = characterID != nil && characterID == self.characterID
        self.characterID = characterID
        edition = request.edition
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
            characterID: character.id
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
        var options = DiceRollOptions.standard
        var rollPool = max(0, pool + modifier)

        if pushTheLimit, canPushTheLimit {
            rollPool = DiceRollerEngine.pushTheLimitPool(basePool: max(0, pool + modifier), edgeRating: edgeRating)
            options = .pushTheLimit
            edgeSpent = 1
            mode = .pushTheLimit
            edgeRemaining = max(0, edgeRemaining - 1)
            pushTheLimit = false
        }

        let result = DiceRollerEngine.roll(
            pool: rollPool,
            edition: edition,
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
        secondChancePreview = DiceRollerEngine.secondChance(previous: last)
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
