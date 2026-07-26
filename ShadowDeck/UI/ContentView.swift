//
//  ContentView.swift
//  ShadowDeck
//
//  Root window: library list, at-a-glance summary, import, and generation.
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
            if newValue == .characters {
                // Stay on summary if a character is selected; refresh list data.
                refresh()
            } else {
                selectedCharacterID = nil
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .importCharacter:
            ImportView()
                .onDisappear { refresh() }
        case .newCharacter:
            GenerationWizardView {
                selection = .characters
                refresh()
            }
        case .characters, .none:
            if let id = selectedCharacterID {
                CharacterAtAGlanceView(
                    characterID: id,
                    onBack: {
                        selectedCharacterID = nil
                        refresh()
                    },
                    onDeleted: {
                        selectedCharacterID = nil
                        refresh()
                    }
                )
            } else {
                charactersLibrary
            }
        }
    }

    private var charactersLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Character Library")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                Button("Load Samples", systemImage: "tray.and.arrow.down") { seedSamplesIfEmpty() }
                Button("New Character", systemImage: "plus.circle") {
                    selection = .newCharacter
                }
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
                    Text("Create a runner with the generation wizard, import Chummer, or load samples.")
                } actions: {
                    Button("New Character") { selection = .newCharacter }
                    Button("Import…") { selection = .importCharacter }
                    Button("Load Samples") { seedSamplesIfEmpty() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a runner for the at-a-glance summary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List(summaries, selection: $selectedCharacterID) { summary in
                    HStack(spacing: 12) {
                        Image(systemName: summary.hasAvatar ? "person.crop.rectangle.fill" : "person.crop.rectangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.displayTitle)
                                .font(.headline)
                            Text("\(summary.editionRaw) · \(summary.metatypeRaw.capitalized) · \(summary.concept.isEmpty ? "—" : summary.concept)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .tag(summary.id)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Open Summary") {
                            selectedCharacterID = summary.id
                        }
                        Button("Delete", role: .destructive) {
                            deleteCharacter(summary.id)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: 720)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func refresh() {
        do {
            summaries = try libraryEnvironment.library.listSummaries()
            if selectedCharacterID != nil,
               !summaries.contains(where: { $0.id == selectedCharacterID })
            {
                selectedCharacterID = nil
            }
            if selectedCharacterID == nil {
                statusMessage = summaries.isEmpty
                    ? "Library is empty."
                    : "\(summaries.count) character(s) in library."
            }
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
                statusMessage = "Library already has characters. Use New Character or Import."
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
        .frame(width: 1100, height: 720)
}
