//
//  ChummerParsingHelpers.swift
//  ShadowDeck
//
//  Shared coercion helpers for Chummer's stringly-typed exports.
//

import AppKit
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

    /// Clean Chummer rich-text fields (HTML from JSON exports, RTF from `.chum5`).
    static func stripHTML(_ html: String?) -> String {
        cleanRichText(html)
    }

    /// Normalize Chummer notes/description/background into plain text.
    static func cleanRichText(_ raw: String?) -> String {
        guard let raw else { return "" }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // Prefer AppKit document conversion for real RTF / HTML payloads.
        if looksLikeRTF(text), let plain = plainText(fromRichData: Data(text.utf8), documentType: .rtf) {
            text = plain
        } else if looksLikeHTML(text), let plain = plainText(fromRichData: Data(text.utf8), documentType: .html) {
            text = plain
        } else if looksLikeHTML(text) {
            text = fallbackStripTags(text)
        } else if looksLikeRTF(text) {
            text = fallbackStripRTF(text)
        }

        // Collapse runs of whitespace while preserving intentional blank lines lightly.
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeRTF(_ text: String) -> Bool {
        text.hasPrefix("{\\rtf") || text.contains("{\\rtf")
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<html") || lower.contains("<div") || lower.contains("<p")
            || lower.contains("<br") || lower.contains("<span") || lower.contains("<ul")
            || (text.contains("<") && text.contains(">"))
    }

    private static func plainText(
        fromRichData data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType
        ]
        if documentType == .html {
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) else {
            return nil
        }
        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }

    private static func fallbackStripTags(_ html: String) -> String {
        var result = html
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        return result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func fallbackStripRTF(_ rtf: String) -> String {
        // Drop control words like \par, \b0, leave readable runs.
        var result = rtf
        if let regex = try? NSRegularExpression(pattern: #"\\'[0-9a-fA-F]{2}"#, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        if let regex = try? NSRegularExpression(pattern: #"\\[a-zA-Z]+-?\d*[ ]?"#, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        result = result
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\\", with: "")
        return result
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
