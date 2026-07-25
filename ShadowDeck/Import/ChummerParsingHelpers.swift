//
//  ChummerParsingHelpers.swift
//  ShadowDeck
//
//  Shared coercion helpers for Chummer's stringly-typed exports.
//

import Foundation

enum ChummerParsingHelpers {
    static func stringValue(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if any is NSNull { return nil }
        if let n = any as? NSNumber {
            return n.stringValue
        }
        if let b = any as? Bool {
            return b ? "True" : "False"
        }
        return String(describing: any)
    }

    static func intValue(_ any: Any?, default defaultValue: Int = 0) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = stringValue(any) {
            let cleaned = s.replacingOccurrences(of: ",", with: "")
            if let i = Int(cleaned) { return i }
            if let d = Double(cleaned) { return Int(d) }
        }
        return defaultValue
    }

    static func decimalValue(_ any: Any?, default defaultValue: Decimal = 0) -> Decimal {
        if let d = any as? Decimal { return d }
        if let d = any as? Double { return Decimal(d) }
        if let i = any as? Int { return Decimal(i) }
        if let n = any as? NSNumber { return n.decimalValue }
        if let s = stringValue(any) {
            let cleaned = s.replacingOccurrences(of: ",", with: "")
            if let d = Decimal(string: cleaned) { return d }
        }
        return defaultValue
    }

    static func boolValue(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let s = stringValue(any)?.lowercased() {
            return s == "true" || s == "yes" || s == "1"
        }
        if let i = any as? Int { return i != 0 }
        return false
    }

    /// Chummer XML→JSON often wraps repeating elements as a single object or an array.
    static func arrayOfDictionaries(_ node: Any?, childKey: String? = nil) -> [[String: Any]] {
        guard let node else { return [] }

        if let childKey, let dict = node as? [String: Any] {
            return arrayOfDictionaries(dict[childKey])
        }

        if let arr = node as? [Any] {
            return arr.compactMap { item -> [String: Any]? in
                if let d = item as? [String: Any] { return d }
                return nil
            }
        }
        if let dict = node as? [String: Any] {
            return [dict]
        }
        return []
    }

    /// Attributes block in JSON is often: ["0", { "attribute": [ ... ] }, ...]
    static func attributeDictionaries(from attributesNode: Any?) -> [[String: Any]] {
        guard let attributesNode else { return [] }

        if let arr = attributesNode as? [Any] {
            var result: [[String: Any]] = []
            for item in arr {
                if let dict = item as? [String: Any] {
                    if let nested = dict["attribute"] {
                        result.append(contentsOf: arrayOfDictionaries(nested))
                    } else if dict["name"] != nil || dict["name_english"] != nil {
                        result.append(dict)
                    }
                }
            }
            return result
        }

        if let dict = attributesNode as? [String: Any] {
            if let nested = dict["attribute"] {
                return arrayOfDictionaries(nested)
            }
            return arrayOfDictionaries(dict)
        }

        return []
    }

    static func stripHTML(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        var result = html
        // Basic tag strip; good enough for Chummer notes fields.
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func catalogKey(from name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
    }
}
