//
//  RulesReferenceSession.swift
//  ShadowDeck
//
//  Shared session for the single Rules Reference window.
//

import Foundation
import SwiftUI

/// One reusable Rules Reference controller for the dedicated window.
@MainActor
final class RulesReferenceSession: ObservableObject {
    static let shared = RulesReferenceSession()

    let controller = RulesReferenceController()

    private init() {}

    /// Apply optional search/edition/character context before the window is shown or focused.
    func prepare(
        query: String? = nil,
        edition: Edition? = nil,
        calcContext: RulesCalcContext? = nil
    ) {
        controller.applyOpenContext(query: query, edition: edition, calcContext: calcContext)
    }
}

// MARK: - Open helper

enum RulesReferenceOpener {
    /// Window scene id registered on `ShadowDeckApp`.
    static let windowID = "rules-reference"

    @MainActor
    static func open(
        query: String? = nil,
        edition: Edition? = nil,
        character: Character? = nil,
        openWindow: OpenWindowAction
    ) {
        let ctx = character.map { RulesCalcContext.from(character: $0) }
        RulesReferenceSession.shared.prepare(
            query: query,
            edition: edition ?? ctx?.edition,
            calcContext: ctx
        )
        openWindow(id: windowID)
    }

    /// Open Rules Reference from anywhere without an `OpenWindowAction`.
    /// ContentView listens for `AppCommand.openRulesReference`.
    @MainActor
    static func request(
        query: String? = nil,
        edition: Edition? = nil,
        character: Character? = nil
    ) {
        var info: [AnyHashable: Any] = [:]
        if let query {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { info["query"] = trimmed }
        }
        if let character {
            info["calcContext"] = RulesCalcContext.from(character: character)
            info["edition"] = character.edition
        } else if let edition {
            info["edition"] = edition
        }
        NotificationCenter.default.post(
            name: AppCommand.openRulesReference,
            object: nil,
            userInfo: info.isEmpty ? nil : info
        )
    }
}
