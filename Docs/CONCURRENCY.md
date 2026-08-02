# Concurrency & MainActor notes

Living notes for Swift concurrency readiness (Swift 6 language mode later).  
Not a full audit — only intentional patterns and known hotspots.

## Current language mode

- Project uses **Swift 5** with **upcoming StrictConcurrency** enabled in the Debug build settings.
- Full Swift 6 mode is **not** enabled yet.

## Patterns we keep

| Pattern | Where | Why |
|---------|--------|-----|
| Pure engines as `Sendable` value types | `Rules/*`, calculators | Safe to call from any isolation |
| `@MainActor` UI controllers / stores | CatalogStore, Rules session, dice, libraries | SwiftUI + AppKit touch UI |
| `Task { @MainActor in … }` | View actions, PDF binding updates | Avoid publish-during-update |
| `Task.detached` + PDFKit per task | Shelf text search | PDFDocument is not cross-thread-safe; one doc per task |
| Capped task-group concurrency | `PDFLibrarySearchEngine.maxConcurrentBooks` | Memory on large CRBs |
| `DispatchWorkItem` cancel lists | `LaunchWindowCoordinator` | Splash/frame timers need cancel |

## Intentional `nonisolated(unsafe)` / `@unchecked Sendable`

| Symbol | Rationale |
|--------|-----------|
| `CatalogCache` static entries | Process-wide cache guarded by `NSLock`; single load path for import + UI |
| `LaunchSplashView` font register flag | One-time AppKit font registration |
| `RulesReferenceStore: @unchecked Sendable` | Immutable after load; search is read-only |

Do **not** add new global mutable caches without a lock or actor.

## Prefer over `DispatchQueue.main.async`

For simple “run next turn on main” deferrals, prefer:

```swift
Task { @MainActor in
    await Task.yield()
    // mutate @Published / @State
}
```

Keep `DispatchQueue.main.asyncAfter` / `DispatchWorkItem` when **cancellation** or **debounce** is required (launch policy, notes format refresh).

## Import / large work

- Chummer import runs on `@MainActor` today — large `.chum5` files can stall the UI.
- Future improvement: parse off-main, then hop to main for library save + UI.

## Checklist for new code

1. Rules math → pure / `Sendable`, no SwiftUI.
2. UI mutations → `@MainActor` or `Task { @MainActor }`.
3. Never write `@Published` inside `updateNSView` / `body` without yield.
4. PDFKit: one `PDFDocument` per concurrent task; share sessions when possible (`SharedPDFDocumentSession`).
