//
//  ShadowDeckApp.swift
//  ShadowDeck
//
//  Shadowrun character creation & campaign management for macOS.
//

import SwiftUI

@main
struct ShadowDeckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
        }
    }
}
