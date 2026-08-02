//
//  ContentView+Marketing.swift
//  ShadowDeck
//
//  Marketing screenshot / GIF storyboard drivers (extracted from ContentView).
//

import Foundation
import SwiftUI

extension ContentView {
    /// Drive UI into known-good states for README marquee captures.
    /// Capture launches with an in-memory sample-only library (`LibraryEnvironment.marketingCapture()`).
    func handleMarketingPhase(_ phase: MarketingScreenshotExporter.Phase, step: Int?) {
        switch phase {
        case .splash:
            break
        case .library:
            marketingOpenRunID = nil
            selection = .characters
            selectedCharacterID = nil
            libraryQuery = ""
            refresh()
        case .generationRole:
            marketingOpenRunID = nil
            selection = .newCharacter
            selectedCharacterID = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                NotificationCenter.default.post(name: AppCommand.wizardShowRoleStep, object: nil)
            }
        case .characterSheet:
            marketingOpenRunID = nil
            selection = .characters
            refresh()
            // Marquee “play sheet” stays on Summary (default tab).
            selectedCharacterID = SampleCharacters.sr5ID
        case .diceRoller:
            marketingOpenRunID = nil
            selection = .characters
            refresh()
            selectedCharacterID = SampleCharacters.sr5ID
            // Let the sheet mount, then Skills + roller with a completed skill roll.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                NotificationCenter.default.post(name: AppCommand.marketingShowDiceRoller, object: nil)
            }
        case .runLibrary:
            // Kept for phase completeness; no longer used as a still marquee.
            selectedCharacterID = nil
            marketingOpenRunID = nil
            selection = .runs
            refresh()
        case .runGif:
            applyRunGifStoryboard(step: step ?? 0)
        case .advanceGif:
            applyAdvanceGifStoryboard(step: step ?? 0)
        case .finished:
            break
        }
    }

    /// Storyboard for `07-run-mission-flow.gif`:
    /// library → create → fill → team → active/log → objectives → complete → library list.
    func applyRunGifStoryboard(step: Int) {
        selectedCharacterID = nil
        do {
            switch step {
            case 0:
                // Empty Run Library (start of flow).
                try clearMarketingRuns()
                marketingOpenRunID = nil
                marketingForceRunListOnly = true
                selection = .runs
                refresh()
                return

            case 1:
                // Create a new planning job and open detail.
                try clearMarketingRuns()
                marketingForceRunListOnly = false
                var run = Run.makeDraft(title: "New Run")
                run.status = .planning
                run.participantCharacterIDs = []
                run.sessionLog = []
                run.outcomeSummary = ""
                run.actualPayout = nil
                run.objectives = []
                try libraryEnvironment.runLibrary.save(run)
                libraryEnvironment.refreshRunCount()
                marketingOpenRunID = run.id
                selection = .runs
                refresh()
                NotificationCenter.default.post(name: AppCommand.marketingReloadRun, object: nil)
                postMarketingFocus(anchor: "overview", highlight: nil)
                return

            default:
                break
            }

            // List is oldest-first; storyboard wants the latest minted marketing run.
            guard let runID = try libraryEnvironment.runLibrary.listSummaries().last?.id else {
                statusMessage = "Screenshot run GIF: no sample run"
                return
            }
            var run = try libraryEnvironment.runLibrary.require(runID)
            var focusAnchor = "overview"
            var focusHighlight: String?
            var returnToLibrary = false

            switch step {
            case 2:
                // Fill briefing fields (still Planning).
                marketingForceRunListOnly = false
                run.title = "Datasteal on Renraku Arcology"
                run.client = "Mr. Johnson (Ares cut-out)"
                run.location = "Downtown Seattle · Renraku Arcology"
                run.tags = ["Datasteal", "Seattle"]
                run.expectedPayout = RunPayout(nuyen: 18_000, karma: 6)
                run.objectives = [
                    RunObjective(text: "Extract paydata from host 77-A", isPrimary: true, status: .pending),
                    RunObjective(text: "No civilian casualties", isPrimary: false, status: .pending),
                ]
                run.opposition = "High-threat Matrix IC; two corp security mage teams on rotation."
                focusAnchor = "overview"
            case 3:
                marketingForceRunListOnly = false
                focusAnchor = "team"
                focusHighlight = "team"
            case 4:
                marketingForceRunListOnly = false
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                focusAnchor = "team"
                focusHighlight = "team"
            case 5:
                marketingForceRunListOnly = false
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                run.applyStatus(.active)
                focusAnchor = "sessionLog"
                focusHighlight = "sessionLog"
            case 6:
                marketingForceRunListOnly = false
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                run.applyStatus(.active)
                run.sessionLog = [
                    RunLogEntry(kind: .session, text: "Session 1 — matrix recon complete; host footprint mapped."),
                ]
                focusAnchor = "sessionLog"
            case 7:
                marketingForceRunListOnly = false
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                run.applyStatus(.active)
                run.sessionLog = [
                    RunLogEntry(kind: .session, text: "Session 1 — matrix recon complete; host footprint mapped."),
                ]
                focusAnchor = "objectives"
                focusHighlight = "objectives"
            case 8:
                marketingForceRunListOnly = false
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                run.applyStatus(.active)
                if let i = run.objectives.firstIndex(where: \.isPrimary) {
                    run.objectives[i].status = .complete
                }
                run.sessionLog = [
                    RunLogEntry(kind: .session, text: "Session 1 — matrix recon complete; host footprint mapped."),
                    RunLogEntry(kind: .objective, text: "Primary objective complete — paydata secured."),
                ]
                focusAnchor = "objectives"
                focusHighlight = "objectives"
            case 9:
                // Outcome + Completed status (still on detail).
                marketingForceRunListOnly = false
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                if let i = run.objectives.firstIndex(where: \.isPrimary) {
                    run.objectives[i].status = .complete
                }
                run.sessionLog = [
                    RunLogEntry(kind: .session, text: "Session 1 — matrix recon complete; host footprint mapped."),
                    RunLogEntry(kind: .objective, text: "Primary objective complete — paydata secured."),
                ]
                run.outcomeSummary = "Paydata extracted. Team extraction clean; Johnson paid full nuyen."
                run.actualPayout = RunPayout(nuyen: 18_000, karma: 6)
                run.applyStatus(.completed)
                focusAnchor = "outcome"
                focusHighlight = "outcome"
            default:
                // Steps 10–11: force list mode with completed run row (status + team + payout).
                run.participantCharacterIDs = [SampleCharacters.sr5ID, SampleCharacters.sr4ID]
                if let i = run.objectives.firstIndex(where: \.isPrimary) {
                    run.objectives[i].status = .complete
                }
                run.sessionLog = [
                    RunLogEntry(kind: .session, text: "Session 1 — matrix recon complete; host footprint mapped."),
                    RunLogEntry(kind: .objective, text: "Primary objective complete — paydata secured."),
                ]
                run.outcomeSummary = "Paydata extracted. Team extraction clean; Johnson paid full nuyen."
                run.actualPayout = RunPayout(nuyen: 18_000, karma: 6)
                run.applyStatus(.completed)
                returnToLibrary = true
            }

            try libraryEnvironment.runLibrary.save(run)
            libraryEnvironment.refreshRunCount()

            if returnToLibrary {
                marketingOpenRunID = nil
                marketingForceRunListOnly = true
                selection = .runs
                libraryEnvironment.refreshRunCount()
                refresh()
            } else {
                marketingForceRunListOnly = false
                marketingOpenRunID = runID
                selection = .runs
                refresh()
                NotificationCenter.default.post(name: AppCommand.marketingReloadRun, object: nil)
                postMarketingFocus(anchor: focusAnchor, highlight: focusHighlight)
            }
        } catch {
            statusMessage = "Screenshot run GIF failed: \(error.localizedDescription)"
        }
    }

    func clearMarketingRuns() throws {
        let runs = try libraryEnvironment.runLibrary.listSummaries()
        for summary in runs {
            try libraryEnvironment.runLibrary.delete(id: summary.id)
        }
        libraryEnvironment.refreshRunCount()
        marketingOpenRunID = nil
    }

    /// Storyboard for `08-advancement-planner.gif` — scroll skills, highlight Add/Apply.
    func applyAdvanceGifStoryboard(step: Int) {
        marketingOpenRunID = nil
        selection = .characters
        selectedCharacterID = SampleCharacters.sr5ID
        do {
            var c = try libraryEnvironment.library.require(SampleCharacters.sr5ID)
            let rules = RulesRegistry.rules(for: c.edition)
            var focusAnchor = "skills"
            var focusHighlight: String?

            // Stable ranks for re-runs.
            func resetRanks() {
                if let i = c.skills.firstIndex(where: { $0.catalogKey == "perception" }) {
                    c.skills[i].rating = 3
                }
                if let i = c.skills.firstIndex(where: { $0.catalogKey == "assensing" }) {
                    c.skills[i].rating = 4
                }
            }

            switch step {
            case 0:
                // Top of planner — karma budget, empty plan.
                resetRanks()
                c.karmaAvailable = 40
                c.karmaTotal = max(c.karmaTotal, 40)
                c.advancementPlanItems = []
                focusAnchor = "planHeader"
                focusHighlight = nil
            case 1:
                // Scroll to skills list (before adding).
                resetRanks()
                c.karmaAvailable = 40
                c.advancementPlanItems = []
                focusAnchor = "skills"
                focusHighlight = "skill-perception"
            case 2:
                // Perception added after “click” highlight.
                resetRanks()
                c.karmaAvailable = 40
                if let item = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "perception", rules: rules
                ) {
                    c.advancementPlanItems = [item]
                }
                focusAnchor = "skills"
                focusHighlight = "skill-perception"
            case 3:
                // Highlight second skill control.
                resetRanks()
                c.karmaAvailable = 40
                if let item = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "perception", rules: rules
                ) {
                    c.advancementPlanItems = [item]
                }
                focusAnchor = "skills"
                focusHighlight = "skill-assensing"
            case 4:
                // Both raises in plan; still viewing skills.
                resetRanks()
                c.karmaAvailable = 40
                var plan: [AdvancementPlanItem] = []
                if let a = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "perception", rules: rules
                ) { plan.append(a) }
                if let b = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "assensing", rules: rules
                ) { plan.append(b) }
                c.advancementPlanItems = plan
                focusAnchor = "skills"
            case 5:
                // Scroll/focus plan header + highlight Apply.
                resetRanks()
                c.karmaAvailable = 40
                var plan: [AdvancementPlanItem] = []
                if let a = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "perception", rules: rules
                ) { plan.append(a) }
                if let b = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "assensing", rules: rules
                ) { plan.append(b) }
                c.advancementPlanItems = plan
                focusAnchor = "planHeader"
                focusHighlight = "applyPlan"
            case 6:
                // Same pre-apply frame (metrics emphasis).
                resetRanks()
                c.karmaAvailable = 40
                var plan: [AdvancementPlanItem] = []
                if let a = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "perception", rules: rules
                ) { plan.append(a) }
                if let b = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "assensing", rules: rules
                ) { plan.append(b) }
                c.advancementPlanItems = plan
                focusAnchor = "planHeader"
                focusHighlight = "applyPlan"
            default:
                // Applied: karma down, ranks up, cart clear, ledger row.
                resetRanks()
                c.karmaAvailable = 40
                var plan: [AdvancementPlanItem] = []
                if let a = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "perception", rules: rules
                ) { plan.append(a) }
                if let b = AdvancementEngine.makeSkillRaiseItem(
                    character: c, catalogKey: "assensing", rules: rules
                ) { plan.append(b) }
                try AdvancementEngine.apply(items: plan, to: &c, rules: rules)
                c.advancementPlanItems = []
                focusAnchor = "skills"
                focusHighlight = nil
            }

            try libraryEnvironment.library.save(c)
            refresh()
            NotificationCenter.default.post(name: AppCommand.characterSheetShowAdvanceTab, object: nil)
            NotificationCenter.default.post(name: AppCommand.marketingReloadCharacter, object: nil)
            postMarketingFocus(anchor: focusAnchor, highlight: focusHighlight)
        } catch {
            statusMessage = "Screenshot advance GIF failed: \(error.localizedDescription)"
        }
    }

    func postMarketingFocus(anchor: String, highlight: String?) {
        var info: [AnyHashable: Any] = ["anchor": anchor]
        if let highlight { info["highlight"] = highlight }
        // Delay so views finish reload before scrolling.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            NotificationCenter.default.post(
                name: AppCommand.marketingFocus,
                object: nil,
                userInfo: info
            )
        }
    }

}
