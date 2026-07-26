//
//  CharacterAtAGlanceView.swift
//  ShadowDeck
//
//  Phase 5 — primary at-a-glance character dashboard.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CharacterAtAGlanceView: View {
    @Environment(LibraryEnvironment.self) private var libraryEnvironment

    let characterID: UUID
    var onBack: () -> Void
    var onDeleted: () -> Void

    @State private var character: Character?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var karmaToAdd: Int = 1
    @State private var isExporting = false

    private var rules: any EditionRules {
        RulesRegistry.rules(for: character?.edition ?? .sr5)
    }

    private var derived: DerivedStats {
        guard let character else {
            return DerivedStats()
        }
        return rules.deriveStats(for: character)
    }

    var body: some View {
        Group {
            if let character {
                dashboard(character)
            } else {
                ProgressView("Loading character…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reload() }
        .onChange(of: characterID) { _, _ in reload() }
    }

    // MARK: - Dashboard

    private func dashboard(_ c: Character) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                toolbar(c)

                // Hero: portrait + identity + vitals
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        portraitColumn(c)
                            .frame(width: 260)
                        identityAndVitals(c)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        portraitColumn(c)
                            .frame(maxWidth: 320)
                        identityAndVitals(c)
                    }
                }

                // Attributes
                sectionCard("Attributes") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(AttributeID.standardGenerationAttributes, id: \.self) { id in
                            attributeTile(id.displayName, value: "\(c.attributes[id])")
                        }
                        attributeTile("Edge", value: "\(c.attributes.edge)")
                        if c.awakened.usesMagic {
                            attributeTile("Magic", value: "\(c.attributes.magic)")
                        }
                        if c.awakened.usesResonance {
                            attributeTile("Resonance", value: "\(c.attributes.resonance)")
                        }
                        attributeTile("Essence", value: essenceString(c))
                    }
                }

                // Combat readiness
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        conditionCard(c).frame(maxWidth: .infinity)
                        initiativeCard(c).frame(maxWidth: .infinity)
                        limitsCard(c).frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 12) {
                        conditionCard(c)
                        initiativeCard(c)
                        limitsCard(c)
                    }
                }

                // Skills & qualities
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        skillsCard(c).frame(maxWidth: .infinity, alignment: .topLeading)
                        qualitiesCard(c).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    VStack(spacing: 12) {
                        skillsCard(c)
                        qualitiesCard(c)
                    }
                }

                // Resources row
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    resourceTile("Karma Available", "\(c.karmaAvailable)", systemImage: "sparkles")
                    resourceTile("Karma Total", "\(c.karmaTotal)", systemImage: "chart.line.uptrend.xyaxis")
                    resourceTile("Nuyen", "¥\(formatInt(c.nuyen))", systemImage: "yensign.circle")
                    resourceTile("Contacts", "\(c.contacts.count)", systemImage: "person.2")
                    resourceTile("Augmentations", "\(c.augmentations.count)", systemImage: "cpu")
                    if !c.spells.isEmpty {
                        resourceTile("Spells", "\(c.spells.count)", systemImage: "wand.and.stars")
                    }
                    if !c.adeptPowers.isEmpty {
                        resourceTile("Adept Powers", "\(c.adeptPowers.count)", systemImage: "bolt.heart")
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar

    private func toolbar(_ c: Character) -> some View {
        HStack(spacing: 12) {
            Button {
                onBack()
            } label: {
                Label("Library", systemImage: "chevron.left")
            }

            Spacer()

            Button("Change Portrait…", systemImage: "photo") {
                pickAvatar()
            }
            .help("Upload or replace the character portrait")

            Button("Export…", systemImage: "square.and.arrow.up") {
                exportPackage()
            }
            .help("Export a portable .shadowdeck package")

            Menu {
                Button("Add \(karmaToAdd) Karma") { advanceKarma(by: karmaToAdd) }
                Button("Add 5 Karma") { advanceKarma(by: 5) }
                Button("Spend 1 Karma") { advanceKarma(by: -1) }
            } label: {
                Label("Karma", systemImage: "sparkles")
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteCharacter()
            }
        }
    }

    // MARK: - Portrait

    private func portraitColumn(_ c: Character) -> some View {
        VStack(spacing: 12) {
            portraitView(c)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

            if c.avatar.hasImage {
                Text(c.avatar.isAnimated ? "Animated portrait" : "Custom portrait")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No custom portrait — showing placeholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func portraitView(_ c: Character) -> some View {
        if let data = c.avatar.inlineData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else if let meta = ChargenArtLoader.nsImage(named: ChargenArtLoader.metatypeImageName(c.metatype)) {
            Image(nsImage: meta)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [.secondary.opacity(0.2), .secondary.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Identity & vitals

    private func identityAndVitals(_ c: Character) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.displayTitle)
                    .font(.largeTitle.weight(.bold))
                Text(c.concept.isEmpty ? "No concept set" : c.concept)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            FlowChips(items: [
                c.edition.shortName,
                c.metatype.displayName,
                c.awakened == .mundane ? "Mundane" : c.awakened.displayName,
                c.generation.system.displayName,
            ])

            Divider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                vital("Edge", "\(c.attributes.edge)", "bolt.fill")
                vital("Karma", "\(c.karmaAvailable)", "sparkles")
                vital("Nuyen", "¥\(formatInt(c.nuyen))", "yensign.circle.fill")
                vital("Essence", essenceString(c), "heart.fill")
                vital("Initiative", initiativeString(c), "gauge.with.dots.needle.67percent")
                if let phys = derived.physicalLimit {
                    vital("Phys. Limit", "\(phys)", "shield")
                }
            }

            if !c.notes.isEmpty {
                GroupBox("Notes") {
                    Text(c.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vital(_ title: String, _ value: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Sections

    private func conditionCard(_ c: Character) -> some View {
        sectionCard("Condition Monitors") {
            VStack(alignment: .leading, spacing: 12) {
                monitorRow(
                    title: "Physical",
                    filled: derived.condition.physicalFilled,
                    total: derived.condition.physicalBoxes,
                    color: .red
                )
                monitorRow(
                    title: "Stun",
                    filled: derived.condition.stunFilled,
                    total: derived.condition.stunBoxes,
                    color: .orange
                )
                Text("Overflow capacity: \(derived.condition.overflowBoxes) boxes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func monitorRow(title: String, filled: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(filled) / \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Box strip
            let columns = Array(repeating: GridItem(.fixed(14), spacing: 3), count: min(total, 18))
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < filled ? color.opacity(0.85) : Color.secondary.opacity(0.15))
                        .frame(width: 14, height: 18)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        }
                }
            }
        }
    }

    private func initiativeCard(_ c: Character) -> some View {
        sectionCard("Initiative") {
            VStack(alignment: .leading, spacing: 8) {
                Text(initiativeString(c))
                    .font(.title.monospacedDigit().weight(.semibold))
                Text("Reaction \(c.attributes.reaction) + Intuition \(c.attributes.intuition)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(initiativeDiceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                LabeledContent("Composure", value: "\(derived.composure)")
                LabeledContent("Judge Intentions", value: "\(derived.judgeIntentions)")
                LabeledContent("Memory", value: "\(derived.memory)")
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func limitsCard(_ c: Character) -> some View {
        sectionCard(c.edition.usesLimits ? "Limits" : "Derived") {
            if c.edition.usesLimits {
                VStack(alignment: .leading, spacing: 8) {
                    limitRow("Physical", derived.physicalLimit)
                    limitRow("Mental", derived.mentalLimit)
                    limitRow("Social", derived.socialLimit)
                    Text("SR5-style limits cap dice used on related tests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Armor", value: "\(derived.armor)")
                    LabeledContent("Walk / Run", value: "\(derived.movementWalk) / \(derived.movementRun)")
                    if c.edition.usesSessionEdgePool {
                        Text("SR6: Edge is a session pool that refreshes between encounters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This edition does not use classic Physical/Mental/Social limits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func limitRow(_ title: String, _ value: Int?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.map(String.init) ?? "—")
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }

    private func skillsCard(_ c: Character) -> some View {
        let top = c.skills
            .filter { $0.rating > 0 }
            .sorted { $0.rating > $1.rating }
            .prefix(10)

        return sectionCard("Key Skills") {
            if top.isEmpty {
                Text("No skills recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(top)) { skill in
                        HStack {
                            Text(skill.displayName)
                            if let spec = skill.specialized, !spec.isEmpty {
                                Text("(\(spec))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(skill.rating)")
                                .font(.body.monospacedDigit().weight(.semibold))
                            if let pool = derived.dicePools[skill.catalogKey] {
                                Text("pool \(pool)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .trailing)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func qualitiesCard(_ c: Character) -> some View {
        sectionCard("Qualities") {
            if c.qualities.isEmpty {
                Text("No qualities recorded.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(c.qualities) { q in
                        HStack(alignment: .top) {
                            Image(systemName: q.kind == .positive ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(q.kind == .positive ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.name)
                                    .font(.callout.weight(.medium))
                                Text("\(q.kind == .positive ? "Cost" : "Bonus") \(q.karmaValue) Karma")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }

    private func attributeTile(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func resourceTile(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private func reload() {
        do {
            character = try libraryEnvironment.library.fetch(id: characterID)
            if character == nil {
                errorMessage = "Character not found."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a portrait for this runner"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 8 * 1024 * 1024 else {
                errorMessage = "Image must be under 8 MB."
                return
            }
            guard var c = character else { return }
            c.avatar.inlineData = data
            c.avatar.mimeType = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            c.avatar.isAnimated = ["gif"].contains(url.pathExtension.lowercased())
            c.touch()
            try libraryEnvironment.library.save(c, avatarData: data)
            character = try libraryEnvironment.library.fetch(id: characterID)
            statusMessage = "Portrait updated."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportPackage() {
        guard character != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ShadowDeckFormat.fileExtension) ?? .data]
        panel.nameFieldStringValue = "\((character?.streetName.isEmpty == false ? character?.streetName : character?.name) ?? "Runner").\(ShadowDeckFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = "Export a portable ShadowDeck character package"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try libraryEnvironment.library.exportPackage(id: characterID, to: url)
            statusMessage = "Exported \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advanceKarma(by amount: Int) {
        guard var c = character else { return }
        if amount >= 0 {
            c.karmaTotal += amount
            c.karmaAvailable += amount
            statusMessage = "Awarded \(amount) Karma."
        } else {
            let spend = min(c.karmaAvailable, -amount)
            c.karmaAvailable -= spend
            statusMessage = "Spent \(spend) Karma."
        }
        c.touch()
        do {
            try libraryEnvironment.library.save(c)
            character = try libraryEnvironment.library.fetch(id: characterID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCharacter() {
        do {
            try libraryEnvironment.library.delete(id: characterID)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Formatting

    private func essenceString(_ c: Character) -> String {
        let ess = derived.currentEssence
        let n = NSDecimalNumber(decimal: ess)
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "\(ess)"
    }

    private func initiativeString(_ c: Character) -> String {
        "\(derived.initiativeBase) + \(derived.initiativeDice)D6"
    }

    private var initiativeDiceLabel: String {
        let n = derived.initiativeDice
        return n == 1 ? "1 Initiative Die" : "\(n) Initiative Dice"
    }

    private func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Chips

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

#Preview {
    CharacterAtAGlanceView(
        characterID: SampleCharacters.sr5ID,
        onBack: {},
        onDeleted: {}
    )
    .environment(LibraryEnvironment.preview())
    .frame(width: 1000, height: 800)
}
