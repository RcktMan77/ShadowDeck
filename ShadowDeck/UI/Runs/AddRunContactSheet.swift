//
//  AddRunContactSheet.swift
//  ShadowDeck
//
//  Pick a contact from a character’s list and attach them to a run.
//

import SwiftUI

struct AddRunContactSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let characterSummaries: [CharacterSummary]
    var onCancel: () -> Void
    var onAdd: (RunContactLink) -> Void

    @State private var role: RunContactRole = .johnson
    @State private var selectedCharacterID: UUID?
    @State private var contacts: [Contact] = []
    @State private var selectedContactID: UUID?
    @State private var errorMessage: String?

    private var selectedContact: Contact? {
        contacts.first { $0.id == selectedContactID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add from character contacts")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedContact == nil)
            }
            .padding()

            Divider()

            Form {
                Picker("Role on this run", selection: $role) {
                    ForEach(RunContactRole.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Character", selection: $selectedCharacterID) {
                    Text("Select…").tag(Optional<UUID>.none)
                    ForEach(characterSummaries) { summary in
                        Text(summary.displayTitle).tag(Optional(summary.id))
                    }
                }
                .onChange(of: selectedCharacterID) { _, newID in
                    loadContacts(for: newID)
                }

                if selectedCharacterID != nil {
                    if contacts.isEmpty {
                        Text("This character has no contacts yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Contact", selection: $selectedContactID) {
                            Text("Select…").tag(Optional<UUID>.none)
                            ForEach(contacts) { contact in
                                Text(contactRowTitle(contact)).tag(Optional(contact.id))
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 360)
        .onAppear {
            if selectedCharacterID == nil {
                selectedCharacterID = characterSummaries.first?.id
                loadContacts(for: selectedCharacterID)
            }
        }
    }

    private func contactRowTitle(_ contact: Contact) -> String {
        let role = contact.role.trimmingCharacters(in: .whitespacesAndNewlines)
        if role.isEmpty { return contact.name }
        return "\(contact.name) (\(role))"
    }

    private func loadContacts(for characterID: UUID?) {
        selectedContactID = nil
        contacts = []
        guard let characterID else { return }
        do {
            let character = try libraryEnvironment.library.require(characterID)
            contacts = character.contacts.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add() {
        guard let characterID = selectedCharacterID,
              let contact = selectedContact
        else { return }
        let link = RunContactLink(
            role: role,
            sourceCharacterID: characterID,
            contactID: contact.id,
            displayName: contact.name,
            displayRoleLabel: contact.role.isEmpty ? nil : contact.role
        )
        onAdd(link)
    }
}
