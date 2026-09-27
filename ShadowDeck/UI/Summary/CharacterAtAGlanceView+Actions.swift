//
//  CharacterAtAGlanceView+Actions.swift
//  ShadowDeck
//
//  Sheet mutations: story, attributes, damage, portrait, export, karma, delete.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension CharacterAtAGlanceView {
    // MARK: - Actions / mutations

    func reload() {
        do {
            character = try libraryEnvironment.library.fetch(id: characterID)
            notesDraft = character?.notes ?? ""
            if let c = character {
                conceptDraft = c.concept
                backgroundDraft = resolvedBackground(for: c)
                // Lift legacy background out of notes once, if dedicated field is empty.
                // Defer save so we don't nest Observable/state publishes during onAppear.
                if c.background == nil || c.background?.isEmpty == true,
                   let legacy = CharacterGlanceStorySection.extractLegacyBackground(from: c.notes) {
                    Task { @MainActor in
                        self.updateCharacter { char in
                            char.background = legacy
                        }
                    }
                }
                errorMessage = nil
            } else {
                errorMessage = "Character not found."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commitStory() {
        updateCharacter({ c in
            c.concept = conceptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let bg = backgroundDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            c.background = bg.isEmpty ? nil : bg
        }, status: "Story updated.")
        isEditingStory = false
    }

    func updateCharacter(_ mutate: (inout Character) -> Void, status: String? = nil) {
        guard var c = character else { return }
        mutate(&c)
        c.touch()
        do {
            try libraryEnvironment.library.save(c)
            character = try libraryEnvironment.library.fetch(id: characterID)
            // Keep notes draft if we didn't intentionally change notes via editor.
            if let fresh = character, notesDraft != fresh.notes, status != nil {
                // no-op
            }
            if let status { statusMessage = status }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func adjustAttribute(_ id: AttributeID, by delta: Int) {
        updateCharacter({ c in
            // Edit base only; effective = base + active modifiers.
            let next = c.attributes[id] + delta
            let bounds = rules.metatypeProfile(c.metatype).bounds(for: id)
            let maxAllowed = ValidationHelpers.augmentedAttributeMaximum(
                naturalMaximum: bounds.maximum,
                houseRules: c.houseRules
            )
            c.attributes[id] = min(max(next, bounds.minimum), maxAllowed)
        }, status: "\(id.displayName) base updated.")
    }

    func setPhysicalDamage(_ damage: Int) {
        let maxBoxes = derived.condition.physicalBoxes
        updateCharacter({ c in
            var track = c.conditionTrack ?? ConditionTrack()
            track.setPhysicalDamage(damage, maxBoxes: maxBoxes)
            c.conditionTrack = track
        }, status: damage == 0 ? "Physical track cleared." : "Physical damage set to \(min(damage, maxBoxes)).")
    }

    func setStunDamage(_ damage: Int) {
        let maxBoxes = derived.condition.stunBoxes
        updateCharacter({ c in
            var track = c.conditionTrack ?? ConditionTrack()
            track.setStunDamage(damage, maxBoxes: maxBoxes)
            c.conditionTrack = track
        }, status: damage == 0 ? "Stun track cleared." : "Stun damage set to \(min(damage, maxBoxes)).")
    }

    func commitNotesIfNeeded(force: Bool = false) {
        guard var c = character else { return }
        guard force || c.notes != notesDraft else { return }
        c.notes = notesDraft
        c.touch()
        do {
            try libraryEnvironment.library.save(c)
            character = try libraryEnvironment.library.fetch(id: characterID)
            if force { statusMessage = "Notes saved." }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyPortrait(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                errorMessage = "Selected image was empty."
                return
            }
            guard data.count < 8 * 1024 * 1024 else {
                errorMessage = "Image must be under 8 MB."
                return
            }
            guard NSImage(data: data) != nil else {
                errorMessage = "Could not read that file as an image."
                return
            }
            guard var c = character else { return }
            let ext = url.pathExtension.lowercased()
            c.avatar.inlineData = data
            c.avatar.mimeType = AvatarStoragePolicy.mimeType(forFileExtension: ext)
            // Prefer real multi-frame detection over extension alone (covers APNG / mislabeled files).
            c.avatar.isAnimated = GIFDecoder.isAnimatedImageData(data) || ext == "gif"
            c.touch()
            try libraryEnvironment.library.save(c, avatarData: data)
            character = try libraryEnvironment.library.fetch(id: characterID)
            statusMessage = "Portrait updated."
            errorMessage = nil
        } catch {
            errorMessage = "Portrait failed: \(error.localizedDescription)"
        }
    }

    func exportPDFSheet() {
        guard let c = character else { return }
        let report = CampaignSheetReport.build(for: c)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = c.streetName.isEmpty ? c.name : c.streetName
        panel.nameFieldStringValue = "\(base.isEmpty ? "Runner" : base)_sheet.pdf"
        panel.canCreateDirectories = true
        panel.message = "Export a printable ShadowDeck character sheet (PDF)"
        panel.prompt = "Export PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CharacterSheetPDF.write(report: report, to: url)
            let ready = report.isCampaignReady ? "validated" : "with validation notes"
            statusMessage = "Exported PDF sheet (\(ready))."
            errorMessage = nil
        } catch {
            errorMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }

    func exportChummer() {
        guard let c = character else { return }
        let hasOriginal = c.importProvenance?.originalPayload != nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "chum5") ?? .xml]
        let base = c.streetName.isEmpty ? c.name : c.streetName
        panel.nameFieldStringValue = "\(base.isEmpty ? "Runner" : base).chum5"
        panel.canCreateDirectories = true
        panel.message = hasOriginal
            ? "Export Chummer .chum5 — uses the original imported file when available (faithful)."
            : "Best-effort regenerated Chummer .chum5 (not full Chummer parity)."
        panel.prompt = "Export .chum5"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try ChummerXMLExporter.export(c, mode: .preferOriginal)
            try result.xmlData.write(to: url, options: .atomic)
            if result.usedOriginalPayload {
                statusMessage = "Exported original Chummer file (byte-faithful import payload)."
            } else {
                statusMessage = "Exported regenerated Chummer file (\(result.fidelity.included.count) groups)."
            }
            errorMessage = nil
        } catch {
            errorMessage = "Chummer export failed: \(error.localizedDescription)"
        }
    }

    func exportPackage() {
        guard character != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.shadowdeckCharacter]
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

    func advanceKarma(by amount: Int) {
        // Manual control is award-only; spending should happen via advancement purchases.
        guard amount > 0 else { return }
        updateCharacter({ c in
            c.karmaTotal += amount
            c.karmaAvailable += amount
        }, status: "Awarded \(amount) Karma.")
        manualKarmaAwardStack.append(amount)
    }

    /// Reverts the most recent Summary-sheet manual award (both available and total).
    /// Session-only — not a full karma history; Plan spends are not on this stack.
    func undoLastManualKarmaAward() {
        guard let amount = manualKarmaAwardStack.popLast(), amount > 0 else { return }
        updateCharacter({ c in
            c.karmaTotal = max(0, c.karmaTotal - amount)
            c.karmaAvailable = max(0, c.karmaAvailable - amount)
            // Keep available from drifting above total if other edits intervened.
            if c.karmaAvailable > c.karmaTotal {
                c.karmaAvailable = c.karmaTotal
            }
        }, status: "Undid last karma award (−\(amount)).")
    }

    func deleteCharacter() {
        do {
            try libraryEnvironment.library.delete(id: characterID)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
