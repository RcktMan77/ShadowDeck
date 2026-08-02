//
//  AppDelegate.swift
//  ShadowDeck
//
//  Phase 8 — receive Finder double-clicks / Open for .shadowdeck packages.
//  Also keeps cold-launch focus on the main window (splash), not restored utility windows.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: AppCommand.openPackageURL, object: url)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Library app — no untitled document window.
        false
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start before the first window is ordered front so we can pin splash size
        // without a visible “large → splash” shrink.
        LaunchWindowCoordinator.beginColdLaunchGuard()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchWindowCoordinator.reinforceColdLaunch()
    }

    func applicationDidResignActive(_ notification: Notification) {
        LaunchWindowCoordinator.persistMainWindowFrameIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        LaunchWindowCoordinator.persistMainWindowFrameIfPossible()
    }
}
