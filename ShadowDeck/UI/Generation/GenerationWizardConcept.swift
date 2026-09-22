import SwiftUI

extension GenerationWizardView {
    var conceptStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Concept & Role")
                .font(.title3.weight(.semibold))
            HelpCallout(text: """
                Pick a runner role (playstyle archetype). This is not a mechanical character class—\
                it guides recommendations and your default Magic/Resonance path.
                """)

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    PaintedPortraitView(kind: .archetype(draft.archetype), showLabel: true)
                        .frame(height: 320)
                        .animation(.easeInOut(duration: 0.3), value: draft.archetype)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(draft.archetype.tagline)
                            .font(.headline)
                        EmphasizedHelpText(text: draft.archetype.summaryMarkdown)

                        Divider()
                        Text("Suggested Focus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(draft.archetype.suggestedFocus, id: \.self) { focus in
                                Text(focus)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default Magical Path")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(draft.archetype.defaultPathLabel)
                                .font(.callout)
                            EmphasizedHelpText(text: pathDescriptionMarkdown(draft.archetype.defaultAwakened))
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 380)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(RunnerArchetype.allCases) { arch in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                draft.selectArchetype(arch)
                            }
                        } label: {
                            PaintedPortraitView(
                                kind: .archetype(arch),
                                cornerRadius: 10,
                                showLabel: true
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        draft.archetype == arch ? Color.accentColor : Color.clear,
                                        lineWidth: 3
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sheet concept line")
                    .font(.subheadline.weight(.semibold))
                Text(ChargenHelpCatalog.conceptFieldHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Ex-Renraku security consultant", text: $draft.concept)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Metatype

}
