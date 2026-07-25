//
//  Validation.swift
//  ShadowDeck
//

import Foundation

public enum ValidationSeverity: String, Codable, Sendable, Hashable {
    case error
    case warning
    case info
}

public struct ValidationIssue: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var severity: ValidationSeverity
    public var code: String
    public var message: String
    public var field: String?

    public init(
        id: UUID = UUID(),
        severity: ValidationSeverity,
        code: String,
        message: String,
        field: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.field = field
    }
}

public struct ValidationResult: Codable, Sendable, Hashable {
    public var issues: [ValidationIssue]

    public init(issues: [ValidationIssue] = []) {
        self.issues = issues
    }

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }

    public var errors: [ValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    public var warnings: [ValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    public mutating func append(_ issue: ValidationIssue) {
        issues.append(issue)
    }

    public mutating func error(_ code: String, _ message: String, field: String? = nil) {
        append(ValidationIssue(severity: .error, code: code, message: message, field: field))
    }

    public mutating func warning(_ code: String, _ message: String, field: String? = nil) {
        append(ValidationIssue(severity: .warning, code: code, message: message, field: field))
    }
}
