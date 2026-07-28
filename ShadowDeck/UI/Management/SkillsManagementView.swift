//
//  SkillsManagementView.swift
//  ShadowDeck
//

import SwiftUI

struct SkillsManagementView: View {
    @Binding var character: Character
    var onPersist: () -> Void

    @State private var showCatalog = false
    @State private var isCustom = false
    @State private var draftName = ""
    @State private var draftCategory: SkillCategory = .active

    private var sortedSkills: [SkillRating] {
        character.skills.sorted {
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        ManagementListChrome(
            title: "Skills",
            subtitle: "Browse the skill catalog or add a custom skill. Pools use linked attributes on Summary.",
            onAdd: { showCatalog = true },
            addLabel: "Add Skill"
        ) {
            if character.skills.isEmpty {
                ManagementEmptyState(
                    title: "No Skills",
                    systemImage: "list.bullet.rectangle",
                    message: "Add from the catalog or import a Chummer sheet."
                )
            } else {
                List {
                    ForEach(SkillCategory.allCases, id: \.self) { category in
                        let rows = sortedSkills.filter { $0.category == category }
                        if !rows.isEmpty {
                            Section(category.rawValue.capitalized) {
                                ForEach(rows) { skill in
                                    skillRow(skill)
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
                title: "Add Skill",
                kinds: [.skill],
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

    private func skillRow(_ skill: SkillRating) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayName)
                    .font(.body.weight(.medium))
                if let spec = skill.specialized, !spec.isEmpty {
                    Text("Spec: \(spec)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            StepperControl(value: skill.rating, range: 0...13) { newRating in
                updateSkill(id: skill.id) { $0.rating = newRating }
            }
            Button(role: .destructive) {
                character.skills.removeAll { $0.id == skill.id }
                onPersist()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove skill")
        }
    }

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Skill")
                .font(.title2.weight(.semibold))
            TextField("Skill name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            Picker("Category", selection: $draftCategory) {
                ForEach(SkillCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button("Cancel") { isCustom = false }
                Button("Add") {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    character.skills.append(
                        SkillRating(
                            catalogKey: ManagementSupport.catalogKey(from: name),
                            displayName: name,
                            category: draftCategory,
                            rating: 1
                        )
                    )
                    onPersist()
                    draftName = ""
                    isCustom = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func addFromCatalog(_ entry: CatalogEntry) {
        // Avoid duplicates by name.
        if character.skills.contains(where: {
            $0.displayName.caseInsensitiveCompare(entry.name) == .orderedSame
        }) {
            return
        }
        let category: SkillCategory
        let cat = entry.category.lowercased()
        let notes = entry.notes.lowercased()
        if cat.contains("language") {
            category = .language
        } else if notes == "knowledge" || cat.contains("knowledge")
            || ["academic", "interest", "professional", "street"].contains(cat)
        {
            category = .knowledge
        } else {
            category = .active
        }
        character.skills.append(
            SkillRating(
                catalogKey: ManagementSupport.catalogKey(from: entry.name),
                displayName: entry.name,
                category: category,
                rating: 1,
                knowledgeType: category == .knowledge ? entry.category : nil
            )
        )
        onPersist()
    }

    private func updateSkill(id: UUID, mutate: (inout SkillRating) -> Void) {
        guard let idx = character.skills.firstIndex(where: { $0.id == id }) else { return }
        mutate(&character.skills[idx])
        onPersist()
    }
}
