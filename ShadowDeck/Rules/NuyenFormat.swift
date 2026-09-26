//
//  NuyenFormat.swift
//  ShadowDeck
//
//  One integer grouping style for nuyen shown in the UI, wizard, and sheet.
//

import Foundation

enum NuyenFormat {
    /// Grouped integer, no currency mark. Matches `NumberFormatter` `.decimal`.
    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Grouped integer with a yen prefix.
    static func format(_ value: Int) -> String {
        "¥\(grouped(value))"
    }
}

/// Shared decimal style for essence and power points. One formatter per style.
enum DecimalFormat {
    private static let lock = NSLock()
    private static let essenceFormatter = make(minimum: 1, maximum: 2)
    private static let powerPointFormatter = make(minimum: 0, maximum: 2)

    static func essence(_ value: Decimal) -> String {
        string(value, formatter: essenceFormatter)
    }

    static func powerPoints(_ value: Decimal) -> String {
        string(value, formatter: powerPointFormatter)
    }

    private static func make(minimum: Int, maximum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = maximum
        return formatter
    }

    private static func string(_ value: Decimal, formatter: NumberFormatter) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
