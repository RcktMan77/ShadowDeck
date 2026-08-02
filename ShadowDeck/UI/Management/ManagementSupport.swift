//
//  ManagementSupport.swift
//  ShadowDeck
//
//  Shared chrome for Phase 6 detailed management lists.
//

import SwiftUI

enum ManagementSupport {
    static func catalogKey(from name: String) -> String {
        name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "'", with: "")
    }

    /// Copy catalog modifiers with fresh IDs for a character instance.
    static func instanceModifiers(from entry: CatalogEntry) -> [StatModifier] {
        entry.modifiers.map {
            StatModifier(
                target: $0.target,
                amount: $0.amount,
                usesRating: $0.usesRating,
                ratingOffset: $0.ratingOffset,
                ratingTable: $0.ratingTable,
                skillKey: $0.skillKey,
                condition: $0.condition
            )
        }
    }

    /// Parse simple PP cost text like `"1"`, `"0.5"`, `"Rating"`, `"0.25 * Rating"`.
    static func parsePowerPointCost(_ text: String, level: Int) -> Decimal {
        let t = text
            .replacingOccurrences(of: "PP ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return Decimal(level) }
        if t.compare("Rating", options: .caseInsensitive) == .orderedSame {
            return Decimal(max(1, level))
        }
        if let n = Decimal(string: t.replacingOccurrences(of: ",", with: ".")) {
            return n
        }
        // "0.25 * Rating" style
        if let match = t.range(
            of: #"^([\d.]+)\s*\*\s*Rating$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let coef = String(t[match])
                .replacingOccurrences(of: "Rating", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let c = Decimal(string: coef.replacingOccurrences(of: ",", with: ".")) {
                return c * Decimal(max(1, level))
            }
        }
        return Decimal(level)
    }
}

/// Compact editor for custom item/quality/power modifiers (Phase 7).
struct ModifierDraftEditor: View {
    @Binding var modifiers: [StatModifier]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stat modifiers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    modifiers.append(StatModifier(target: .body, amount: 1))
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
                .controlSize(.small)
            }

            if modifiers.isEmpty {
                Text("Optional — e.g. +1 Strength, +2 Armor when equipped.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(modifiers.enumerated()), id: \.element.id) { index, mod in
                    HStack(spacing: 8) {
                        Picker("Target", selection: bindingTarget(at: index)) {
                            ForEach(ModifierTarget.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 120)

                        StepperControl(value: mod.amount, range: -6...6) { amount in
                            modifiers[index].amount = amount
                        }

                        Toggle("×R", isOn: bindingUsesRating(at: index))
                            .toggleStyle(.checkbox)
                            .help("Scale by item rating / power level")

                        if mod.target == .skill {
                            TextField("Skill", text: bindingSkillKey(at: index))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }

                        Button(role: .destructive) {
                            modifiers.removeAll { $0.id == mod.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func bindingTarget(at index: Int) -> Binding<ModifierTarget> {
        Binding(
            get: { modifiers[index].target },
            set: { modifiers[index].target = $0 }
        )
    }

    private func bindingUsesRating(at index: Int) -> Binding<Bool> {
        Binding(
            get: { modifiers[index].usesRating },
            set: { modifiers[index].usesRating = $0 }
        )
    }

    private func bindingSkillKey(at index: Int) -> Binding<String> {
        Binding(
            get: { modifiers[index].skillKey ?? "" },
            set: { modifiers[index].skillKey = $0.isEmpty ? nil : $0 }
        )
    }
}

/// Compact ± control for integer fields on management rows.
struct StepperControl: View {
    let value: Int
    var range: ClosedRange<Int> = 0...12
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onChange(max(range.lowerBound, value - 1))
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(value <= range.lowerBound)

            Text("\(value)")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 24)

            Button {
                onChange(min(range.upperBound, value + 1))
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(value >= range.upperBound)
        }
    }
}

struct ManagementEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

/// Soft accent ring used by marketing GIF storyboards to show “where we click”.
struct MarketingHighlightPulse: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .padding(active ? 4 : 0)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}

struct ManagementListChrome<Content: View>: View {
    let title: String
    let subtitle: String
    var onAdd: (() -> Void)?
    var addLabel: String = "Add"
    /// Opens Rules Reference (optional look-up aid for this tab).
    var onLookUp: (() -> Void)?
    var lookUpLabel: String = "Look up"
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if let onLookUp {
                    AppChromeButton.labeled(
                        lookUpLabel,
                        systemImage: "book.pages",
                        help: "Open Rules Reference for this topic"
                    ) {
                        onLookUp()
                    }
                }
                if let onAdd {
                    AppChromeButton.labeled(
                        addLabel,
                        systemImage: "plus.circle",
                        help: addLabel
                    ) {
                        onAdd()
                    }
                }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
