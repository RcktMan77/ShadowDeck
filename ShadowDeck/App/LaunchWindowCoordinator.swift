//
//  LaunchWindowCoordinator.swift
//  ShadowDeck
//
//  Cold-launch splash presentation for the main deck window, plus remembering
//  the library window frame across launches.
//
//  - Opens at a fixed splash size (no visible downsize).
//  - Loads the last library frame from AppPreferences for post-splash restore.
//  - Saves the library frame on live-resize end, window move (debounced), resign, terminate.
//
//  Pure size/frame helpers live on `LaunchWindowGeometry` for unit tests.
//

import AppKit

/// Pure geometry helpers (no AppKit side effects) for splash/main frame decisions.
enum LaunchWindowGeometry {
    /// Fixed splash content size (3:2) — smaller than default main (1100×720).
    static let splashContentSize = NSSize(width: 840, height: 560)
    /// Default main deck content size when nothing is saved.
    static let mainContentSize = NSSize(width: 1100, height: 720)

    static func isNearSplashSize(_ content: NSSize, tolerance: CGFloat = 48) -> Bool {
        abs(content.width - splashContentSize.width) < tolerance
            && abs(content.height - splashContentSize.height) < tolerance
    }

    static func isPlausibleMainFrame(_ frame: NSRect) -> Bool {
        frame.width >= 880 && frame.height >= 500
            && frame.width < 10_000 && frame.height < 10_000
    }

    /// Clamp a saved frame into a screen’s visible area with minimum deck size.
    static func clampedFrame(_ frame: NSRect, visibleFrame vf: NSRect) -> NSRect {
        var f = frame
        if f.maxX < vf.minX + 100 { f.origin.x = vf.minX }
        if f.minX > vf.maxX - 100 { f.origin.x = vf.maxX - f.width }
        if f.maxY < vf.minY + 100 { f.origin.y = vf.minY }
        if f.minY > vf.maxY - 100 { f.origin.y = vf.maxY - f.height }
        f.size.width = min(max(f.width, 900), vf.width)
        f.size.height = min(max(f.height, 520), vf.height)
        return f
    }

    static func centerOrigin(windowFrame f: NSRect, visibleFrame vf: NSRect) -> NSPoint {
        NSPoint(
            x: vf.midX - f.width / 2,
            y: vf.midY - f.height / 2
        )
    }
}

/// Cold-launch splash + main frame persistence coordinator.
@MainActor
enum LaunchWindowCoordinator {
    static let rulesWindowID = "rules-reference"

    static let splashContentSize = LaunchWindowGeometry.splashContentSize
    static let mainContentSize = LaunchWindowGeometry.mainContentSize

    private static let mainFrameAutosaveName = "ShadowDeck.MainDeck"

    private static var isGuarding = false
    private static var didEndSplash = false
    private static var preferredMainFrame: NSRect?
    private static var splashWork: [DispatchWorkItem] = []
    private static var persistWork: DispatchWorkItem?
    private static var keyWindowObserver: NSObjectProtocol?
    private static var resizeObserver: NSObjectProtocol?
    private static var moveObserver: NSObjectProtocol?

    // MARK: - Public lifecycle

    static func beginColdLaunchGuard() {
        cancelSplashWork()
        isGuarding = true
        didEndSplash = false
        preferredMainFrame = loadPersistedMainFrame()

        installKeyWindowObserverIfNeeded()

        applyColdLaunchFocusIfGuarding()
        for delay: TimeInterval in [0.0, 0.02, 0.08, 0.2] {
            scheduleSplash(after: delay) {
                applyColdLaunchFocusIfGuarding()
            }
        }
        // Only ends splash if still guarding (user may have dismissed already).
        scheduleSplash(after: 12) {
            guard isGuarding, !didEndSplash else { return }
            endColdLaunchGuard()
        }
    }

    static func reinforceColdLaunch() {
        guard isGuarding, !didEndSplash else { return }
        applyColdLaunchFocusIfGuarding()
    }

