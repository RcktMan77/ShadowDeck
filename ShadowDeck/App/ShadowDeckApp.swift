//
//  ShadowDeckApp.swift
//  ShadowDeck
//
//  Shadowrun character creation & campaign management for macOS.
//

import SwiftUI
import SwiftData

@main
struct ShadowDeckApp: App {
    private let libraryEnvironment: LibraryEnvironment

    init() {
        do {
            libraryEnvironment = try LibraryEnvironment.live()
        } catch {
            // Fall back to empty in-memory so the window still launches if disk setup fails.
            do {
                libraryEnvironment = try LibraryEnvironment.ephemeral()
                libraryEnvironment.lastErrorMessage =
                    "Persistence unavailable: \(error.localizedDescription). Using temporary in-memory library."
            } catch {
                fatalError("Unable to create ShadowDeck library: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(libraryEnvironment)
                .modelContainer(libraryEnvironment.container)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(libraryEnvironment)
        }
    }
}
