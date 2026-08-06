//
//  ContactsManagementView.swift
//  ShadowDeck
//
//  Enriched contacts: tags, favor standing, interaction log, search/filter.
//

import SwiftUI

struct ContactsManagementView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    @Binding var character: Character
    var onPersist: () -> Void

    @State private var showCatalog = false
    @State private var isAdding = false
    @State private var draftName = ""
    @State private var draftRole = ""
    @State private var expandedID: UUID?
    /// Local RTF drafts so typing does not thrash persistence every keystroke.
    @State private var notesDrafts: [UUID: String] = [:]
    @State private var searchQuery = ""
    @State private var pendingFavorOnly = false
    @State private var tagFilter: String?
    @State private var newTagDraft = ""
    @State private var interactionTargetID: UUID?
    @State private var interactionPendingDelete: (contactID: UUID, entryID: UUID)?
    @State private var runSummaries: [RunSummary] = []

    private var filteredContacts: [Contact] {
        ContactHelpers.filter(
            character.contacts,
            query: searchQuery,
            pendingFavorOnly: pendingFavorOnly,
            tag: tagFilter
        )
    }

    private var allTagsInUse: [String] {
        let set = Set(character.contacts.flatMap(\.tags))
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        ManagementListChrome(
            title: "Contacts",
            subtitle: "L = Loyalty, C = Connection. Tags, favors, and a dated interaction log stay on this runner. Expand a contact to edit.",
            onAdd: { showCatalog = true },
            addLabel: "Add Contact",
            onLookUp: {
                RulesReferenceOpener.request(query: "contact", character: character)
            },
            lookUpLabel: "Look up"
        ) {
            filterBar

            if character.contacts.isEmpty {
                ManagementEmptyState(
                    title: "No Contacts",
                    systemImage: "person.2",
                    message: "Add a contact or re-import from Chummer to pull notes and profile details."
                )
            } else if filteredContacts.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No contacts match the current search or filters.")
                } actions: {
                    Button("Clear Filters") {
                        searchQuery = ""
                        pendingFavorOnly = false
                        tagFilter = nil
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List {
                    ForEach(filteredContacts) { contact in
                        contactBlock(contact)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView(
                title: "Contact Role Archetype",
                kinds: [.contactRole],
                edition: character.edition,
                onPick: { entry in
                    draftRole = entry.name
                    draftName = ""
                    showCatalog = false
                    isAdding = true
                },
                onCustom: {
                    showCatalog = false
                    draftRole = ""
                    isAdding = true
                },
                onCancel: { showCatalog = false }
            )
        }
        .sheet(isPresented: $isAdding) {
            addSheet
        }
        .sheet(isPresented: Binding(
            get: { interactionTargetID != nil },
            set: { if !$0 { interactionTargetID = nil } }
        )) {
            if let contactID = interactionTargetID,
               let contact = character.contacts.first(where: { $0.id == contactID }) {
                ContactInteractionSheet(
                    contactName: contact.name.isEmpty ? "Contact" : contact.name,
                    runSummaries: runSummaries,
                    onCancel: { interactionTargetID = nil },
                    onSave: { entry, updateFavor in
                        update(id: contactID) { c in
                            c.addInteraction(entry, updateCurrentFavor: updateFavor)
                        }
                        interactionTargetID = nil
                    }
                )
            }
        }
        .confirmationDialog(
            "Delete this interaction?",
            isPresented: Binding(
                get: { interactionPendingDelete != nil },
                set: { if !$0 { interactionPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                if let pending = interactionPendingDelete {
                    update(id: pending.contactID) { $0.removeInteraction(id: pending.entryID) }
                }
                interactionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                interactionPendingDelete = nil
            }
        } message: {
            Text("This removes the log entry only. Current favor standing is unchanged.")
        }
        .onAppear {
            reloadRunSummaries()
            for c in character.contacts where notesDrafts[c.id] == nil {
                notesDrafts[c.id] = c.notes
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search name, role, or tags…", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 480)

            HStack(spacing: 10) {
                Toggle("Has favor", isOn: $pendingFavorOnly)
                    .toggleStyle(.checkbox)
                    .help("Show only contacts with a current favor standing")

                Picker("Tag", selection: $tagFilter) {
                    Text("All tags").tag(Optional<String>.none)
                    ForEach(allTagsInUse, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
                .frame(maxWidth: 200)

                Spacer()
                Text("\(filteredContacts.count) of \(character.contacts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Row

    private func contactBlock(_ contact: Contact) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedID == contact.id },
                set: { open in
                    if !open, expandedID == contact.id {
                        commitNotes(for: contact.id)
                    }
                    expandedID = open ? contact.id : nil
                    if open, notesDrafts[contact.id] == nil {
                        notesDrafts[contact.id] = contact.notes
                    }
                }
            )
        ) {
            compactEditor(contact)
                .padding(.vertical, 4)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name.isEmpty ? "Unnamed contact" : contact.name)
                        .font(.body.weight(.medium))
                    Text(contactSubtitle(contact))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !contact.tags.isEmpty {
                        ContactTagChips(tags: contact.tags)
                    }
                    HStack(spacing: 8) {
                        if contact.favorState.hasPendingFavor {
                            ContactFavorBadge(state: contact.favorState, oneTime: contact.favorOneTime)
                        }
                        Text(ContactHelpers.relationshipStatus(for: contact).displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let last = contact.lastContactAt {
                            Text("Last \(last.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text("L\(contact.loyalty) · C\(contact.connection)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Loyalty · Connection")
                Button(role: .destructive) {
                    character.contacts.removeAll { $0.id == contact.id }
                    notesDrafts[contact.id] = nil
                    onPersist()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Detail editor

    private func compactEditor(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Identity + ratings
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    compactField("Name", text: stringBinding(id: contact.id, keyPath: \.name))
                    compactField("Role", text: stringBinding(id: contact.id, keyPath: \.role))
                }
                GridRow {
                    compactField(
                        "Type",
                        text: optionalStringBinding(id: contact.id, get: { $0.contactType }, set: { $0.contactType = $1 })
                    )
                    compactField(
                        "Metatype",
                        text: optionalStringBinding(id: contact.id, get: { $0.metatype }, set: { $0.metatype = $1 })
                    )
                }
                GridRow {
                    compactField(
                        "Gender",
                        text: optionalStringBinding(id: contact.id, get: { $0.gender }, set: { $0.gender = $1 })
                    )
                    compactField(
                        "Age",
                        text: optionalStringBinding(id: contact.id, get: { $0.age }, set: { $0.age = $1 })
                    )
                }
                GridRow {
                    compactField(
                        "Location",
                        text: optionalStringBinding(id: contact.id, get: { $0.location }, set: { $0.location = $1 })
                    )
                    compactField(
                        "Payment",
                        text: optionalStringBinding(id: contact.id, get: { $0.preferredPayment }, set: { $0.preferredPayment = $1 })
                    )
                }
                GridRow {
                    compactField(
                        "Hobbies / Vice",
                        text: optionalStringBinding(id: contact.id, get: { $0.hobbiesVice }, set: { $0.hobbiesVice = $1 })
                    )
                    compactField(
                        "Personal life",
                        text: optionalStringBinding(id: contact.id, get: { $0.personalLife }, set: { $0.personalLife = $1 })
                    )
                }
                GridRow {
                    HStack(spacing: 8) {
                        Text("L")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .help("Loyalty")
                        StepperControl(value: contact.loyalty, range: 1...6) { v in
                            update(id: contact.id) { $0.loyalty = v }
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text("C")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .help("Connection")
                        StepperControl(value: contact.connection, range: 1...12) { v in
                            update(id: contact.id) { $0.connection = v }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            tagsEditor(contact)
            favorEditor(contact)
            lastContactRow(contact)
            notesEditor(contact)
            interactionLogSection(contact)
        }
    }

    private func tagsEditor(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !contact.tags.isEmpty {
                ContactTagChips(tags: contact.tags) { tag in
                    update(id: contact.id) { c in
                        c.tags.removeAll { $0 == tag }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add tag…", text: $newTagDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onSubmit { addTag(to: contact.id) }
                Button("Add") { addTag(to: contact.id) }
                    .disabled(ContactHelpers.normalizeTag(newTagDraft) == nil)
            }
            // Suggestions not already on the contact
            let suggestions = ContactHelpers.suggestedTags.filter { suggested in
                !contact.tags.contains { $0.caseInsensitiveCompare(suggested) == .orderedSame }
            }
            if !suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button(tag) {
                            update(id: contact.id) { c in
                                if !c.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                                    c.tags.append(tag)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    private func favorEditor(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current favor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Favor", selection: favorStateBinding(contact.id)) {
                ForEach(ContactFavorState.allCases) { state in
                    Text(state.displayName).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .help("Manual standing. Interaction log snapshots do not change this unless you opt in when adding an entry.")
            Toggle("One-time favor", isOn: favorOneTimeBinding(contact.id))
                .toggleStyle(.checkbox)
                .help("Mark when this standing is a single outstanding favor rather than an ongoing ledger")
        }
    }

    private func lastContactRow(_ contact: Contact) -> some View {
        HStack {
            Text("Last contact")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let last = contact.lastContactAt {
                Text(last.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(ContactHelpers.relationshipStatus(for: contact).displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Derived from loyalty and recency of last contact")
        }
    }

    private func notesEditor(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                AppChromeButton.title("Save Notes", help: "Save contact notes") {
                    commitNotes(for: contact.id)
                }
            }
            NotesEditor(
                text: Binding(
                    get: { notesDrafts[contact.id] ?? contact.notes },
                    set: { notesDrafts[contact.id] = $0 }
                ),
                onCommit: { commitNotes(for: contact.id) }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 110)
        }
    }

    private func interactionLogSection(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Interaction log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                AppChromeButton.title("Add Interaction…", help: "Log a contact interaction") {
                    interactionTargetID = contact.id
                }
            }

            let entries = contact.interactionLogNewestFirst
            if entries.isEmpty {
                Text("No interactions yet. Log a call, meet, or favor to track relationship history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption.weight(.semibold))
                                if let direction = entry.favorDirection, direction != .none {
                                    Text(direction.shortLabel)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(entry.summary)
                                .font(.callout)
                                .textSelection(.enabled)
                            if let runID = entry.relatedRunID {
                                Text(runTitle(for: runID))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 4)
                        Button(role: .destructive) {
                            interactionPendingDelete = (contact.id, entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this log entry")
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    // MARK: - Add contact sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Contact")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            TextField("Role", text: $draftRole)
                .textFieldStyle(.roundedBorder)
            Text("You can fill tags, favors, notes, and the rest after adding.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                AppChromeButton.title("Cancel", help: "Close without adding") { isAdding = false }
                AppChromeButton.title(
                    "Add",
                    help: "Add contact",
                    style: .prominent,
                    isEnabled: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    keyEquivalent: "\r"
                ) {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let contact = Contact(
                        name: name,
                        role: draftRole.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    character.contacts.append(contact)
                    notesDrafts[contact.id] = ""
                    onPersist()
                    draftName = ""
                    draftRole = ""
                    isAdding = false
                    expandedID = contact.id
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Helpers

    private func contactSubtitle(_ c: Contact) -> String {
        var parts: [String] = []
        if !c.role.isEmpty { parts.append(c.role) }
        if let meta = c.metatype, !meta.isEmpty { parts.append(meta) }
        if let loc = c.location, !loc.isEmpty { parts.append(loc) }
        return parts.isEmpty ? "Expand to edit details" : parts.joined(separator: " · ")
    }

    private func addTag(to id: UUID) {
        guard let tag = ContactHelpers.normalizeTag(newTagDraft) else { return }
        update(id: id) { c in
            if !c.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                c.tags.append(tag)
            }
        }
        newTagDraft = ""
    }

    private func runTitle(for id: UUID) -> String {
        if let summary = runSummaries.first(where: { $0.id == id }) {
            return "Run: \(summary.title.isEmpty ? "Untitled" : summary.title)"
        }
        return "Run: (deleted or missing)"
    }

    private func reloadRunSummaries() {
        runSummaries = (try? libraryEnvironment.runLibrary.listSummaries()) ?? []
    }

    private func compactField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }

    // MARK: - Bindings

    private func stringBinding(id: UUID, keyPath: WritableKeyPath<Contact, String>) -> Binding<String> {
        Binding(
            get: {
                character.contacts.first { $0.id == id }?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                update(id: id) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func optionalStringBinding(
        id: UUID,
        get: @escaping (Contact) -> String?,
        set: @escaping (inout Contact, String?) -> Void
    ) -> Binding<String> {
        Binding(
            get: {
                get(character.contacts.first { $0.id == id } ?? Contact(name: "")) ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                update(id: id) { set(&$0, trimmed.isEmpty ? nil : trimmed) }
            }
        )
    }

    private func favorStateBinding(_ id: UUID) -> Binding<ContactFavorState> {
        Binding(
            get: { character.contacts.first { $0.id == id }?.favorState ?? .none },
            set: { v in update(id: id) { $0.favorState = v } }
        )
    }

    private func favorOneTimeBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { character.contacts.first { $0.id == id }?.favorOneTime ?? false },
            set: { v in update(id: id) { $0.favorOneTime = v } }
        )
    }

    private func commitNotes(for id: UUID) {
        guard let draft = notesDrafts[id] else { return }
        update(id: id) { $0.notes = draft }
    }

    private func update(id: UUID, mutate: (inout Contact) -> Void) {
        guard let idx = character.contacts.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.contacts[idx])
        onPersist()
    }
}

// MARK: - Small UI atoms

struct ContactFavorBadge: View {
    let state: ContactFavorState
    var oneTime: Bool = false

    var body: some View {
        if state.hasPendingFavor {
            Text(oneTime ? "\(state.shortLabel) · 1×" : state.shortLabel)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(background, in: Capsule())
                .foregroundStyle(foreground)
        }
    }

    private var background: Color {
        switch state {
        case .none: Color.clear
        case .owesMe: Color.green.opacity(0.16)
        case .iOweThem: Color.orange.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch state {
        case .none: .secondary
        case .owesMe: .green
        case .iOweThem: .orange
        }
    }
}

struct ContactTagChips: View {
    let tags: [String]
    var onRemove: ((String) -> Void)?

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption2.weight(.medium))
                        if let onRemove {
                            Button {
                                onRemove(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
                }
            }
        }
    }
}
