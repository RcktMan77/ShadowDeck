//
//  AugmentationsManagementView.swift
//  ShadowDeck
//
//  Phase 6–7 — cyber/bioware, essence, nuyen, attribute modifiers.
//

import SwiftUI

struct AugmentationsManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void
    var onStatus: ((String) -> Void)?

    @State private var showCatalog = false
    @State private var isCustom = false
    @State private var draftName = ""
    @State private var draftKind: AugmentationKind = .cyberware
    @State private var draftEssence: String = "0.1"
    @State private var draftCost = 0
    @State private var draftRating = 1
    @State private var draftModifiers: [StatModifier] = []
    @State private var chargeNuyen = true

    private var totalEssence: Decimal {
        character.augmentations.reduce(0) { $0 + $1.essenceCost }
    }

    var body: some View {
        ManagementListChrome(
            title: "Augmentations",
            subtitle: "Installing catalog cyber/bioware charges nuyen and applies modifiers to Summary.",
            onAdd: { showCatalog = true },
            addLabel: "Add Aug",
            onLookUp: {
                RulesReferenceOpener.request(query: "cyberware", character: character)
            },
            lookUpLabel: "Look up"
        ) {
            HStack {
                Text("Installed essence cost: \(formatEssence(totalEssence))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Nuyen: ¥\(character.nuyen)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if character.augmentations.isEmpty {
                ManagementEmptyState(
                    title: "No Augmentations",
                    systemImage: "cpu",
                    message: "Add from the catalog or import from Chummer."
                )
            } else {
                List {
                    ForEach(character.augmentations.sorted { $0.name < $1.name }) { aug in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(aug.name)
                                    .font(.body.weight(.medium))
                                Text("\(aug.kind.rawValue.capitalized) · \(aug.grade.rawValue.capitalized) · ESS \(formatEssence(aug.essenceCost))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !aug.modifiers.isEmpty {
                                    Text(aug.modifiers.map(\.summary).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.tint)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if aug.modifiers.contains(where: \.usesRating) || aug.rating != nil {
                                HStack(spacing: 4) {
                                    Text("R")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    StepperControl(value: aug.rating ?? 1, range: 1...12) { r in
                                        update(id: aug.id) { $0.rating = r }
                                    }
                                }
                            }
                            if aug.nuyenCost > 0 {
                                Text("¥\(aug.nuyenCost)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                remove(aug)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView(
                title: "Add Augmentation",
                kinds: [.cyberware, .bioware],
                edition: character.edition,
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

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Augmentation")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            Picker("Kind", selection: $draftKind) {
                Text("Cyberware").tag(AugmentationKind.cyberware)
                Text("Bioware").tag(AugmentationKind.bioware)
            }
            .pickerStyle(.segmented)
            TextField("Essence cost", text: $draftEssence)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Nuyen")
                Spacer()
                StepperControl(value: draftCost, range: 0...1_000_000) { draftCost = $0 }
            }
            HStack {
                Text("Rating")
                Spacer()
                StepperControl(value: draftRating, range: 1...12) { draftRating = $0 }
            }
            Toggle("Charge nuyen from character", isOn: $chargeNuyen)
                .toggleStyle(.checkbox)
            ModifierDraftEditor(modifiers: $draftModifiers)
            HStack {
                Spacer()
                AppChromeButton.title("Cancel", help: "Close without adding") { isCustom = false }
                AppChromeButton.title(
                    "Add",
                    help: "Add custom entry",
                    style: .prominent,
                    keyEquivalent: "\r"
                ) {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let ess = Decimal(string: draftEssence.replacingOccurrences(of: ",", with: ".")) ?? 0
                    var msg = ""
                    if chargeNuyen {
                        let result = CharacterEffectsEngine.chargeNuyen(
                            &character,
                            unitCost: draftCost,
                            itemName: name
                        )
                        msg = result.message
                    }
                    character.augmentations.append(
                        Augmentation(
                            catalogKey: ManagementSupport.catalogKey(from: name),
                            name: name,
                            kind: draftKind,
                            rating: draftRating,
                            essenceCost: ess,
                            nuyenCost: draftCost,
                            notes: "Custom",
                            modifiers: draftModifiers,
                            purchasedInApp: chargeNuyen && draftCost > 0
                        )
                    )
                    onPersist()
                    onStatus?(msg.isEmpty ? "Installed \(name)." : msg)
                    draftName = ""
                    draftEssence = "0.1"
                    draftCost = 0
                    draftRating = 1
                    draftModifiers = []
                    isCustom = false
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func addFromCatalog(_ entry: CatalogEntry) {
        let kind: AugmentationKind = entry.kind == .bioware ? .bioware : .cyberware
        let ess: Decimal
        if let text = entry.essenceText,
           let parsed = Decimal(string: text.replacingOccurrences(of: ",", with: ".")) {
            ess = parsed
        } else {
            ess = 0
        }
        let unit = entry.costNuyen ?? 0
        let charge = CharacterEffectsEngine.chargeNuyen(
            &character,
            unitCost: unit,
            itemName: entry.name
        )
        character.augmentations.append(
            Augmentation(
                catalogKey: ManagementSupport.catalogKey(from: entry.name),
                name: entry.name,
                kind: kind,
                rating: entry.modifiers.contains(where: \.usesRating) ? 1 : nil,
                essenceCost: ess,
                nuyenCost: unit,
                notes: [
                    entry.category,
                    entry.essenceText.map { "ESS formula: \($0)" },
                    entry.source.isEmpty ? nil : "\(entry.source) p.\(entry.page)"
                ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                modifiers: ManagementSupport.instanceModifiers(from: entry),
                purchasedInApp: charge.charged > 0
            )
        )
        onPersist()
        onStatus?(charge.message)
    }

    private func remove(_ aug: Augmentation) {
        if aug.purchasedInApp {
            let msg = CharacterEffectsEngine.refundNuyen(
                &character,
                unitCost: aug.nuyenCost,
                itemName: aug.name
            )
            onStatus?(msg)
        } else {
            onStatus?("\(aug.name) removed.")
        }
        character.augmentations.removeAll { $0.id == aug.id }
        onPersist()
    }

    private func update(id: UUID, mutate: (inout Augmentation) -> Void) {
        guard let idx = character.augmentations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.augmentations[idx])
        onPersist()
    }

    private func formatEssence(_ value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value)
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "\(value)"
    }
}
