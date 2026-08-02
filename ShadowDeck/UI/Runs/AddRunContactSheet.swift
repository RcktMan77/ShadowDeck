//
//  AddRunContactSheet.swift
//  ShadowDeck
//
//  Pick one or more contacts from character lists and attach them to a run.
//  Supports multi-select and staging across characters before a single Add.
//
//  Johnson / Fixer / Target / Other are **run roles** assigned when you stage a
//  contact — not filters on the character’s contact list.
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

    /// Role applied to the **next** contact(s) you check. Not a list filter.
    @State private var nextRole: RunContactRole = .johnson
    @State private var selectedCharacterID: UUID?
    @State private var contacts: [Contact] = []
    /// Live filter on the loaded character’s contact list (name + contact-sheet role).
    @State private var contactSearch: String = ""
    /// Staged links (may come from several characters / roles).
    @State private var staged: [RunContactLink] = []
    @State private var errorMessage: String?

    private var selectedCharacterTitle: String {
        characterSummaries.first { $0.id == selectedCharacterID }?.displayTitle ?? "Character"
    }

    /// Contacts matching the live search term (empty query → full list).
    private var filteredContacts: [Contact] {
        let query = contactSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contacts }
        return contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(query)
                || contact.role.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                characterPicker
                nextRoleSection
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
        .frame(width: 500, height: 560)
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
            AppChromeButton.title("Cancel", help: "Close without adding") {
                onCancel()
            }
            AppChromeButton.title(
                addButtonTitle,
                help: "Add staged people to this run",
                style: .prominent,
                isEnabled: !staged.isEmpty,
                keyEquivalent: "\r"
            ) {
                commit()
            }
        }
        .padding()
    }

    private var addButtonTitle: String {
        staged.isEmpty ? "Add to run" : "Add \(staged.count) to run"
    }

    private var characterPicker: some View {
        Section {
            Picker("Whose contacts", selection: $selectedCharacterID) {
                Text("Select…").tag(Optional<UUID>.none)
                ForEach(characterSummaries) { summary in
                    Text(summary.displayTitle).tag(Optional(summary.id))
                }
            }
            .onChange(of: selectedCharacterID) { _, newID in
                contactSearch = ""
                loadContacts(for: newID)
            }
        } footer: {
            Text("Shows that character’s full contact list. Switch characters to stage people from more than one runner.")
                .font(.caption)
        }
    }

    private var nextRoleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Role for next picks")
                    .font(.subheadline.weight(.semibold))
                Text("Not a filter — this is the job role (Johnson / Fixer / Target / Other) stamped onto each contact you check below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Role for next picks", selection: $nextRole) {
                    ForEach(RunContactRole.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Assigns this run role when you check a contact. Does not filter the list.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            Text("Multi-add: set Johnson → check your Johnson; set Fixer → check your fixer; then Add once. Fix mistakes with the role menu in Ready to add.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var contactChecklist: some View {
        if selectedCharacterID != nil {
            if contacts.isEmpty {
                Section("Contacts — \(selectedCharacterTitle)") {
                    Text("This character has no contacts yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("Search contacts", text: $contactSearch, prompt: Text("Name or contact role…"))
                        .textFieldStyle(.roundedBorder)
                        #if os(macOS)
                        .onSubmit {} // live filter; Enter does not commit the sheet
                        #endif
                        .help("Narrow the list by name or contact-sheet role")

                    if filteredContacts.isEmpty {
                        Text(emptyFilterMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(filteredContacts) { contact in
                            contactToggleRow(contact)
                        }
                    }
                } header: {
                    Text(contactsHeaderTitle)
                } footer: {
                    Text("Check to stage with “\(nextRole.displayName)”. Uncheck to remove from the list below. Free-text under a name is their contact-sheet role, not the run role.")
                        .font(.caption)
                }
            }
        }
    }

    private var contactsHeaderTitle: String {
        let total = contacts.count
        let shown = filteredContacts.count
        let query = contactSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return "Contacts — \(selectedCharacterTitle) (\(total))"
        }
        return "Contacts — \(selectedCharacterTitle) (\(shown) of \(total))"
    }

    private var emptyFilterMessage: String {
        let q = contactSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return "No contacts."
        }
        return "No contacts match “\(q)”."
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
                    let sheetRole = contact.role.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sheetRole.isEmpty {
                        Text("Contact: \(sheetRole)")
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
                    Text("→ \(stagedRole.displayName)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
        .disabled(alreadyOnRun && !isStaged)
        .help(
            alreadyOnRun && !isStaged
                ? "Already linked on this run"
                : "Stage as \(nextRole.displayName) on this job"
        )
    }

    @ViewBuilder
    private var stagedSection: some View {
        if !staged.isEmpty {
            Section {
                ForEach(Array(staged.indices), id: \.self) { index in
                    stagedRow(index: index)
                }
            } header: {
                Text("Ready to add (\(staged.count))")
            } footer: {
                Text("Each person gets their own run role. Adjust with the menu if you picked the wrong one.")
                    .font(.caption)
            }
        }
    }

    private func stagedRow(index: Int) -> some View {
        let link = staged[index]
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.displayName)
                    .font(.body.weight(.medium))
                Text(stagedSubtitle(link))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Picker("Run role", selection: roleBinding(at: index)) {
                ForEach(RunContactRole.allCases) { r in
                    Text(r.displayName).tag(r)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 120)
            .help("Role on this job")

            Button {
                staged.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from staging")
        }
    }

    private func roleBinding(at index: Int) -> Binding<RunContactRole> {
        Binding(
            get: {
                staged.indices.contains(index) ? staged[index].role : .other
            },
            set: { newRole in
                guard staged.indices.contains(index) else { return }
                staged[index].role = newRole
            }
        )
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
        // Replace if re-staging the same contact (e.g. next-role change then re-check).
        staged.removeAll {
            $0.sourceCharacterID == characterID && $0.contactID == contact.id
        }
        let link = RunContactLink(
            role: nextRole,
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
        var parts: [String] = []
        if let source {
            parts.append("From \(source)")
        }
        let sheetRole = link.displayRoleLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sheetRole.isEmpty {
            parts.append("contact: \(sheetRole)")
        }
        return parts.isEmpty ? "Linked contact" : parts.joined(separator: " · ")
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