    static func endColdLaunchGuard() {
        if didEndSplash {
            // Already past splash — never force-resize again (would wipe user layout).
            return
        }
        didEndSplash = true
        isGuarding = false
        cancelSplashWork()
        removeKeyWindowObserver()

        applyMainWindowPresentation(force: true)
        enableMainFramePersistenceTracking()

        // Re-assert only while still splash-sized (SwiftUI one-frame snap-back).
        scheduleSplash(after: 0.05) {
            applyMainWindowPresentation(force: false)
        }
        scheduleSplash(after: 0.15) {
            applyMainWindowPresentation(force: false)
        }
    }

    static func promoteMainWindowForSplash() {
        guard isGuarding, !didEndSplash else { return }
        promoteMainWindow()
        applySplashWindowPresentation()
    }

    /// Save the current deck window frame for the next launch (no-op during splash).
    static func persistMainWindowFrameIfPossible() {
        guard didEndSplash, !isGuarding else { return }
        guard let main = primaryMainWindow() else { return }
        guard !isNearSplashSize(main) else { return }

        let frame = main.frame
        guard LaunchWindowGeometry.isPlausibleMainFrame(frame) else { return }

        preferredMainFrame = frame
        AppPreferences.set(NSStringFromRect(frame), for: .mainWindowFrame)

        if main.frameAutosaveName != mainFrameAutosaveName {
            main.setFrameAutosaveName(mainFrameAutosaveName)
        }
        main.saveFrame(usingName: mainFrameAutosaveName)
    }

