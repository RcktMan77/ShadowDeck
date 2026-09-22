//
//  GenerationWizardView.swift
//  ShadowDeck
//
//  Multi-page character generation with painted art, rules help, and recommendations.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GenerationWizardView: View {
    @Environment(LibraryEnvironment.self) var libraryEnvironment
    @ObservedObject var catalog = CatalogStore.shared
    @State var draft = GenerationDraft()
    @State var statusMessage: String?
    @State var didFinish = false
    @State var avatarImportError: String?
    @State var scrollAnchor = UUID()
    @State var showHouseRulesBrowser = false
    @State var confirmCancel = false
    @State var showSpellCatalog = false
    @State var draftContactName = ""
    @State var draftContactRole = "Fixer"
    @State var draftContactConnection = 2
    @State var draftContactLoyalty = 2
    /// Text field for direct BP entry on the SR4 resources step (kept in sync with draft.nuyen).
    @State var resourceBPText = "0"

    var onFinished: (() -> Void)?
    /// Leave the wizard without saving (any step).
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AllocationCounterBar(draft: draft)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()

            // Sticky profile art after concept is chosen
            if draft.step > .concept {
                ProfileArtChrome(draft: draft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }

            // Sticky priority balance on priorities step
            if draft.step == .priorities && draft.generationSystem != .buildPoints {
                PriorityBalanceBanner(draft: draft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    stepContent
                        .padding(20)
                        .frame(maxWidth: 960, alignment: .leading)
                        .id(scrollAnchor)
                }
                .onChange(of: draft.step) { _, _ in
                    statusMessage = nil
                    scrollAnchor = UUID()
                    Task { @MainActor in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(scrollAnchor, anchor: .top)
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.wizardShowRoleStep)) { _ in
            // Marketing screenshots: land on Concept & Role with a photogenic archetype.
            draft.edition = .sr5
            draft.archetype = .decker
            if draft.concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.concept = "Ex-Renraku matrix specialist"
            }
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = "Aiko Sato"
            }
            if draft.streetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.streetName = "Ghostwire"
            }
            draft.step = .concept
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Cancel character creation?",
            isPresented: $confirmCancel,
            titleVisibility: .visible
        ) {
            Button("Discard Character", role: .destructive) {
                onCancel?()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Progress in this wizard will be lost. Nothing has been saved to your library yet.")
        }
    }

    var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Character")
                    .font(.title2.weight(.semibold))
                Text("Step \(draft.step.rawValue + 1) of \(draft.steps.count) — \(draft.step.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Progress dots only — Cancel lives next to Back in the footer.
            HStack(spacing: 6) {
                ForEach(draft.steps) { step in
                    Circle()
                        .fill(step == draft.step ? Color.accentColor : (step < draft.step ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25)))
                        .frame(width: 8, height: 8)
                        .help(step.title)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    var stepContent: some View {
        switch draft.step {
        case .edition: editionStep
        case .concept: conceptStep
        case .metatype: metatypeStep
        case .priorities: prioritiesStep
        case .attributes: attributesStep
        case .magic: magicStep
        case .skills: skillsStep
        case .qualities: qualitiesStep
        case .resources: resourcesStep
        case .finish: finishStep
        }
    }

    var footer: some View {
        HStack {
            AppChromeButton.title(
                "Cancel",
                help: "Leave without saving this character"
            ) {
                requestCancel()
            }
            AppChromeButton.title(
                "Back",
                help: "Previous step",
                isEnabled: draft.step != .edition
            ) {
                draft.goBack()
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if draft.step == .finish {
                AppChromeButton.title(
                    "Save Character",
                    help: "Save this character to your library",
                    style: .prominent,
                    isEnabled: draft.canGoNext && !didFinish,
                    keyEquivalent: "\r"
                ) {
                    saveCharacter()
                }
            } else {
                AppChromeButton.title(
                    "Continue",
                    help: "Next step",
                    style: .prominent,
                    isEnabled: draft.canGoNext,
                    keyEquivalent: "\r"
                ) {
                    draft.goNext()
                }
            }
        }
        .padding(16)
    }

    func pickAvatar() {
        let panel = NSOpenPanel()
        panel.title = "Choose Portrait"
        panel.message = "Choose a portrait image for this runner"
        panel.prompt = "Use Image"
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .heic, .tiff]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                avatarImportError = "Selected image was empty."
                return
            }
            guard data.count < 8 * 1024 * 1024 else {
                avatarImportError = "Image must be under 8 MB."
                return
            }
            guard NSImage(data: data) != nil else {
                avatarImportError = "Could not read that file as an image."
                return
            }
            draft.avatarData = data
            avatarImportError = nil
        } catch {
            avatarImportError = error.localizedDescription
        }
    }

    func requestCancel() {
        // Confirm only after the user has moved past the first step or entered a name.
        let hasProgress = draft.step != .edition
            || !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.houseRules.enabled.isEmpty == false && draft.houseRules != .coreBook
        if hasProgress {
            confirmCancel = true
        } else {
            onCancel?()
        }
    }

    func saveCharacter() {
        do {
            let character = draft.buildCharacter()
            try libraryEnvironment.library.save(character, avatarData: draft.avatarData)
            didFinish = true
            statusMessage = "Saved \(character.displayTitle)."
            onFinished?()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    GenerationWizardView()
        .environment(LibraryEnvironment.preview(seedSamples: false))
        .frame(width: 1000, height: 760)
}
