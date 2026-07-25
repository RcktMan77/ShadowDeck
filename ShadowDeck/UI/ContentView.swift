//
//  ContentView.swift
//  ShadowDeck
//
//  Root window: library shell with import entry point.
//

import SwiftUI

private enum SidebarItem: String, Identifiable, Hashable, CaseIterable {
    case characters
    case importCharacter
    case newCharacter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characters: "Characters"
        case .importCharacter: "Import…"
        case .newCharacter: "New Character"
        }
    }

    var systemImage: String {
        switch self {
        case .characters: "person.3"
        case .importCharacter: "square.and.arrow.down"
        case .newCharacter: "plus.circle"
        }
    }
}

struct ContentView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @State private var selection: SidebarItem? = .characters
    @State private var summaries: [CharacterSummary] = []
    @State private var statusMessage: String?
    @State private var selectedCharacterID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label(SidebarItem.characters.title, systemImage: SidebarItem.characters.systemImage)
                        .badge(summaries.count)
                        .tag(SidebarItem.characters)
                    Label(SidebarItem.importCharacter.title, systemImage: SidebarItem.importCharacter.systemImage)
                        .tag(SidebarItem.importCharacter)
                }
                Section("Create") {
                    Label(SidebarItem.newCharacter.title, systemImage: SidebarItem.newCharacter.systemImage)
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.newCharacter)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            .listStyle(.sidebar)
        } detail: {
            detail
        }
        .navigationTitle("ShadowDeck")
        .onAppear { refresh() }
        .onChange(of: selection) { _, newValue in
            if newValue == .characters { refresh() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .importCharacter:
            ImportView()
                .onDisappear { refresh() }
        case .newCharacter:
            ContentUnavailableView(
                "Character Generation",
                systemImage: "wand.and.stars",
                description: Text("The generation wizard arrives in Phase 4.")
            )
        case .characters, .none:
            charactersDetail
        }
    }

    private var charactersDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Character Library")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                Button("Load Samples", systemImage: "tray.and.arrow.down") { seedSamplesIfEmpty() }
                Button("Import…", systemImage: "square.and.arrow.down") {
                    selection = .importCharacter
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = libraryEnvironment.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if summaries.isEmpty {
                ContentUnavailableView {
                    Label("No Characters Yet", systemImage: "person.crop.rectangle.stack")
                } description: {
                    Text("Import a Chummer file or load sample runners to get started.")
                } actions: {
                    Button("Import…") { selection = .importCharacter }
                    Button("Load Samples") { seedSamplesIfEmpty() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(summaries, selection: $selectedCharacterID) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.displayTitle)
                                .font(.headline)
                            Text("\(summary.editionRaw) · \(summary.metatypeRaw.capitalized) · \(summary.concept.isEmpty ? "—" : summary.concept)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if summary.hasAvatar {
                            Image(systemName: "person.crop.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(summary.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deleteCharacter(summary.id)
                        }
                    }
                }
                .frame(maxWidth: 640)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func refresh() {
        do {
            summaries = try libraryEnvironment.library.listSummaries()
            statusMessage = summaries.isEmpty
                ? "Library is empty."
                : "\(summaries.count) character(s) in library."
        } catch {
            statusMessage = "Failed to load library: \(error.localizedDescription)"
        }
    }

    private func seedSamplesIfEmpty() {
        do {
            if try libraryEnvironment.library.count() == 0 {
                for sample in SampleCharacters.makeAll() {
                    try libraryEnvironment.library.save(sample)
                }
                statusMessage = "Seeded sample SR4 / SR5 / SR6 characters."
            } else {
                // Still allow adding samples only when empty to avoid duplicates of fixed IDs.
                statusMessage = "Library already has characters. Use Import for new runners."
            }
            refresh()
        } catch {
            statusMessage = "Seed failed: \(error.localizedDescription)"
        }
    }

    private func deleteCharacter(_ id: UUID) {
        do {
            try libraryEnvironment.library.delete(id: id)
            if selectedCharacterID == id { selectedCharacterID = nil }
            refresh()
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(LibraryEnvironment.preview())
        .frame(width: 960, height: 640)
}
