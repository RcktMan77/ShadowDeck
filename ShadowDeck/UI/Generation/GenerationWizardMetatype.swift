import SwiftUI

extension GenerationWizardView {
    var metatypeStep: some View {
        let showBPCosts = draft.generationSystem == .buildPoints
        return VStack(alignment: .leading, spacing: 16) {
            Text("Metatype")
                .font(.title3.weight(.semibold))
            if showBPCosts {
                HelpCallout(text: """
                    Your metatype sets natural min/max attributes and costs **Build Points** from the **400 BP** budget \
                    (Human **0**, Ork **20**, Dwarf **25**, Elf **30**, Troll **40**). \
                    Body and Edge ranges matter for every runner:
                    """)
            } else {
                HelpCallout(text: """
                    Your metatype sets natural minimum and maximum scores for attributes. \
                    Availability and special/adjustment points come from the **Metatype** priority column (not a flat karma fee). \
                    Body and Edge are especially important for every runner:
                    """)
            }

            HStack(spacing: 12) {
                attributeChip(id: .body, short: "BOD")
                attributeChip(id: .edge, short: "EDG")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(MetatypeID.allCases) { meta in
                    let profile = MetatypeCatalog.profile(for: meta, edition: draft.edition)
                    let selected = draft.metatype == meta
                    let bpCost = SR4BuildPointEngine.metatypeCost(meta)
                    Button {
                        draft.selectMetatype(meta)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            PaintedPortraitView(kind: .metatype(meta), cornerRadius: 8, showLabel: false)
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .contentShape(Rectangle())
                            HStack(alignment: .firstTextBaseline) {
                                Text(meta.displayName)
                                    .font(.headline)
                                Spacer(minLength: 4)
                                if showBPCosts {
                                    Text(bpCost == 0 ? "0 BP" : "\(bpCost) BP")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                                        )
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                        .help("SR4A metatype Build Point cost")
                                }
                            }
                            Text(ChargenHelpCatalog.metatypeBlurb(meta))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("BOD \(profile.bounds(for: .body).minimum)–\(profile.bounds(for: .body).maximum) · EDG max \(profile.bounds(for: .edge).maximum)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func attributeChip(id: AttributeID, short: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(short) — \(id.displayName)")
                .font(.subheadline.weight(.semibold))
            Text(ChargenHelpCatalog.attributeDescription(id))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Influences: \(ChargenHelpCatalog.attributeInfluences(id))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    func pathDescriptionMarkdown(_ path: AwakenedPath) -> String {
        // Emphasize key game terms consistently for hover help.
        switch path {
        case .mundane:
            "You have no **Magic** or **Resonance**—neither a spellcaster nor a technomancer. Most runners are mundane and rely on **Skills**, **Edge**, gear, and cyberware."
        case .fullMagician:
            "A Magician channels mana to cast spells, summon spirits, and project astrally. You need a **Magic** attribute; **Essence** loss from cyberware can reduce **Magic**."
        case .aspectedMagician:
            "Limited to one magical skill category (for example only **Sorcery**, Conjuring, or Enchanting). Cheaper than a full Magician, with a narrower toolbox."
        case .mysticAdept:
            "Splits power between spellcasting and adept powers. Flexible but expensive; you juggle **Magic** for both spells and power points."
        case .adept:
            "Spends **Magic** on adept powers (improved reflexes, combat sense, attribute boosts) instead of spells. Your body is the focus."
        case .technomancer:
            "Emerged, not awakened: **Resonance** replaces a cyberdeck. You thread complex forms and compile sprites. Guard your **Essence**."
        }
    }

    // MARK: - Priorities

}
