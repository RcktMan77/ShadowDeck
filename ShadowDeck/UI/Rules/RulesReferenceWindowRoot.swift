import SwiftUI

// MARK: - Window root

struct RulesReferenceWindowRoot: View {
    /// Observe the session root so the window stays tied to the process-wide session.
    /// The controller is still the source of `@Published` UI state for the view tree.
    @ObservedObject private var session = RulesReferenceSession.shared

    var body: some View {
        RulesReferenceView(controller: session.controller)
            .frame(minWidth: 880, minHeight: 520)
    }
}
