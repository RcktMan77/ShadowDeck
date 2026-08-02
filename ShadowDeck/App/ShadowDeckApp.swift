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
    /// Opaque cover under the splash art; stays for a beat after dismiss so sidebar
    /// accent / title-bar chrome cannot flash through during the hand-off.
    @State private var showLaunchVeil: Bool

    init() {
        // Show splash on every cold launch (skip with click/key).
        _showSplash = State(initialValue: true)
        _showLaunchVeil = State(initialValue: true)
        // Clear legacy key so Settings / docs stay accurate.
        AppPreferences.remove(.hasSeenLaunchSplash)
        AppPreferences.set(Self.splashRevision, for: .launchSplashRevision)
        do {
            // Marketing captures never open the on-disk personal library.
            if MarketingScreenshotExporter.isEnabled {
                libraryEnvironment = try LibraryEnvironment.marketingCapture()
            } else {
                libraryEnvironment = try LibraryEnvironment.live()
            }
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

                // Always-opaque black under the splash (and briefly after dismiss).
                // Without this, NavigationSplitView’s accent selection and title-bar
                // safe area flash green through the click-to-skip hand-off.
                if showLaunchVeil {
                    Color.black
                        .ignoresSafeArea()
                        .zIndex(1)
                        .allowsHitTesting(false)
                        .transaction { $0.animation = nil }
                }

                if showSplash {
                    LaunchSplashView {
                        dismissSplashWithVeil()
                    }
                    .zIndex(2)
                    .onAppear {
                        // Fixed splash size + keep the deck key over restored utilities.
                        AppLaunchWindowPolicy.promoteMainWindowForSplash()
                    }
                }
            }
            // During splash, pin SwiftUI's proposed size to the splash canvas so the
            // scene does not open at ideal library size and then shrink.
            // After dismiss, use the normal library min/ideal.
            .frame(
                minWidth: showSplash ? AppLaunchWindowPolicy.splashContentSize.width : 900,
                idealWidth: showSplash
                    ? AppLaunchWindowPolicy.splashContentSize.width
                    : AppLaunchWindowPolicy.mainContentSize.width,
                minHeight: showSplash ? AppLaunchWindowPolicy.splashContentSize.height : 560,
                idealHeight: showSplash
                    ? AppLaunchWindowPolicy.splashContentSize.height
                    : AppLaunchWindowPolicy.mainContentSize.height
            )
            .onAppear {
                if showSplash {
                    AppLaunchWindowPolicy.promoteMainWindowForSplash()
                }
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
                        showLaunchVeil = true
                        showSplash = true
                        AppLaunchWindowPolicy.beginColdLaunchGuard()
                    case .library, .generationRole, .characterSheet, .diceRoller, .runLibrary,
                         .runGif, .advanceGif, .finished:
                        dismissSplashWithVeil()
                    }
                }
            }
        }
        // Open at splash size so the first painted frame is already correct
        // (avoids a visible downsize from the library default into splash).
        .defaultSize(
            width: AppLaunchWindowPolicy.splashContentSize.width,
            height: AppLaunchWindowPolicy.splashContentSize.height
        )
        // Size from content minimum only — do not auto-resize the window when
        // switching Library / Import / Wizard ideal content sizes change.
        .windowResizability(.contentMinSize)
        // Hide native title bar so splash (and main UI) are not under a chrome strip.
        // Traffic lights remain after splash; in-app titles come from toolbars.
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

            CommandGroup(after: .newItem) {
                Button("Roll Dice…") {
                    NotificationCenter.default.post(name: AppCommand.openDiceRoller, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Rules Reference…") {
                    NotificationCenter.default.post(name: AppCommand.openRulesReference, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            // Standard format shortcuts. Target the focused NSTextView (NotesEditor, etc.).
            // NotesNSTextView.performKeyEquivalent is a fallback if these don’t reach the field.
            CommandMenu("Format") {
                Button("Bold") {
                    NotesTextFormatting.applyBoldToFocusedTextView()
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button("Italic") {
                    NotesTextFormatting.applyItalicToFocusedTextView()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Underline") {
                    NotesTextFormatting.applyUnderlineToFocusedTextView()
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
        }

        // Single reusable Rules Reference window (not a trailing inspector).
        // Cold launch: AppLaunchWindowPolicy closes any restored instance so it
        // cannot sit key/front over the splash (see AppDelegate).
        Window("Rules Reference", id: RulesReferenceOpener.windowID) {
            RulesReferenceWindowRoot()
                .environment(libraryEnvironment)
                .background(RulesWindowChromeConfigurer())
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(libraryEnvironment)
        }
    }

    /// Drop splash art first under an opaque black veil, restore window chrome, then
    /// reveal the library after a short settle so accent title/sidebar cannot flash.
    @MainActor
    private func dismissSplashWithVeil() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            showLaunchVeil = true
            showSplash = false
        }
        // Restore library frame / traffic lights under the veil.
        AppLaunchWindowPolicy.endColdLaunchGuard()
        Task { @MainActor in
            // Two frames + a short settle: resize + NavigationSplitView first layout.
            await Task.yield()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(180))
            var clear = Transaction()
            clear.disablesAnimations = true
            withTransaction(clear) {
                showLaunchVeil = false
            }
        }
    }
}

// MARK: - Rules window chrome

/// Tags the NSWindow and disables AppKit state restoration so a prior Rules
/// session is less likely to resurrect in front of the cold-start splash.
/// Closing of restored instances is handled by `AppLaunchWindowPolicy`.
private struct RulesWindowChromeConfigurer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(RulesReferenceOpener.windowID)
            window.isRestorable = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(RulesReferenceOpener.windowID)
            window.isRestorable = false
        }
    }
}
