//
//  RunDetailView+Awards.swift
//  ShadowDeck
//
//  Apply-awards flow for a run. Same view as RunDetailView.
//

import SwiftUI

extension RunDetailView {
    // MARK: - Apply awards

    func presentApplyAwardsSheet() {
        guard var current = run else { return }
        // Ensure rich-text drafts are flushed before we read/mutate the run.
        commitRichTextDrafts(force: true)
        current = run ?? current

        var charactersByID: [UUID: Character] = [:]
        for id in current.participantCharacterIDs {
            if let character = try? libraryEnvironment.library.fetch(id: id) {
                charactersByID[id] = character
            }
        }
        let preview = RunAwardApplicator.preview(run: current, charactersByID: charactersByID)
        applyAwardsPresentation = ApplyAwardsPresentation(
            runTitle: current.title,
            heatDelta: current.heatDelta,
            preview: preview
        )
    }

    func applyAwards(shares: [AwardShare], note: String, heatNote: String) {
        guard var current = run else {
            applyAwardsPresentation = nil
            return
        }
        commitRichTextDrafts(force: true)
        current = run ?? current

        var characters: [Character] = []
        var missingIDs: [UUID] = []
        for id in current.participantCharacterIDs {
            if let character = try? libraryEnvironment.library.fetch(id: id) {
                characters.append(character)
            } else {
                missingIDs.append(id)
            }
        }

        do {
            let result = try RunAwardApplicator.apply(
                run: &current,
                characters: &characters,
                shares: shares,
                note: note,
                heatNote: heatNote
            )

            // Persist characters first, then the run (applied marker last).
            var failedSaves: [String] = []
            for character in characters where result.applied.contains(where: { $0.characterID == character.id }) {
                do {
                    try libraryEnvironment.library.save(character)
                } catch {
                    failedSaves.append(character.displayTitle)
                }
            }

            if !failedSaves.isEmpty {
                errorMessage =
                    "Some character saves failed (\(failedSaves.joined(separator: ", "))). "
                    + "Verify those sheets before applying again — awards were not marked applied on the run."
                applyAwardsPresentation = nil
                // Do not save run with awardsAppliedAt if character saves failed mid-way.
                // Note: pure apply already mutated `current` in memory; reload to discard.
                reload()
                return
            }

            try libraryEnvironment.runLibrary.save(current)
            run = current
            characterSummaries = try libraryEnvironment.library.listSummaries()
            statusMessage = awardsStatusMessage(result: result, missingCount: missingIDs.count)
            errorMessage = nil
            applyAwardsPresentation = nil
        } catch {
            errorMessage = error.localizedDescription
            applyAwardsPresentation = nil
        }
    }

    func awardsStatusMessage(result: ApplyResult, missingCount: Int) -> String {
        let nuyen = result.applied.map(\.nuyen).reduce(0, +)
        let karma = result.applied.map(\.karma).reduce(0, +)
        var message =
            "Applied awards to \(result.applied.count) runner(s): "
            + "\(RunSupport.formatNuyen(nuyen)) + \(karma) karma."
        if result.applied.contains(where: \.hasReputationDelta) {
            message += " Reputation updated."
        }
        if result.heatNote != nil {
            message += " Heat note logged."
        }
        if !result.skipped.isEmpty || missingCount > 0 {
            message += " Skipped \(result.skipped.count) missing."
        }
        return message
    }

    func updateRun(_ mutate: (inout Run) -> Void) {
        guard session.allowAutoSave else { return }
        guard var current = run else { return }
        mutate(&current)
        persist(current)
    }

    func persist(_ current: Run) {
        guard session.allowAutoSave else { return }
        do {
            try libraryEnvironment.runLibrary.save(current)
            // Keep local state; avoid require() if we just deleted or tore down.
            if session.allowAutoSave {
                run = current
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            // Reload last good copy if save failed (e.g. empty title).
            if session.allowAutoSave {
                reload()
            }
        }
    }

    func reload() {
        do {
            let loaded = try libraryEnvironment.runLibrary.require(runID)
            run = loaded
            loadRichTextDrafts(from: loaded)
            characterSummaries = try libraryEnvironment.library.listSummaries()
            campaignOptions = try libraryEnvironment.campaignLibrary.listSummaries(includeArchived: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            run = nil
        }
    }

    func goBack() {
        commitRichTextDrafts(force: true)
        onBack()
    }

    func deleteRun() {
        // 1) Kill all auto-save paths immediately (reference flag).
        // 2) Delete in the store (also blocks re-insert by id in RunLibrary).
        // 3) Leave — onDisappear / delayed NotesEditor commits cannot resurrect.
        session.allowAutoSave = false
        let idToDelete = runID
        run = nil
        do {
            try libraryEnvironment.runLibrary.delete(id: idToDelete)
            libraryEnvironment.refreshRunCount()
            onDeleted()
        } catch {
            // Deletion failed — allow editing again and reload.
            session.allowAutoSave = true
            errorMessage = error.localizedDescription
            reload()
        }
    }
}
