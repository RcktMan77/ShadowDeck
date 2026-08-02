//
//  GearManagementView.swift
//  ShadowDeck
//
//  Phase 6–7 — inventory + catalog browse, nuyen purchase, equip modifiers.
//

import SwiftUI

struct GearManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void
    var onStatus: ((String) -> Void)?

    @State private var showCatalog = false
    @State private var isCustom = false
    @State private var draftName = ""
    @State private var draftCategory: GearCategory = .other
    @State private var draftCost = 0
    @State private var draftArmor: Int = 0
    @State private var draftModifiers: [StatModifier] = []
    @State private var chargeNuyen = true

    private var sorted: [GearItem] {
        character.gear.sorted {
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ManagementListChrome(
            title: "Gear",
            subtitle: "Catalog items charge nuyen when added. Equipped gear applies modifiers to Summary.",
            onAdd: { showCatalog = true },
            addLabel: "Add Gear",
            onLookUp: {
                RulesReferenceOpener.request(query: "gear", character: character)
            },
            lookUpLabel: "Look up"
        ) {
            HStack {
                Text("Nuyen: ¥\(character.nuyen)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if character.gear.isEmpty {
                ManagementEmptyState(
                    title: "No Gear",
                    systemImage: "bag",
                    message: "Add from the catalog or import a Chummer sheet."
                )
            } else {
                List {
                    ForEach(GearCategory.allCases, id: \.self) { category in
                        let rows = sorted.filter { $0.category == category }
                        if !rows.isEmpty {
                            Section(category.displayName) {
                                ForEach(rows) { item in
                                    gearRow(item)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView(
                title: "Add Gear",
                kinds: [.gear, .weapon, .armor],
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

    private func gearRow(_ item: GearItem) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { item.equipped },
                set: { equipped in
                    update(id: item.id) { $0.equipped = equipped }
                    let effectsNote = equipped && !item.modifiers.isEmpty
                        ? " Equipped — modifiers active."
                        : (equipped ? " Equipped." : " Unequipped.")
                    onStatus?("\(item.name):\(effectsNote)")
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .help("Equipped (applies modifiers to Summary)")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    if let sub = item.subcategory, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.quantity != 1 {
                        Text("×\(item.quantity)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let dmg = item.damageCode, !dmg.isEmpty {
                        Text(dmg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let armor = item.armorRating {
                        Text("Armor \(armor)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.nuyenCost > 0 {
                        Text("¥\(item.nuyenCost)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !item.modifiers.isEmpty {
                        Text(item.modifiers.map(\.summary).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    }
                    if let source = item.source, !source.isEmpty {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if item.modifiers.contains(where: \.usesRating) {
                HStack(spacing: 4) {
                    Text("R")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    StepperControl(value: item.rating, range: 1...12) { r in
                        update(id: item.id) { $0.rating = r }
                    }
                }
            }
            StepperControl(value: item.quantity, range: 1...99) { qty in
                update(id: item.id) { $0.quantity = qty }
            }
            Button(role: .destructive) {
                remove(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Gear")
                .font(.title2.weight(.semibold))
            TextField("Item name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            Picker("Category", selection: $draftCategory) {
                ForEach(GearCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            HStack {
                Text("Nuyen")
                Spacer()
                StepperControl(value: draftCost, range: 0...1_000_000) { draftCost = $0 }
            }
            if draftCategory == .armor {
                HStack {
                    Text("Armor rating")
                    Spacer()
                    StepperControl(value: draftArmor, range: 0...30) { draftArmor = $0 }
                }
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
                    var msg = ""
                    if chargeNuyen {
                        let result = CharacterEffectsEngine.chargeNuyen(
                            &character,
                            unitCost: draftCost,
                            itemName: name
                        )
                        msg = result.message
                    }
                    character.gear.append(
                        GearItem(
                            catalogKey: ManagementSupport.catalogKey(from: name),
                            name: name,
                            category: draftCategory,
                            nuyenCost: draftCost,
                            notes: "Custom item",
                            armorRating: draftCategory == .armor && draftArmor > 0 ? draftArmor : nil,
                            modifiers: draftModifiers,
                            purchasedInApp: chargeNuyen && draftCost > 0
                        )
                    )
                    onPersist()
                    onStatus?(msg.isEmpty ? "Added \(name)." : msg)
                    draftName = ""
                    draftCost = 0
                    draftArmor = 0
                    draftModifiers = []
                    isCustom = false
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func addFromCatalog(_ entry: CatalogEntry) {
        let category: GearCategory
        switch entry.kind {
        case .weapon: category = .weapon
        case .armor: category = .armor
        default: category = GearCategory.infer(from: entry.category)
        }
        let unit = entry.costNuyen ?? 0
        let charge = CharacterEffectsEngine.chargeNuyen(
            &character,
            unitCost: unit,
            itemName: entry.name
        )
        character.gear.append(
            GearItem(
                catalogKey: ManagementSupport.catalogKey(from: entry.name),
                name: entry.name,
                category: category,
                nuyenCost: unit,
                availability: entry.availability,
                notes: entry.notes,
                armorRating: entry.armorRating,
                damageCode: entry.damage,
                subcategory: entry.category.isEmpty ? nil : entry.category,
                source: entry.source.isEmpty ? nil : entry.source,
                modifiers: ManagementSupport.instanceModifiers(from: entry),
                purchasedInApp: charge.charged > 0
            )
        )
        onPersist()
        onStatus?(charge.message)
    }

    private func remove(_ item: GearItem) {
        if item.purchasedInApp {
            let msg = CharacterEffectsEngine.refundNuyen(
                &character,
                unitCost: item.nuyenCost,
                quantity: item.quantity,
                itemName: item.name
            )
            onStatus?(msg)
        } else {
            onStatus?("\(item.name) removed.")
        }
        character.gear.removeAll { $0.id == item.id }
        onPersist()
    }

    private func update(id: UUID, mutate: (inout GearItem) -> Void) {
        guard let idx = character.gear.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.gear[idx])
        onPersist()
    }
}
