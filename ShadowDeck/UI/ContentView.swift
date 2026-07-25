//
//  ContentView.swift
//  ShadowDeck
//
//  Root window: library-aware shell. Full management UI arrives in later phases.
//

import SwiftUI

struct ContentView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @State private var summaries: [CharacterSummary] = []
    @State private var statusMessage: String?

    var body: some View {
        NavigationSplitView {
            List {
                Section("Library") {
                    Label {
                        Text("Characters")
                    } icon: {
                        Image(systemName: "person.3")
                    }
                    .badge(summaries.count)

                    Button {
                        seedSamplesIfEmpty()
                    } label: {
                        Label("Load Sample Runners", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                Section("Create") {
                    Label("New Character", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            .listStyle(.sidebar)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                ContentUnavailableView {
                    Label("ShadowDeck", systemImage: "person.crop.rectangle.stack")
                } description: {
                    Text("App-managed character library with portable .shadowdeck export.")
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 480)
                }

                if let error = libraryEnvironment.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 480)
                }

                if !summaries.isEmpty {
                    GroupBox("Library (\(summaries.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(summaries) { summary in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(summary.displayTitle)
                                            .font(.headline)
                                        Text("\(summary.editionRaw) · \(summary.metatypeRaw.capitalized)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if summary.hasAvatar {
                                        Image(systemName: "person.crop.square")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .frame(maxWidth: 480, alignment: .leading)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("ShadowDeck")
        .onAppear { refresh() }
    }

    private func refresh() {
        do {
            summaries = try libraryEnvironment.library.listSummaries()
            statusMessage = summaries.isEmpty
                ? "Library is empty. Load sample runners to exercise persistence."
                : "Loaded \(summaries.count) character(s) from SwiftData."
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
                statusMessage = "Library already has characters."
            }
            refresh()
        } catch {
            statusMessage = "Seed failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(LibraryEnvironment.preview())
        .frame(width: 900, height: 600)
}
