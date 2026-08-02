//
//  ApplyAwardsSheet.swift
//  ShadowDeck
//
//  Confirmation sheet for applying run nuyen/karma awards (and optional
//  reputation / heat note) to linked characters.
//

import SwiftUI

/// Payload for `sheet(item:)` so Apply Awards never presents an empty content tree.
struct ApplyAwardsPresentation: Identifiable, Hashable {
    let id = UUID()
    var runTitle: String
    var heatDelta: Int
    var preview: AwardPreview
}

struct ApplyAwardsSheet: View {
    let runTitle: String
    let preview: AwardPreview
    /// Run-level heat Δ already stored on the run (shown as context only).
    var runHeatDelta: Int = 0
    var onCancel: () -> Void
    var onConfirm: (_ shares: [AwardShare], _ note: String, _ heatNote: String) -> Void

    @State private var editableShares: [AwardShare] = []
    @State private var note: String = ""
    @State private var heatNote: String = ""
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    totals
                    sharesList
                    if !preview.skipped.isEmpty {
                        skippedSection
                    }
                    Text("Remainder ¥/karma goes to the first listed runner. Reputation deltas are optional and per runner.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    heatNoteField
                    noteField
                    if !preview.canApply, !preview.blockReason.isEmpty {
                        Text(preview.blockReason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(20)
        }
        // Firm size so macOS sheet chrome does not collapse to a blank white chip.
        .frame(width: 540, height: 560)
        .onAppear {
            if editableShares.isEmpty {
                editableShares = preview.perCharacter
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apply Awards")
                .font(.title2.weight(.semibold))
            Text(runTitle.isEmpty ? "Untitled run" : runTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Using \(preview.sourceLabel) payout. This credits linked runners and cannot be undone from the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var totals: some View {
        HStack(spacing: 16) {
            metric("Total nuyen", RunSupport.formatNuyen(preview.totalNuyen))
            metric("Total karma", "\(preview.totalKarma)")
            metric("Runners", "\(preview.perCharacter.count)")
            if runHeatDelta != 0 {
                metric("Run heat Δ", runHeatDelta >= 0 ? "+\(runHeatDelta)" : "\(runHeatDelta)")
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }

    private var sharesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Per runner")
                .font(.subheadline.weight(.semibold))
            if editableShares.isEmpty {
                Text("No available runners to credit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(editableShares.indices), id: \.self) { index in
                        shareRow(index: index)
                        if index < editableShares.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func shareRow(index: Int) -> some View {
        let share = editableShares[index]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(share.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(RunSupport.formatNuyen(share.nuyen))
                    .font(.callout.monospacedDigit())
                Text("\(share.karma) karma")
                    .font(.callout.monospacedDigit())
                    .frame(width: 72, alignment: .trailing)
            }
            HStack(spacing: 10) {
                repField("SC", value: streetCredBinding(index))
                repField("Not", value: notorietyBinding(index))
                repField("PA", value: publicAwarenessBinding(index))
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 6)
    }

    private func repField(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .font(.caption.monospacedDigit())
                .help("Reputation delta (0 = no change)")
        }
    }

    private func streetCredBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { editableShares.indices.contains(index) ? editableShares[index].streetCredDelta : 0 },
            set: { v in
                guard editableShares.indices.contains(index) else { return }
                editableShares[index].streetCredDelta = v
            }
        )
    }

    private func notorietyBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { editableShares.indices.contains(index) ? editableShares[index].notorietyDelta : 0 },
            set: { v in
                guard editableShares.indices.contains(index) else { return }
                editableShares[index].notorietyDelta = v
            }
        )
    }

    private func publicAwarenessBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { editableShares.indices.contains(index) ? editableShares[index].publicAwarenessDelta : 0 },
            set: { v in
                guard editableShares.indices.contains(index) else { return }
                editableShares[index].publicAwarenessDelta = v
            }
        )
    }

    private var skippedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skipped")
                .font(.subheadline.weight(.semibold))
            ForEach(preview.skipped) { item in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Missing runner")
                        .font(.caption)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(item.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.characterID.uuidString.prefix(8) + "…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var heatNoteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Heat note (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. +1 heat from messy exit — Lone Star scanning the zone", text: $heatNote)
                .textFieldStyle(.roundedBorder)
            Text("Logged as a Heat session entry. Run heat Δ is already on Payout & Heat.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. Paid after debrief", text: $note)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Spacer()

            Button {
                guard !isApplying else { return }
                isApplying = true
                onConfirm(editableShares, note, heatNote)
            } label: {
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Apply")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!preview.canApply || isApplying)
        }
    }
}
