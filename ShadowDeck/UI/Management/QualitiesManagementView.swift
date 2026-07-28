//
//  QualitiesManagementView.swift
//  ShadowDeck
//
//  Phase 6–7 — qualities with optional stat modifiers from catalog / custom.
//

import SwiftUI

struct QualitiesManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void
    var onStatus: ((String) -> Void)?

    @State private var showCatalog = false
    @State private var isCustom = false
    @State private var draftName = ""
    @State private var draftKind: QualityKind = .positive
    @State private var draftKarma = 5
    @State private var draftModifiers: [StatModifier] = []

    var body: some View {
        ManagementListChrome(
            title: "Qualities",
            subtitle: "Catalog qualities may include attribute/skill modifiers applied on Summary.",
            onAdd: { showCatalog = true },
            addLabel: "Add Quality"
        ) {
            if character.qualities.isEmpty {
                ManagementEmptyState(
                    title: "No Qualities",
                    systemImage: "star.circle",
                    message: "Add from the catalog or import from Chummer."
                )
            } else {
                List {
                    Section("Positive") {
                        ForEach(character.qualities.filter { $0.kind == .positive }) { q in
                            qualityRow(q)
                        }
                    }
                    Section("Negative") {
                        ForEach(character.qualities.filter { $0.kind == .negative }) { q in
                            qualityRow(q)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView(
                title: "Add Quality",
                kinds: [.quality],
                onPick: { entry in
                    addFromCatalog(entry)
                    showCatalog = false
                },
                onCustom: {
                    showCatalog = false
                    isCustom = true
                },
                onCancel: { showCatalog = false }
            )
        }
        .sheet(isPresented: $isCustom) {
            customSheet
        }
    }

    private func qualityRow(_ q: QualityInstance) -> some View {
        HStack {
            Image(systemName: q.kind == .positive ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(q.kind == .positive ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(q.name)
                    .font(.body.weight(.medium))
                Text("\(q.kind == .positive ? "Cost" : "Bonus") \(q.karmaValue) Karma")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !q.modifiers.isEmpty {
                    Text(q.modifiers.map(\.summary).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(2)
                }
            }
            Spacer()
            StepperControl(value: q.karmaValue, range: 0...50) { karma in
                update(id: q.id) { $0.karmaValue = karma }
            }
            Button(role: .destructive) {
                character.qualities.removeAll { $0.id == q.id }
                onPersist()
                onStatus?("\(q.name) removed.")
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Quality")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            Picker("Type", selection: $draftKind) {
                Text("Positive").tag(QualityKind.positive)
                Text("Negative").tag(QualityKind.negative)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Karma value")
                Spacer()
                StepperControl(value: draftKarma, range: 0...50) { draftKarma = $0 }
            }
            ModifierDraftEditor(modifiers: $draftModifiers)
            HStack {
                Spacer()
                Button("Cancel") { isCustom = false }
                Button("Add") {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    character.qualities.append(
                        QualityInstance(
                            catalogKey: ManagementSupport.catalogKey(from: name),
                            name: name,
                            kind: draftKind,
                            karmaValue: draftKarma,
                            notes: "Custom",
                            modifiers: draftModifiers
                        )
                    )
                    onPersist()
                    onStatus?("Added quality \(name).")
                    draftName = ""
                    draftModifiers = []
                    isCustom = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func addFromCatalog(_ entry: CatalogEntry) {
        let isPositive = !(entry.category.lowercased().contains("negative"))
        let karma = entry.karma ?? 0
        character.qualities.append(
            QualityInstance(
                catalogKey: ManagementSupport.catalogKey(from: entry.name),
                name: entry.name,
                kind: isPositive ? .positive : .negative,
                karmaValue: abs(karma),
                notes: entry.source.isEmpty ? "" : "\(entry.source) p.\(entry.page)",
                modifiers: ManagementSupport.instanceModifiers(from: entry)
            )
        )
        onPersist()
        let modNote = entry.modifiers.isEmpty
            ? ""
            : " Mods: " + entry.modifiers.map(\.summary).joined(separator: ", ") + "."
        onStatus?("Added quality \(entry.name).\(modNote)")
    }

    private func update(id: UUID, mutate: (inout QualityInstance) -> Void) {
        guard let idx = character.qualities.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.qualities[idx])
        onPersist()
    }
}