    static func setTrafficLightsHidden(_ hidden: Bool, on window: NSWindow? = nil) {
        let target = window ?? primaryMainWindow()
        guard let target else { return }
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            target.standardWindowButton(type)?.isHidden = hidden
            // Also zero alpha so the buttons cannot flash during a one-frame unhide.
            target.standardWindowButton(type)?.alphaValue = hidden ? 0 : 1
        }
    }

    /// Soften / black-out title-bar chrome while splash is up (hiddenTitleBar still
    /// reserves a top strip that can pick up accent tint).
    private static func applySplashTitlebarChrome(on main: NSWindow) {
        main.titlebarAppearsTransparent = true
        main.backgroundColor = .black
        main.titlebarSeparatorStyle = .none
        // Titlebar button container (traffic lights row) — keep fully invisible.
        if let container = main.standardWindowButton(.closeButton)?.superview {
            container.alphaValue = 0
        }
    }

    private static func applyMainTitlebarChrome(on main: NSWindow) {
        main.titlebarAppearsTransparent = true
        main.backgroundColor = NSColor.windowBackgroundColor
        main.titlebarSeparatorStyle = .none
        if let container = main.standardWindowButton(.closeButton)?.superview {
            container.alphaValue = 1
        }
    }

    // MARK: - Size presentation

    private static func applyColdLaunchFocusIfGuarding() {
        guard isGuarding, !didEndSplash else { return }

        for window in rulesWindows() {
            window.close()
        }

        promoteMainWindow()
        applySplashWindowPresentation()
    }

    private static func applySplashWindowPresentation() {
        guard isGuarding, !didEndSplash, let main = primaryMainWindow() else { return }

        main.isRestorable = false
        main.setFrameAutosaveName("")

        if !isNearSplashSize(main) {
            main.setContentSize(splashContentSize)
            center(main)
        }
        applySplashTitlebarChrome(on: main)
        setTrafficLightsHidden(true, on: main)
    }

    private static func applyMainWindowPresentation(force: Bool) {
        guard let main = primaryMainWindow() else { return }
        applyMainTitlebarChrome(on: main)
        setTrafficLightsHidden(false, on: main)
        main.isRestorable = true
        main.setFrameAutosaveName(mainFrameAutosaveName)

        if !force, !isNearSplashSize(main) {
            return
        }

        if let preferred = preferredMainFrame, LaunchWindowGeometry.isPlausibleMainFrame(preferred) {
            let vf = (main.screen ?? NSScreen.main)?.visibleFrame ?? preferred
            main.setFrame(
                LaunchWindowGeometry.clampedFrame(preferred, visibleFrame: vf),
                display: true,
                animate: false
            )
        } else if main.setFrameUsingName(mainFrameAutosaveName) {
            // Applied from AppKit autosave backup.
        } else {
            main.setContentSize(mainContentSize)
            center(main)
        }
    }

    private static func enableMainFramePersistenceTracking() {
        removeResizeObservers()

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: nil,
            queue: .main
        ) { note in
            // NotificationCenter closures are nonisolated under Swift 6; hop to MainActor.
            let window = note.object as? NSWindow
            Task { @MainActor in
                guard didEndSplash, !isGuarding else { return }
                guard let window, !isRulesWindow(window) else { return }
                persistMainWindowFrameIfPossible()
            }
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main
        ) { note in
            let window = note.object as? NSWindow
            Task { @MainActor in
                guard didEndSplash, !isGuarding else { return }
                guard let window, !isRulesWindow(window) else { return }
                schedulePersistDebounced()
            }
        }
    }

    private static func schedulePersistDebounced() {
        persistWork?.cancel()
        let item = DispatchWorkItem {
            persistMainWindowFrameIfPossible()
        }
        persistWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private static func removeResizeObservers() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        persistWork?.cancel()
        persistWork = nil
    }

    private static func loadPersistedMainFrame() -> NSRect? {
        guard let raw = AppPreferences.string(.mainWindowFrame) else {
            return nil
        }
        let rect = NSRectFromString(raw)
        guard LaunchWindowGeometry.isPlausibleMainFrame(rect) else { return nil }
        return rect
    }

    private static func isNearSplashSize(_ main: NSWindow) -> Bool {
        LaunchWindowGeometry.isNearSplashSize(main.contentLayoutRect.size)
    }

    private static func center(_ main: NSWindow) {
        guard let screen = main.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let f = main.frame
        main.setFrameOrigin(LaunchWindowGeometry.centerOrigin(windowFrame: f, visibleFrame: vf))
    }

    // MARK: - Observers / scheduling

    private static func installKeyWindowObserverIfNeeded() {
        guard keyWindowObserver == nil else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            let window = note.object as? NSWindow
            Task { @MainActor in
                guard isGuarding, !didEndSplash else { return }
                guard let window, !isRulesWindow(window) else { return }
                applySplashWindowPresentation()
            }
        }
    }

    private static func removeKeyWindowObserver() {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
    }

    private static func scheduleSplash(after delay: TimeInterval, _ body: @escaping () -> Void) {
        let item = DispatchWorkItem(block: body)
        splashWork.append(item)
        if delay <= 0 {
            DispatchQueue.main.async(execute: item)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private static func cancelSplashWork() {
        splashWork.forEach { $0.cancel() }
        splashWork.removeAll()
    }

    private static func promoteMainWindow() {
        guard let main = primaryMainWindow() else { return }
        if !main.isKeyWindow || main != NSApp.keyWindow {
            main.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: false)
    }

    private static func rulesWindows() -> [NSWindow] {
        NSApp.windows.filter { isRulesWindow($0) }
    }

    private static func isRulesWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == rulesWindowID { return true }
        if window.title == "Rules Reference" { return true }
        return false
    }

    private static func primaryMainWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            guard !isRulesWindow(window) else { return false }
            guard window.styleMask.contains(.titled) || window.styleMask.contains(.fullSizeContentView) else {
                return false
            }
            if window.frame.width > 0, window.frame.width < 400 { return false }
            return true
        }
        return candidates.max {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }
    }
}

/// Backward-compatible name used throughout the app scene.
typealias AppLaunchWindowPolicy = LaunchWindowCoordinator
