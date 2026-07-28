//
//  AppDelegate.swift
//  ShadowDeck
//
//  Phase 8 — receive Finder double-clicks / Open for .shadowdeck packages.
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
}
