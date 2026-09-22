import SwiftUI

extension GenerationWizardView {
    var magicStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Magic / Resonance")
                .font(.title3.weight(.semibold))
            HelpCallout(text: """
                Your path decides whether you use Magic, Resonance, or neither. \
                Mundane is the normal state for most runners—no spells, no complex forms—\
                just skills, Edge, and gear.
                """)

            ForEach(AwakenedPath.allCases, id: \.self) { path in
                let selected = draft.awakened == path
                Button {
                    draft.setAwakenedPath(path)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            Text(path == .mundane ? ChargenHelpCatalog.mundanePathLabel : path.displayName)
                                .font(.headline)
                        }
                        EmphasizedHelpText(text: pathDescriptionMarkdown(path))
                        Text(ChargenHelpCatalog.pathStory(path))
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            if draft.generationSystem == .buildPoints, draft.awakened.usesMagic {
                sr4SpellsSection
            }
        }
        .sheet(isPresented: $showSpellCatalog) {
            CatalogBrowserView(
                title: "Learn Spell (3 BP)",
                kinds: [.gear],
                edition: .sr4,
                matching: { $0.category.localizedCaseInsensitiveContains("spell") },
                onPick: { entry in
                    draft.addSpell(
                        SpellInstance(
                            catalogKey: entry.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                            name: entry.name,
                            category: entry.category
                        )
                    )
                    showSpellCatalog = false
                },
                onCustom: nil,
                onCancel: { showSpellCatalog = false }
            )
        }
    }

    var sr4SpellsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Spells (SR4A Build Points)")
                .font(.headline)
            HelpCallout(text: """
                Each spell costs **3 BP**. Maximum at chargen is twice the higher of Spellcasting or \
                Ritual Spellcasting (currently max \(draft.maxSpellsAtChargen)). \
                Raise Spellcasting on the Skills step first if you need more slots.
                """)
            LabeledContent("Spells", value: "\(draft.spells.count) / \(draft.maxSpellsAtChargen)")
            LabeledContent("Spell BP", value: "\(draft.buildPointLedger.spells) BP")

            if draft.spells.isEmpty {
                Text("No spells yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.spells) { spell in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spell.name).font(.body.weight(.medium))
                            if !spell.category.isEmpty {
                                Text(spell.category).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("3 BP").font(.caption.monospacedDigit())
                        Button(role: .destructive) {
                            draft.removeSpell(id: spell.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            AppChromeButton.title(
                "Add Spell from Catalog…",
                help: "Browse SR4A spells (3 BP each)",
                isEnabled: draft.canAddSpell()
            ) {
                showSpellCatalog = true
            }
        }
    }

    // MARK: - Skills

}
