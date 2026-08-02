//
//  AddRunContactSheet.swift
//  ShadowDeck
//
//  Pick one or more contacts from character lists and attach them to a run.
//  Supports multi-select and staging across characters before a single Add.
//

import SwiftUI

struct AddRunContactSheet: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let characterSummaries: [CharacterSummary]
    /// Linked pairs already on the run — cannot be staged again.
    var existingLinkedKeys: Set<String> = []
    var onCancel: () -> Void
    /// Called once with every staged link when the user confirms Add.
    var onAdd: ([RunContactLink]) -> Void

    @State private var role: RunContactRole = .johnson
    @State private var selectedCharacterID: UUID?
    @State private var contacts: [Contact] = []
    /// Staged links (may come from several characters / roles).
    @State private var staged: [RunContactLink] = []
    @State private var errorMessage: String?

    private var selectedCharacterTitle: String {
        characterSummaries.first { $0.id == selectedCharacterID }?.displayTitle ?? "Character"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                roleAndCharacter
                contactChecklist
                stagedSection
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            if selectedCharacterID == nil {
                selectedCharacterID = characterSummaries.first?.id
                loadContacts(for: selectedCharacterID)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Add from character contacts")
                .font(.headline)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(addButtonTitle) { commit() }
                .keyboardShortcut(.defaultAction)
                .disabled(staged.isEmpty)
        }
        .padding()
    }

    private var addButtonTitle: String {
        staged.isEmpty ? "Add" : "Add \(staged.count)"
    }

    private var roleAndCharacter: some View {
        Group {
            Picker("Role on this run", selection: $role) {
                ForEach(RunContactRole.allCases) { r in
                    Text(r.displayName).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .help("Applied to contacts you select next. Change role between picks if needed.")

            Picker("Character", selection: $selectedCharacterID) {
                Text("Select…").tag(Optional<UUID>.none)
                ForEach(characterSummaries) { summary in
                    Text(summary.displayTitle).tag(Optional(summary.id))
                }
            }
            .onChange(of: selectedCharacterID) { _, newID in
                loadContacts(for: newID)
            }

            Text("Select contacts below (role applies to new picks). Switch character to stage more, then Add once.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var contactChecklist: some View {
        if selectedCharacterID != nil {
            if contacts.isEmpty {
                Text("This character has no contacts yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Contacts — \(selectedCharacterTitle)") {
                    ForEach(contacts) { contact in
                        contactToggleRow(contact)
                    }
                }
            }
        }
    }

    private func contactToggleRow(_ contact: Contact) -> some View {
        let key = linkKey(characterID: selectedCharacterID, contactID: contact.id)
        let alreadyOnRun = key.map { existingLinkedKeys.contains($0) } ?? false
        let isStaged = isStagedContact(contact.id)

        return Toggle(isOn: Binding(
            get: { isStaged },
            set: { on in
                if on {
                    stage(contact)
                } else {
                    unstage(contactID: contact.id)
                }
            }
        )) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.body.weight(.medium))
                    let roleText = contact.role.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !roleText.isEmpty {
                        Text(roleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if alreadyOnRun {
                    Text("On run")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if isStaged, let stagedRole = stagedRole(for: contact.id) {
                    Text(stagedRole.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
        .disabled(alreadyOnRun && !isStaged)
        .help(alreadyOnRun && !isStaged ? "Already linked on this run" : "Toggle to stage with the selected role")
    }

    @ViewBuilder
    private var stagedSection: some View {
        if !staged.isEmpty {
            Section("Ready to add (\(staged.count))") {
                ForEach(staged) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.displayName)
                                .font(.body.weight(.medium))
                            Text(stagedSubtitle(link))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(link.role.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        Button {
                            staged.removeAll { $0.id == link.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from staging")
                    }
                }
            }
        }
    }

    // MARK: - Staging

    private func linkKey(characterID: UUID?, contactID: UUID?) -> String? {
        guard let characterID, let contactID else { return nil }
        return "\(characterID.uuidString)|\(contactID.uuidString)"
    }

    private func isStagedContact(_ contactID: UUID) -> Bool {
        guard let characterID = selectedCharacterID else { return false }
        return staged.contains {
            $0.sourceCharacterID == characterID && $0.contactID == contactID
        }
    }

    private func stagedRole(for contactID: UUID) -> RunContactRole? {
        guard let characterID = selectedCharacterID else { return nil }
        return staged.first {
            $0.sourceCharacterID == characterID && $0.contactID == contactID
        }?.role
    }

    private func stage(_ contact: Contact) {
        guard let characterID = selectedCharacterID else { return }
        // Replace if re-staging the same contact (e.g. role change).
        staged.removeAll {
            $0.sourceCharacterID == characterID && $0.contactID == contact.id
        }
        let link = RunContactLink(
            role: role,
            sourceCharacterID: characterID,
            contactID: contact.id,
            displayName: contact.name,
            displayRoleLabel: contact.role.isEmpty ? nil : contact.role
        )
        staged.append(link)
    }

    private func unstage(contactID: UUID) {
        guard let characterID = selectedCharacterID else { return }
        staged.removeAll {
            $0.sourceCharacterID == characterID && $0.contactID == contactID
        }
    }

    private func stagedSubtitle(_ link: RunContactLink) -> String {
        let source = characterSummaries.first { $0.id == link.sourceCharacterID }?.displayTitle
        if let source {
            return "From \(source)"
        }
        return "Linked contact"
    }

    private func loadContacts(for characterID: UUID?) {
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

    private func commit() {
        guard !staged.isEmpty else { return }
        onAdd(staged)
    }
}

// MARK: - Existing-link keys

enum RunContactLinkKey {
    /// Stable key for “already on this run” checks (linked contacts only).
    static func make(sourceCharacterID: UUID, contactID: UUID) -> String {
        "\(sourceCharacterID.uuidString)|\(contactID.uuidString)"
    }

    static func set(from links: [RunContactLink]) -> Set<String> {
        Set(links.compactMap { link in
            guard let c = link.sourceCharacterID, let id = link.contactID else { return nil }
            return make(sourceCharacterID: c, contactID: id)
        })
    }
}
