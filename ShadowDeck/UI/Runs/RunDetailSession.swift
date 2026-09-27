import Foundation

/// Mutable session flags for `RunDetailView` (not `@State` bools — those can lag).
@MainActor
final class RunDetailSession {
    var allowAutoSave = true
}
