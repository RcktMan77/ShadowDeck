//
//  ContentView.swift
//  ShadowDeck
//
//  Root window content. Expanded in later phases with character list,
// generation wizard, and at-a-glance summary.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Section("Library") {
                    Label("Characters", systemImage: "person.3")
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                Section("Create") {
                    Label("New Character", systemImage: "plus.circle")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .listStyle(.sidebar)
        } detail: {
            ContentUnavailableView {
                Label("ShadowDeck", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("Shadowrun character creation and campaign management for 4th, 5th, and 6th edition.")
            } actions: {
                Text("Phase 0 foundation — ready for domain models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("ShadowDeck")
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
