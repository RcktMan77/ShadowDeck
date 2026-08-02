//
//  MagicManagementView.swift
//  ShadowDeck
//
//  Phase 6–7 — spells, adept powers (catalog), and complex forms.
//

import SwiftUI

struct MagicManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void
    var onStatus: ((String) -> Void)?

    @State private var isAddingSpell = false
    @State private var showPowerCatalog = false
    @State private var isCustomPower = false
    @State private var isAddingForm = false
    @State private var draftName = ""
    @State private var draftCategory = ""
    @State private var draftLevel = 1
    @State private var draftModifiers: [StatModifier] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Magic & Resonance")
                            .font(.title2.weight(.semibold))
                        Text(character.awakened.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Look up", systemImage: "book.pages") {
                        RulesReferenceOpener.request(query: "magic", character: character)
                    }
                    .help("Open Rules Reference for Drain, spirits, adepts, and astral topics (⌘R)")
                }

                powersSection
                spellsSection
                complexFormsSection
            }
            .padding(20)
        }
        .sheet(isPresented: $isAddingSpell) { addNamedSheet(title: "Add Spell", categoryField: true) { name, cat in
            character.spells.append(
                SpellInstance(
                    catalogKey: ManagementSupport.catalogKey(from: name),
                    name: name,
                    category: cat
                )
            )
            onPersist()
        }
        }
        .sheet(isPresented: $showPowerCatalog) {
            CatalogBrowserView(
                title: "Add Adept Power",
                kinds: [.adeptPower],
                onPick: { entry in
                    addPowerFromCatalog(entry)
                    showPowerCatalog = false
                },
                onCustom: {
                    showPowerCatalog = false
                    isCustomPower = true
                },
                onCancel: { showPowerCatalog = false }
            )
        }
        .sheet(isPresented: $isCustomPower) { addPowerSheet }
        .sheet(isPresented: $isAddingForm) { addNamedSheet(title: "Add Complex Form", categoryField: false) { name, _ in
            character.complexForms.append(
                ComplexFormInstance(
                    catalogKey: ManagementSupport.catalogKey(from: name),
                    name: name
                )
            )
            onPersist()
        }
        }
    }

    private var powersSection: some View {
        section("Adept Powers", add: { showPowerCatalog = true }) {
            if character.adeptPowers.isEmpty {
                Text("No adept powers. Browse the catalog or add a custom power.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(character.adeptPowers.sorted { $0.name < $1.name }) { power in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(power.name)
                                .font(.body.weight(.medium))
                            Text("PP \(formatPP(power.powerPointCost))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !power.modifiers.isEmpty {
                                Text(power.modifiers.map(\.summary).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("Lv")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        StepperControl(value: power.level, range: 1...6) { lv in
                            updatePower(id: power.id) { $0.level = lv }
                            onStatus?("\(power.name) level \(lv) — modifiers scale with level.")
                        }
                        Button(role: .destructive) {
                            character.adeptPowers.removeAll { $0.id == power.id }
                            onPersist()
                            onStatus?("\(power.name) removed.")
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var spellsSection: some View {
        section("Spells", add: { isAddingSpell = true }) {
            if character.spells.isEmpty {
                Text("No spells.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(character.spells.sorted { $0.name < $1.name }) { spell in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spell.name)
                                .font(.body.weight(.medium))
                            if !spell.category.isEmpty {
                                Text(spell.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            character.spells.removeAll { $0.id == spell.id }
                            onPersist()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var complexFormsSection: some View {
        section("Complex Forms", add: { isAddingForm = true }) {
            if character.complexForms.isEmpty {
                Text("No complex forms.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(character.complexForms.sorted { $0.name < $1.name }) { form in
                    HStack {
                        Text(form.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button(role: .destructive) {
                            character.complexForms.removeAll { $0.id == form.id }
                            onPersist()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        add: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Add", systemImage: "plus.circle", action: add)
                    .controlSize(.small)
            }
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.05))
                )
        }
    }

    private func addNamedSheet(
        title: String,
        categoryField: Bool,
        onAdd: @escaping (String, String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            if categoryField {
                TextField("Category (optional)", text: $draftCategory)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    draftName = ""
                    draftCategory = ""
                    isAddingSpell = false
                    isAddingForm = false
                }
                Button("Add") {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    onAdd(name, draftCategory.trimmingCharacters(in: .whitespacesAndNewlines))
                    draftName = ""
                    draftCategory = ""
                    isAddingSpell = false
                    isAddingForm = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var addPowerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Adept Power")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Level")
                Spacer()
                StepperControl(value: draftLevel, range: 1...6) { draftLevel = $0 }
            }
            Text("Optional modifiers apply on the Summary sheet (scales with level when ×R).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ModifierDraftEditor(modifiers: $draftModifiers)
            HStack {
                Spacer()
                Button("Cancel") {
                    isCustomPower = false
                    draftName = ""
                    draftModifiers = []
                }
                Button("Add") {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let catalogMods = CatalogLookup.modifiers(named: name)
                    let mods = draftModifiers.isEmpty ? catalogMods : draftModifiers
                    character.adeptPowers.append(
                        AdeptPowerInstance(
                            catalogKey: ManagementSupport.catalogKey(from: name),
                            name: name,
                            level: draftLevel,
                            powerPointCost: Decimal(draftLevel),
                            notes: "Custom",
                            modifiers: mods
                        )
                    )
                    onPersist()
                    onStatus?("Added power \(name).")
                    draftName = ""
                    draftLevel = 1
                    draftModifiers = []
                    isCustomPower = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func addPowerFromCatalog(_ entry: CatalogEntry) {
        let level = 1
        let ppText = entry.notes.replacingOccurrences(of: "PP ", with: "")
        let pp = ManagementSupport.parsePowerPointCost(ppText.isEmpty ? "1" : ppText, level: level)
        character.adeptPowers.append(
            AdeptPowerInstance(
                catalogKey: ManagementSupport.catalogKey(from: entry.name),
                name: entry.name,
                level: level,
                powerPointCost: pp,
                notes: [
                    entry.category,
                    entry.notes,
                    entry.source.isEmpty ? nil : "\(entry.source) p.\(entry.page)"
                ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                modifiers: ManagementSupport.instanceModifiers(from: entry)
            )
        )
        onPersist()
        let modNote = entry.modifiers.isEmpty
            ? ""
            : " Mods: " + entry.modifiers.map(\.summary).joined(separator: ", ") + "."
        onStatus?("Added \(entry.name).\(modNote)")
    }

    private func updatePower(id: UUID, mutate: (inout AdeptPowerInstance) -> Void) {
        guard let idx = character.adeptPowers.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.adeptPowers[idx])
        onPersist()
    }

    private func formatPP(_ value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value)
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "\(value)"
    }
}
