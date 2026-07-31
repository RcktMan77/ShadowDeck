//
//  ShadowDeckApp.swift
//  ShadowDeck
//
//  Shadowrun character creation & campaign management for macOS.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct ShadowDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let libraryEnvironment: LibraryEnvironment
    /// Bump when splash art/copy changes so users see the new splash once after update.
    private static let splashRevision = 3
    @State private var showSplash: Bool

    init() {
        // Show splash on every cold launch (skip with click/key).
        _showSplash = State(initialValue: true)
        // Clear legacy key so Settings / docs stay accurate.
        UserDefaults.standard.removeObject(forKey: "hasSeenLaunchSplash")
        UserDefaults.standard.set(Self.splashRevision, forKey: "launchSplashRevision")
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
            ZStack {
                ContentView()
                    .environment(libraryEnvironment)
                    .modelContainer(libraryEnvironment.container)

                if showSplash {
                    LaunchSplashView {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            showSplash = false
                        }
                    }
                    .zIndex(1)
                }
            }
            // Explicit min + ideal so the scene always has a concrete size.
            // Avoid max-only / min-only frames that can collapse detail columns.
            .frame(minWidth: 900, idealWidth: 1100, minHeight: 560, idealHeight: 720)
            .onAppear {
                guard MarketingScreenshotExporter.isEnabled else { return }
                Task { @MainActor in
                    await MarketingScreenshotExporter.runSequence()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: MarketingScreenshotExporter.phaseNotification)) { note in
                guard let raw = note.object as? String,
                      let phase = MarketingScreenshotExporter.Phase(rawValue: raw)
                else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    switch phase {
                    case .splash:
                        showSplash = true
                    case .library, .generationRole, .characterSheet, .runLibrary, .runDetail, .finished:
                        showSplash = false
                    }
                }
            }
        }
        .defaultSize(width: 1100, height: 720)
        // Size from content minimum only — do not auto-resize the window when
        // switching Library / Import / Wizard ideal content sizes change.
        .windowResizability(.contentMinSize)
        // Hide native title bar so splash (and main UI) are not under a chrome strip.
        // Traffic lights remain; in-app titles come from NavigationSplitView toolbars.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Character") {
                    NotificationCenter.default.post(name: AppCommand.newCharacter, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Run") {
                    NotificationCenter.default.post(name: AppCommand.newRun, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                // Unified import: Chummer JSON/.chum5 and .shadowdeck packages.
                Button("Import Character…") {
                    NotificationCenter.default.post(name: AppCommand.importCharacter, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(libraryEnvironment)
        }
    }
}
