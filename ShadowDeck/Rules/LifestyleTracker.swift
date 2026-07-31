//
//  LifestyleTracker.swift
//  ShadowDeck
//
//  Pure lifestyle burn / process-month / prepay math (no UI, no persistence).
//

import Foundation

// MARK: - Summaries

public struct LifestyleBurnSummary: Sendable, Hashable {
    /// Σ monthlyCost for active lifestyles.
    public var monthlyBurn: Int
    /// Portion of monthly burn currently covered by prepaid months (> 0 prepaid).
    public var prepaidCoveredBurn: Int
    /// Cash that must be paid this process step (active, 0 prepaid).
    public var cashDue: Int
    public var activeCount: Int
    /// Minimum prepaid months among active lifestyles (0 if any due).
    public var minimumPrepaidMonths: Int
    public var liquidity: Int
    public var isUnderfundedForOneMonth: Bool

    public var overallStatus: LifestyleCoverageStatus {
        if activeCount == 0 { return .covered }
        if cashDue == 0 { return .covered }
        if isUnderfundedForOneMonth { return .underfunded }
        return .due
    }
}

public enum LifestyleTrackerError: Error, LocalizedError, Equatable {
    case invalidMonthCount
    case lifestyleNotFound
    case inactiveLifestyle
    case invalidPrepayMonths
    case insufficientNuyen(needed: Int, available: Int)
    case shortfall(needed: Int, available: Int, months: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMonthCount:
            return "Choose 1, 2, or 3 months to process."
        case .lifestyleNotFound:
            return "That lifestyle was not found."
        case .inactiveLifestyle:
            return "Inactive lifestyles cannot be prepaid."
        case .invalidPrepayMonths:
            return "Prepay at least one month."
        case .insufficientNuyen(let needed, let available):
            return "Need ¥\(needed.formatted()) but only ¥\(available.formatted()) available in nuyen."
        case .shortfall(let needed, let available, let months):
            let label = months == 1 ? "1 month" : "\(months) months"
            return "Cannot process \(label): need ¥\(needed.formatted()) but only ¥\(available.formatted()) available (reserve + nuyen)."
        }
    }
}

public enum LifestyleTracker {
    public static let allowedProcessMonths = 1...3

    // MARK: Burn summary

    public static func burnSummary(for character: Character) -> LifestyleBurnSummary {
        let active = character.lifestyles.filter(\.isActive)
        let monthlyBurn = active.reduce(0) { $0 + max(0, $1.monthlyCost) }
        let prepaidCovered = active
            .filter { $0.monthsPrepaid > 0 }
            .reduce(0) { $0 + max(0, $1.monthlyCost) }
        let cashDue = active
            .filter { $0.monthsPrepaid == 0 }
            .reduce(0) { $0 + max(0, $1.monthlyCost) }
        let minPrepaid = active.map(\.monthsPrepaid).min() ?? 0
        let liquidity = max(0, character.nuyen) + max(0, character.lifestyleNuyenReserve)
        return LifestyleBurnSummary(
            monthlyBurn: monthlyBurn,
            prepaidCoveredBurn: prepaidCovered,
            cashDue: cashDue,
            activeCount: active.count,
            minimumPrepaidMonths: minPrepaid,
            liquidity: liquidity,
            isUnderfundedForOneMonth: cashDue > liquidity
        )
    }

    /// Total cash that must be paid to process `months` consecutive months from the current prepaid state.
    public static func cashRequiredToProcess(character: Character, months: Int) -> Int {
        guard months >= 1 else { return 0 }
        var prepaid = character.lifestyles.map(\.monthsPrepaid)
        var totalCash = 0
        for _ in 0..<months {
            var monthCash = 0
            for (i, life) in character.lifestyles.enumerated() where life.isActive {
                if prepaid[i] > 0 {
                    prepaid[i] -= 1
                } else {
                    monthCash += max(0, life.monthlyCost)
                }
            }
            totalCash += monthCash
        }
        return totalCash
    }

    // MARK: Process month(s)

