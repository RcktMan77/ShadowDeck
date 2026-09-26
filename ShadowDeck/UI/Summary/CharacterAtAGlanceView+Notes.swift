//
//  CharacterAtAGlanceView+Notes.swift
//  ShadowDeck
//
//  Notes editor on the play sheet. Same view as CharacterAtAGlanceView.
//

import SwiftUI

extension CharacterAtAGlanceView {
    func notesSection(_ c: Character) -> some View {
        sectionCard("Notes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mission logs & table notes — scroll inside the editor for long text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save Notes") {
                        commitNotesIfNeeded(force: true)
                    }
                    .controlSize(.small)
                }

                NotesEditor(text: $notesDraft) {
                    commitNotesIfNeeded()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
    }
}
