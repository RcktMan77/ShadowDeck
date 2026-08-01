//
//  ApplyAwardsSheet.swift
//  ShadowDeck
//
//  Confirmation sheet for applying run nuyen/karma awards to linked characters.
//

import SwiftUI

struct ApplyAwardsSheet: View {
    let runTitle: String
    let preview: AwardPreview
    var onCancel: () -> Void
    var onConfirm: (_ note: String) -> Void

    @State private var note: String = ""
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            totals
            sharesList
            if !preview.skipped.isEmpty {
                skippedSection
            }
            Text("Remainder ¥/karma goes to the first listed runner.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            noteField
            if !preview.canApply, !preview.blockReason.isEmpty {
                Text(preview.blockReason)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560, minHeight: 360, idealHeight: 480)
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
            if preview.perCharacter.isEmpty {
                Text("No available runners to credit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(preview.perCharacter) { share in
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
                        .padding(.vertical, 6)
                        if share.id != preview.perCharacter.last?.id {
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
                onConfirm(note)
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
