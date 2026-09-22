import SwiftUI

extension GenerationWizardView {
    var qualitiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Qualities")
                .font(.title3.weight(.semibold))
            if draft.generationSystem == .buildPoints {
                HelpCallout(text: """
                    Positive qualities cost **BP**; negative qualities refund **BP**. \
                    Cap **35 BP** of positive and **35 BP** of negative qualities.
                    """)
                GroupBox("Quality BP") {
                    let pos = draft.qualities.filter { $0.kind == .positive }.reduce(0) { $0 + abs($1.karmaValue) }
                    let neg = draft.qualities.filter { $0.kind == .negative }.reduce(0) { $0 + abs($1.karmaValue) }
                    LabeledContent("Positive qualities", value: "\(pos) / 35 BP")
                    LabeledContent("Negative qualities", value: "\(neg) / 35 BP")
                    LabeledContent("Net quality BP", value: "\(draft.buildPointLedger.qualities) BP")
                    LabeledContent("BP remaining", value: "\(draft.budget.buildPointsRemaining)")
                }
            } else {
                HelpCallout(text: "Qualities are optional lasting traits. Positive qualities cost Karma; negative qualities grant Karma but add complications.")

                GroupBox("Karma budgeting") {
                    Text(ChargenHelpCatalog.karmaBudgetGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent(
                        "Positive quality Karma used",
                        value: "\(draft.budget.positiveQualityKarmaUsed) / \(draft.budget.positiveQualityKarmaCap)"
                    )
                    LabeledContent("Karma remaining", value: "\(draft.budget.karmaRemaining)")
                }
            }

            let starters: [(String, String, QualityKind, Int)] = [
                ("toughness", "Toughness", .positive, 10),
                ("guts", "Guts", .positive, 10),
                ("first_impression", "First Impression", .positive, 11),
                ("sinner", "SINner (National)", .negative, 5),
                ("allergy", "Allergy (Common, Mild)", .negative, 10),
                ("distinctive", "Distinctive Style", .negative, 5)
            ]

            ForEach(starters, id: \.0) { item in
                let selected = draft.qualities.contains { $0.catalogKey == item.0 }
                let unit = draft.generationSystem == .buildPoints ? "BP" : "Karma"
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { selected },
                        set: { on in toggleQuality(item, on: on) }
                    )) {
                        Text("\(item.1) (\(item.2 == .positive ? "costs" : "grants") \(item.3) \(unit))")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!selected && !draft.canAddQuality(kind: item.2, karmaValue: item.3))
                    Text(ChargenHelpCatalog.qualityDescription(catalogKey: item.0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    var sr4ContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Contacts (SR4A Build Points)")
                .font(.headline)
            HelpCallout(text: """
                **SR4A:** every contact costs **Connection + Loyalty** BP (each 1–6). \
                Example: Connection 3 + Loyalty 5 costs **8 BP**. There is **no free CHA×3 contact pool** \
                in Build Points chargen (that free-point model is for priority editions). \
                Contacts you buy here appear under the **Contacts** tab after you finish.
                """)
            LabeledContent("Contact BP", value: "\(draft.buildPointLedger.contacts) BP")

            if draft.contacts.isEmpty {
                Text("No contacts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.contacts) { contact in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.body.weight(.medium))
                            Text("\(contact.role) · C\(contact.connection) / L\(contact.loyalty)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(draft.contactBPCost(contact)) BP")
                            .font(.caption.monospacedDigit())
                        Button(role: .destructive) {
                            draft.removeContact(id: contact.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GroupBox("Add contact") {
                TextField("Name", text: $draftContactName)
                    .textFieldStyle(.roundedBorder)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Role")
                        .font(.callout)
                        .frame(width: 44, alignment: .leading)
                    Picker("Role", selection: $draftContactRole) {
                        ForEach(contactRoleOptions, id: \.self) { role in
                            Text(role).tag(role)
                        }
                        // Keep a custom selection visible if the user typed something else previously.
                        if !contactRoleOptions.contains(draftContactRole), !draftContactRole.isEmpty {
                            Text(draftContactRole).tag(draftContactRole)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)

                    TextField("Or custom role…", text: $draftContactRole)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                .help("Pick a contact archetype from the SR4A catalog, or type a custom role.")

                Stepper("Connection: \(draftContactConnection)", value: $draftContactConnection, in: 1...6)
                Stepper("Loyalty: \(draftContactLoyalty)", value: $draftContactLoyalty, in: 1...6)
                let cost = SR4BuildPointEngine.contactCost(
                    connection: draftContactConnection,
                    loyalty: draftContactLoyalty
                )
                LabeledContent("Cost", value: "\(cost) BP")
                AppChromeButton.title(
                    "Add Contact",
                    help: "Spend BP for this contact",
                    isEnabled: !draftContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && draft.canAddContact(
                            connection: draftContactConnection,
                            loyalty: draftContactLoyalty
                        )
                ) {
                    let name = draftContactName.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.addContact(
                        Contact(
                            name: name,
                            role: draftContactRole.trimmingCharacters(in: .whitespacesAndNewlines),
                            loyalty: draftContactLoyalty,
                            connection: draftContactConnection
                        )
                    )
                    draftContactName = ""
                }
            }
            .onAppear {
                catalog.ensureLoaded(for: draft.edition)
                if !contactRoleOptions.contains(draftContactRole), let first = contactRoleOptions.first {
                    draftContactRole = first
                }
            }
        }
    }

    func toggleQuality(_ item: (String, String, QualityKind, Int), on: Bool) {
        if on {
            guard draft.canAddQuality(kind: item.2, karmaValue: item.3) else { return }
            if draft.generationSystem == .buildPoints {
                draft.qualities.append(
                    QualityInstance(catalogKey: item.0, name: item.1, kind: item.2, karmaValue: item.3)
                )
                draft.recomputeBuildPoints()
                return
            }
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
                QualityInstance(catalogKey: item.0, name: item.1, kind: item.2, karmaValue: item.3)
            )
        } else {
            draft.qualities.removeAll { $0.catalogKey == item.0 }
            if draft.generationSystem == .buildPoints {
                draft.recomputeBuildPoints()
                return
            }
            if item.2 == .positive {
                draft.budget.positiveQualityKarmaUsed = max(0, draft.budget.positiveQualityKarmaUsed - item.3)
            } else {
                draft.budget.negativeQualityKarmaGained = max(0, draft.budget.negativeQualityKarmaGained - item.3)
                draft.budget.karmaRemaining = max(0, draft.budget.karmaRemaining - item.3)
            }
        }
    }

    // MARK: - Resources

}
