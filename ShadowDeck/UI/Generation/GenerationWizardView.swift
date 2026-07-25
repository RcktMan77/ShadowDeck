//
//  GenerationWizardView.swift
//  ShadowDeck
//
//  Classic multi-page character generation flow with live allocation UI.
//

import SwiftUI
import AppKit

struct GenerationWizardView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment
    @State private var draft = GenerationDraft()
    @State private var statusMessage: String?
    @State private var didFinish = false
    var onFinished: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AllocationCounterBar(draft: draft)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
            ScrollView {
                stepContent
                    .padding(20)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Character")
                    .font(.title2.weight(.semibold))
                Text("Step \(draft.step.rawValue + 1) of \(draft.steps.count) — \(draft.step.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Step dots
            HStack(spacing: 6) {
                ForEach(draft.steps) { step in
                    Circle()
                        .fill(step == draft.step ? Color.accentColor : (step < draft.step ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25)))
                        .frame(width: 8, height: 8)
                        .help(step.title)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch draft.step {
        case .edition: editionStep
        case .concept: conceptStep
        case .metatype: metatypeStep
        case .priorities: prioritiesStep
        case .attributes: attributesStep
        case .magic: magicStep
        case .skills: skillsStep
        case .qualities: qualitiesStep
        case .resources: resourcesStep
        case .finish: finishStep
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") { draft.goBack() }
                .disabled(draft.step == .edition)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if draft.step == .finish {
                Button("Save Character") {
                    saveCharacter()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canGoNext || didFinish)
            } else {
                Button("Continue") { draft.goNext() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canGoNext)
            }
        }
        .padding(16)
    }

    // MARK: - Steps

    private var editionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose edition")
                .font(.title3.weight(.semibold))
            Text("ShadowDeck treats 4th, 5th, and 6th edition as equal peers. Generation rules adapt to your choice.")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(Edition.allCases) { edition in
                    editionCard(edition)
                }
            }

            Toggle("Use popular table house rules (Sum-to-Ten, bonus karma, etc.)", isOn: Binding(
                get: { draft.houseRules.isEnabled(.sumToTen) },
                set: { on in
                    if on {
                        draft.houseRules = .popularTable
                        draft.generationSystem = .sumToTen
                    } else {
                        draft.houseRules = .coreBook
                        draft.generationSystem = draft.rules.defaultGenerationSystem
                    }
                    draft.recomputeBudgetsFromPriorities()
                }
            ))
        }
    }

    private func editionCard(_ edition: Edition) -> some View {
        let selected = draft.edition == edition
        return Button {
            draft.selectEdition(edition)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(edition.shortName)
                    .font(.title2.weight(.bold))
                Text(edition.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(edition.usesPriorityGenerationByDefault ? "Priority generation" : "Build Points generation")
                    .font(.caption2)
                if edition.usesLimits {
                    Text("Uses limits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if edition.usesSessionEdgePool {
                    Text("Session Edge pool")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var conceptStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Concept & role")
                .font(.title3.weight(.semibold))
            Text("Pick a runner archetype. Art and summary update with your selection — this guides defaults; priorities remain your choice.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                // Showcase
                VStack(spacing: 12) {
                    ArchetypeBackdrop(archetype: draft.archetype, isSelected: true)
                        .frame(height: 280)
                        .animation(.easeInOut(duration: 0.35), value: draft.archetype)
                    ArchetypeSummaryCard(archetype: draft.archetype, edition: draft.edition)
                }
                .frame(maxWidth: 360)

                // Picker grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(RunnerArchetype.allCases) { arch in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                draft.selectArchetype(arch)
                            }
                        } label: {
                            ArchetypeBackdrop(archetype: arch, isSelected: draft.archetype == arch)
                                .frame(height: 110)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Custom concept (optional)", text: $draft.concept)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var metatypeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metatype")
                .font(.title3.weight(.semibold))
            Text("Natural attribute ranges depend on metatype. Changing metatype resets attributes to new minima.")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(MetatypeID.allCases) { meta in
                    let profile = MetatypeCatalog.profile(for: meta, edition: draft.edition)
                    let selected = draft.metatype == meta
                    Button {
                        draft.selectMetatype(meta)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meta.displayName)
                                .font(.headline)
                            Text("BOD \(profile.bounds(for: .body).minimum)–\(profile.bounds(for: .body).maximum)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("EDG max \(profile.bounds(for: .edge).maximum)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var prioritiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.generationSystem == .buildPoints ? "Build Points" : "Priorities")
                .font(.title3.weight(.semibold))

            if draft.generationSystem == .buildPoints {
                Text("SR4 uses Build Points (default \(draft.rules.standardBuildPointBudget) BP). Attribute and skill steppers use simplified pools for this wizard; full BP ledger expands in later polish.")
                    .foregroundStyle(.secondary)
                LabeledContent("BP budget", value: "\(draft.budget.buildPointsTotal)")
            } else {
                Text(
                    draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen)
                        ? "Assign letters so values sum to 10 (A=4 … E=0). Duplicates allowed."
                        : "Assign each priority letter A–E exactly once."
                )
                .foregroundStyle(.secondary)

                if draft.priority.isComplete {
                    let ok = draft.priorityValid
                    Label(
                        ok ? "Priority assignment is valid." : "Priority assignment is incomplete or invalid.",
                        systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(ok ? .green : .orange)
                    if draft.generationSystem == .sumToTen || draft.houseRules.isEnabled(.sumToTen) {
                        Text("Sum-to-Ten total: \(draft.priority.sumToTenTotal)")
                            .font(.caption.monospacedDigit())
                    }
                }

                ForEach(PriorityColumn.allCases, id: \.self) { column in
                    priorityRow(column)
                }
            }
        }
    }

    private func priorityRow(_ column: PriorityColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.displayName)
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(PriorityLetter.allCases, id: \.self) { letter in
                    let selected = draft.priority[column] == letter
                    let summary = PrioritySummaryBuilder.summaries(
                        for: draft.edition,
                        metatype: draft.metatype,
                        rules: draft.rules
                    ).first { $0.column == column && $0.letter == letter }

                    Button {
                        draft.assignPriority(letter, to: column)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(letter.rawValue)
                                .font(.title3.weight(.bold))
                            if let summary {
                                ForEach(summary.detailLines.prefix(2), id: \.self) { line in
                                    Text(line)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(summary?.detailLines.joined(separator: "\n") ?? letter.rawValue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var attributesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attributes")
                .font(.title3.weight(.semibold))
            Text("Spend attribute points above metatype minima. + is disabled when the pool is empty or the natural maximum is reached.")
                .foregroundStyle(.secondary)

            GroupBox("Physical & Mental") {
                ForEach(AttributeID.standardGenerationAttributes, id: \.self) { id in
                    let bounds = MetatypeCatalog.profile(for: draft.metatype, edition: draft.edition).bounds(for: id)
                    PointStepperRow(
                        title: id.displayName,
                        value: draft.attributes[id],
                        subtitle: "Range \(bounds.minimum)–\(bounds.maximum)",
                        canIncrease: draft.canIncreaseAttribute(id),
                        canDecrease: draft.canDecreaseAttribute(id),
                        onIncrease: { draft.increaseAttribute(id) },
                        onDecrease: { draft.decreaseAttribute(id) }
                    )
                }
            }

            if draft.budget.specialPointsTotal > 0 || draft.awakened != .mundane {
                GroupBox("Special") {
                    let specialIDs: [AttributeID] = {
                        var ids: [AttributeID] = [.edge]
                        if draft.awakened.usesMagic { ids.append(.magic) }
                        if draft.awakened.usesResonance { ids.append(.resonance) }
                        return ids
                    }()
                    ForEach(specialIDs, id: \.self) { id in
                        PointStepperRow(
                            title: id.displayName,
                            value: draft.attributes[id],
                            subtitle: "Special / adjustment points",
                            canIncrease: draft.canIncreaseAttribute(id),
                            canDecrease: draft.canDecreaseAttribute(id),
                            onIncrease: { draft.increaseAttribute(id) },
                            onDecrease: { draft.decreaseAttribute(id) }
                        )
                    }
                }
            }
        }
    }

    private var magicStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Magic / Resonance")
                .font(.title3.weight(.semibold))
            Text("Confirm your awakened path. Mundane runners can skip detail; magicians, adepts, and technomancers set Magic or Resonance.")
                .foregroundStyle(.secondary)

            Picker("Path", selection: $draft.awakened) {
                ForEach(AwakenedPath.allCases, id: \.self) { path in
                    Text(path.displayName).tag(path)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: draft.awakened) { _, newValue in
                if newValue.usesMagic && draft.attributes.magic < 1 { draft.attributes.magic = 1 }
                if newValue.usesResonance && draft.attributes.resonance < 1 { draft.attributes.resonance = 1 }
                if newValue == .mundane {
                    draft.attributes.magic = 0
                    draft.attributes.resonance = 0
                }
            }

            if draft.awakened.usesMagic {
                LabeledContent("Magic", value: "\(draft.attributes.magic)")
            }
            if draft.awakened.usesResonance {
                LabeledContent("Resonance", value: "\(draft.attributes.resonance)")
            }
            if draft.awakened == .mundane {
                Text("No Magic or Resonance. Special points typically feed Edge.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var skillsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills")
                .font(.title3.weight(.semibold))
            Text("Allocate skill points. Common active skills are listed; ranks above 6 are blocked at chargen for this wizard.")
                .foregroundStyle(.secondary)

            GroupBox {
                ForEach(ChargenSkillCatalog.active, id: \.key) { item in
                    PointStepperRow(
                        title: item.name,
                        value: draft.skillRanks[item.key] ?? 0,
                        subtitle: nil,
                        canIncrease: draft.canIncreaseSkill(catalogKey: item.key),
                        canDecrease: draft.canDecreaseSkill(catalogKey: item.key),
                        onIncrease: {
                            draft.setSkillRank(
                                catalogKey: item.key,
                                displayName: item.name,
                                rank: (draft.skillRanks[item.key] ?? 0) + 1
                            )
                        },
                        onDecrease: {
                            draft.setSkillRank(
                                catalogKey: item.key,
                                displayName: item.name,
                                rank: (draft.skillRanks[item.key] ?? 0) - 1
                            )
                        }
                    )
                }
            }
        }
    }

    private var qualitiesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qualities")
                .font(.title3.weight(.semibold))
            Text("Optional starter qualities. Positive karma spent: \(draft.budget.positiveQualityKarmaUsed) / \(draft.budget.positiveQualityKarmaCap).")
                .foregroundStyle(.secondary)

            let starters: [(String, String, QualityKind, Int)] = [
                ("toughness", "Toughness", .positive, 10),
                ("guts", "Guts", .positive, 10),
                ("first_impression", "First Impression", .positive, 11),
                ("sinner", "SINner (National)", .negative, 5),
                ("allergy", "Allergy (Common, Mild)", .negative, 10),
                ("distinctive", "Distinctive Style", .negative, 5),
            ]

            ForEach(starters, id: \.0) { item in
                let selected = draft.qualities.contains { $0.catalogKey == item.0 }
                Toggle(isOn: Binding(
                    get: { selected },
                    set: { on in
                        if on {
                            if item.2 == .positive {
                                let next = draft.budget.positiveQualityKarmaUsed + item.3
                                guard next <= draft.budget.positiveQualityKarmaCap else { return }
                                draft.budget.positiveQualityKarmaUsed = next
                            } else {
                                let next = draft.budget.negativeQualityKarmaGained + item.3
                                guard next <= draft.budget.negativeQualityKarmaCap else { return }
                                draft.budget.negativeQualityKarmaGained = next
                                draft.budget.karmaRemaining += item.3
                            }
                            draft.qualities.append(
                                QualityInstance(
                                    catalogKey: item.0,
                                    name: item.1,
                                    kind: item.2,
                                    karmaValue: item.3
                                )
                            )
                        } else {
                            draft.qualities.removeAll { $0.catalogKey == item.0 }
                            if item.2 == .positive {
                                draft.budget.positiveQualityKarmaUsed = max(0, draft.budget.positiveQualityKarmaUsed - item.3)
                            } else {
                                draft.budget.negativeQualityKarmaGained = max(0, draft.budget.negativeQualityKarmaGained - item.3)
                                draft.budget.karmaRemaining = max(0, draft.budget.karmaRemaining - item.3)
                            }
                        }
                    }
                )) {
                    Text("\(item.1) (\(item.2 == .positive ? "+" : "−")\(item.3) karma)")
                }
            }
        }
    }

    private var resourcesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resources")
                .font(.title3.weight(.semibold))
            Text("Starting nuyen from your Resources priority (or BP table). Gear shopping expands in later phases; set cash on hand here.")
                .foregroundStyle(.secondary)

            LabeledContent("Nuyen budget", value: "¥\(draft.budget.nuyenTotal)")
            Stepper(value: $draft.nuyen, in: 0...max(draft.budget.nuyenTotal, draft.nuyen), step: 500) {
                Text("Cash on hand: ¥\(draft.nuyen)")
            }
            .onChange(of: draft.nuyen) { _, newValue in
                draft.budget.nuyenRemaining = max(0, draft.budget.nuyenTotal - newValue)
            }

            Text("Tip: Street samurai and deckers often need Resources B+; magicians can lean lower.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Finishing touches")
                .font(.title3.weight(.semibold))

            TextField("Legal / real name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
            TextField("Street name", text: $draft.streetName)
                .textFieldStyle(.roundedBorder)

            GroupBox("Summary") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Edition", value: draft.edition.rawValue)
                    LabeledContent("Metatype", value: draft.metatype.displayName)
                    LabeledContent("Archetype", value: draft.archetype.displayName)
                    LabeledContent("Path", value: draft.awakened.displayName)
                    LabeledContent("Attributes spent", value: "\(draft.budget.attributePointsSpent) / \(draft.budget.attributePointsTotal)")
                    LabeledContent("Skills spent", value: "\(draft.budget.skillPointsSpent) / \(draft.budget.skillPointsTotal)")
                    LabeledContent("Nuyen", value: "¥\(draft.nuyen)")
                    LabeledContent("Qualities", value: "\(draft.qualities.count)")
                }
            }

            Text("Avatar upload is available after save from the character summary (Phase 5). You can also import portraits later.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if didFinish {
                Label("Character saved to library.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func saveCharacter() {
        do {
            let character = draft.buildCharacter()
            try libraryEnvironment.library.save(character, avatarData: draft.avatarData)
            didFinish = true
            statusMessage = "Saved \(character.displayTitle)."
            onFinished?()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    GenerationWizardView()
        .environment(LibraryEnvironment.preview(seedSamples: false))
        .frame(width: 960, height: 720)
}
