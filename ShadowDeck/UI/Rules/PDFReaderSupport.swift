import Foundation

/// Run work after the current SwiftUI update/layout pass finishes.
@MainActor
func afterViewUpdate(_ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        await Task.yield()
        work()
    }
}