    /// Advance `months` (1…3). Reserve is spent before nuyen. Throws on shortfall (no partial apply).
    public static func processMonths(_ character: inout Character, months: Int, at date: Date = Date()) throws {
        guard allowedProcessMonths.contains(months) else {
            throw LifestyleTrackerError.invalidMonthCount
        }
        let needed = cashRequiredToProcess(character: character, months: months)
        let available = max(0, character.nuyen) + max(0, character.lifestyleNuyenReserve)
        if needed > available {
            throw LifestyleTrackerError.shortfall(needed: needed, available: available, months: months)
        }

        var spentFromReserve = 0
        var spentFromNuyen = 0

        for _ in 0..<months {
            for i in character.lifestyles.indices where character.lifestyles[i].isActive {
                if character.lifestyles[i].monthsPrepaid > 0 {
                    character.lifestyles[i].monthsPrepaid -= 1
                } else {
                    let cost = max(0, character.lifestyles[i].monthlyCost)
                    guard cost > 0 else { continue }
                    let fromReserve = min(cost, max(0, character.lifestyleNuyenReserve))
                    character.lifestyleNuyenReserve -= fromReserve
                    spentFromReserve += fromReserve
                    let remainder = cost - fromReserve
                    character.nuyen -= remainder
                    spentFromNuyen += remainder
                }
            }
        }

        character.lifestyleLastProcessedAt = date
        let totalSpent = spentFromReserve + spentFromNuyen
        let monthLabel = months == 1 ? "1 month" : "\(months) months"
        character.appendLifestyleLedger(
            LifestyleLedgerEntry(
                date: date,
                kind: .processMonth,
                amount: -totalSpent,
                note: "Processed \(monthLabel)"
                    + (totalSpent == 0
                        ? " (prepaid only)"
                        : " (¥\(spentFromReserve.formatted()) reserve, ¥\(spentFromNuyen.formatted()) nuyen)")
            )
        )
        character.touch()
    }

    // MARK: Prepay

    /// Pay `months` of rent up front for one lifestyle from **nuyen** (not reserve).
    public static func prepay(
        lifestyleID: UUID,
        months: Int,
        character: inout Character,
        at date: Date = Date()
    ) throws {
        guard months >= 1 else { throw LifestyleTrackerError.invalidPrepayMonths }
        guard let index = character.lifestyles.firstIndex(where: { $0.id == lifestyleID }) else {
            throw LifestyleTrackerError.lifestyleNotFound
        }
        guard character.lifestyles[index].isActive else {
            throw LifestyleTrackerError.inactiveLifestyle
        }
        let costPer = max(0, character.lifestyles[index].monthlyCost)
        let total = costPer * months
        if total > max(0, character.nuyen) {
            throw LifestyleTrackerError.insufficientNuyen(needed: total, available: max(0, character.nuyen))
        }
        character.nuyen -= total
        character.lifestyles[index].monthsPrepaid += months
        let name = character.lifestyles[index].name
        character.appendLifestyleLedger(
            LifestyleLedgerEntry(
                date: date,
                kind: .prepay,
                amount: -total,
                note: "Prepaid \(months) mo · \(name.isEmpty ? "Lifestyle" : name)",
                lifestyleID: lifestyleID
            )
        )
        character.touch()
    }

    // MARK: Reserve

    public static func depositToReserve(amount: Int, character: inout Character, at date: Date = Date()) throws {
        let amt = max(0, amount)
        guard amt > 0 else { return }
        if amt > max(0, character.nuyen) {
            throw LifestyleTrackerError.insufficientNuyen(needed: amt, available: max(0, character.nuyen))
        }
        character.nuyen -= amt
        character.lifestyleNuyenReserve += amt
        character.appendLifestyleLedger(
            LifestyleLedgerEntry(
                date: date,
                kind: .reserveDeposit,
                amount: -amt,
                note: "Moved ¥\(amt.formatted()) to lifestyle reserve"
            )
        )
        character.touch()
    }

    public static func withdrawFromReserve(amount: Int, character: inout Character, at date: Date = Date()) throws {
        let amt = max(0, amount)
        guard amt > 0 else { return }
        let available = max(0, character.lifestyleNuyenReserve)
        if amt > available {
            throw LifestyleTrackerError.insufficientNuyen(needed: amt, available: available)
        }
        character.lifestyleNuyenReserve -= amt
        character.nuyen += amt
        character.appendLifestyleLedger(
            LifestyleLedgerEntry(
                date: date,
                kind: .reserveWithdraw,
                amount: amt,
                note: "Moved ¥\(amt.formatted()) from lifestyle reserve to nuyen"
            )
        )
        character.touch()
    }

    // MARK: Status helpers

    public static func status(for lifestyle: Lifestyle, liquidity: Int) -> LifestyleCoverageStatus {
        guard lifestyle.isActive else { return .inactive }
        if lifestyle.monthsPrepaid > 0 { return .covered }
        if lifestyle.monthlyCost > liquidity { return .underfunded }
        return .due
    }

    public static func summaryStatus(for character: Character) -> LifestyleCoverageStatus {
        burnSummary(for: character).overallStatus
    }
}
