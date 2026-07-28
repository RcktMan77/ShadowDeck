//
//  ContactsManagementView.swift
//  ShadowDeck
//
//  Fully editable contact profiles (name, role, metatype, location, notes, …).
//

import SwiftUI

struct ContactsManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void

    @State private var showCatalog = false
    @State private var isAdding = false
    @State private var draftName = ""
    @State private var draftRole = ""
    @State private var expandedID: UUID?
    /// Local RTF drafts so typing does not thrash persistence every keystroke.
    @State private var notesDrafts: [UUID: String] = [:]

    var body: some View {
        ManagementListChrome(
            title: "Contacts",
            subtitle: "L = Loyalty, C = Connection. Expand a contact to edit every field. Notes support rich text.",
            onAdd: { showCatalog = true },
            addLabel: "Add Contact"
        ) {
            if character.contacts.isEmpty {
                ManagementEmptyState(
                    title: "No Contacts",
                    systemImage: "person.2",
                    message: "Add a contact or re-import from Chummer to pull notes and profile details."
                )
            } else {
                List {
                    ForEach(character.contacts.sorted { $0.name < $1.name }) { contact in
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
        .onAppear {
            for c in character.contacts {
                if notesDrafts[c.id] == nil {
                    notesDrafts[c.id] = c.notes
                }
            }
        }
    }

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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name.isEmpty ? "Unnamed contact" : contact.name)
                        .font(.body.weight(.medium))
                    Text(contactSubtitle(contact))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text("L\(contact.loyalty) · C\(contact.connection)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help("Loyalty (how much they risk for you) · Connection (how well-placed they are)")
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

    /// Dense two-column form: labels inline, paired fields share rows.
    private func compactEditor(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            // Notes: shorter editor, label + save on one bar
            HStack {
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Notes") {
                    commitNotes(for: contact.id)
                }
                .controlSize(.mini)
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

    private func contactSubtitle(_ c: Contact) -> String {
        var parts: [String] = []
        if !c.role.isEmpty { parts.append(c.role) }
        if let meta = c.metatype, !meta.isEmpty { parts.append(meta) }
        if let loc = c.location, !loc.isEmpty { parts.append(loc) }
        return parts.isEmpty ? "Expand to edit details" : parts.joined(separator: " · ")
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Contact")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            TextField("Role", text: $draftRole)
                .textFieldStyle(.roundedBorder)
            Text("You can fill metatype, location, notes, and the rest after adding.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { isAdding = false }
                Button("Add") {
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
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Bindings

    private func stringBinding(id: UUID, keyPath: WritableKeyPath<Contact, String>) -> Binding<String> {
        Binding(
            get: {
                character.contacts.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
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
                get(character.contacts.first(where: { $0.id == id }) ?? Contact(name: "")) ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                update(id: id) { set(&$0, trimmed.isEmpty ? nil : trimmed) }
            }
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
