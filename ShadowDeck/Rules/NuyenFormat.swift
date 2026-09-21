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
