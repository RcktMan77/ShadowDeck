# ShadowDeck Table-Readiness Audit

**Date:** 2026-08-05  
**Branch:** `develop` @ `7964147` (+ local QA helpers: in-memory launch flag, domain probe tests)  
**App build:** Debug, Xcode 26.3 / Apple Swift 6.2.4  
**Host:** macOS 15.7.7 (24G720)  
**Apple Intelligence / on-device Foundation Models:** **Unavailable** on this OS (PDF draft uses heuristic fallback only)  
**Library isolation:** Audit used **ephemeral in-memory libraries only** (`LibraryEnvironment.ephemeral()`, unit tests). Live container under `~/Library/Containers/com.shadowdeck.ShadowDeck/` was **not** used as the working library. A temporary launch flag `SHADOWDECK_IN_MEMORY_LIBRARY=1` was added so interactive QA can also avoid the live store.

---

## A. Executive summary

### Ready to share on r/Shadowrun? **Not yet**

The product is **substantially playable** for an **SR5-first** table loop (sheet, dice, lifestyle, campaigns/runs, awards, player briefing, Rules Reference). Unit tests and domain probes pass for the core engines. However, **SR4 chargen is openly simplified**, **import fixtures are SR5-only**, and a few trust/edition gaps would draw skeptical “vibe-coded” comments from r/Shadowrun.

### Top 5 blockers (before a confident public share)

1. **P1 — SR4 Build Points chargen is incomplete / approximate**  
   Wizard copy admits simplified BP pools (“full BP accounting expands later”). Not a crash, but a weak first impression for SR4 users.

2. **P1 — No shippable SR4/SR6 import fixtures in-repo**  
   Automated import coverage is SR5-only (`minimal_sr5.json` / `.chum5`). Visitors on other editions cannot be guided to a “open this file” path without bringing their own Chummer export.

3. **P2 — SR6 Edge model is simplified**  
   Roller uses a session “remaining / rating” pool with refresh; house rule `simplifiedSR6Edge` defaults on. Acceptable if clearly labeled in-product; currently easy to misread as full SR6 Edge economy.

4. **P2 — Advancement `canRaise` is rating-only (engine)**  
   Preview `canRaise` ignores karma; **Buy Now** UI does disable when `karmaCost > karmaAvailable`. Cart/add path should stay consistent so users never plan free raises.

5. **P2 — Experimental PDF → run draft**  
   Works as heuristic on this Mac; AI path untested here. Fine as experimental, but public share should not oversell AI.

### Edition scorecard

| Area | SR4 | SR5 | SR6 |
|------|-----|-----|-----|
| **Chargen** | **Weak** (BP simplified) | **Pass** (priority + tests) | **Pass** (priority + tests) |
| **Play sheet** | **Pass** (limits hidden; derived card) | **Pass** (limits shown) | **Pass** (session Edge note) |
| **Dice engine** | **Pass** (half-or-more glitch) | **Pass** (more-than-half) | **Pass** hits; **Weak** Edge UX |
| **Import** | **Weak** (no fixture; real Chummer may work) | **Pass** (fixtures + Ghostwire when present) | **Weak** (no fixture) |

---

## B. Findings table

| ID | Sev | Edition(s) | Steps | Expected | Actual | Location / evidence | Suggested fix |
|----|-----|------------|-------|----------|--------|---------------------|---------------|
| F1 | **P1** | SR4 | New Character → SR4 → Priorities/attributes | Full Build Points accounting | Simplified attribute/skill/nuyen pools; HelpCallout: “full BP accounting expands later”; code comment “BP-ish placeholder” | `GenerationWizardView` BP callout; `GenerationDraft.recomputeBudgetsFromPriorities` | Complete SR4 BP tables or gate SR4 with “beta / simplified” in edition picker |
| F2 | **P2** | SR4, SR6 | Look for import samples in repo | Fixtures per edition | Only `Fixtures/minimal_sr5.json` + `.chum5` | `ShadowDeckTests/Fixtures/` | Add minimal SR4/SR6 Chummer JSON fixtures + Load Samples already covers play-sheet peers |
| F3 | **P2** | SR6 | Open dice on SR6 sample; use Edge | Full SR6 Edge rules or clear “simplified” banner | Session remaining pool + `refreshEdge()`; `simplifiedSR6Edge` default true | `DiceRollerController`, `DiceHouseRules` | Always surface active Edge model line in roller chrome for SR6 |
| F4 | **P3** | All | Advancement with 0 karma | Unaffordable raises clearly blocked | Engine `canRaise` is rating-max only; **Buy Now** disables when cost &gt; available; apply throws | `AdvancementEngine` + `AdvancementPlannerView` | Optional `canAfford` on preview for cart/add consistency |
| F5 | **P2** | — | Experimental PDF draft without AI | Stable heuristic draft | Heuristic works (domain tests + prior live PDF tests); AI N/A on 15.7.7 | `RunDraftGenerator` | Keep Experimental label; note heuristic in empty AI state |
| F6 | **P3** | All | Empty Characters / Runs / Books | Clear next step | Copy-only empty states (no CTA buttons by design) | `CharacterLibraryBrowserView`, `RunsListView`, `LibraryShelfBrowseView` | OK if intentional; ensure Create sidebar is discoverable on first launch |
| F7 | **P3** | All | Cold launch | Fast to library | Splash every cold launch (skip with click/key) | `ShadowDeckApp` | Fine; document in Tips if users complain |
| F8 | **P3** | SR5 catalog | Equip catalog gear on non-SR5 | Edition-safe catalog | Bundled catalog is SR5-oriented | `CatalogStore` / README | Label catalog “SR5 reference” in UI if not already |
| F9 | **Info** | — | QA without personal library | Documented path | `SHADOWDECK_IN_MEMORY_LIBRARY=1` (new) uses ephemeral store | `ShadowDeckApp.init` | Keep for maintainers; document in developer docs |
| F10 | **Pass** | All | Player briefing with GM fields | Spoilers hidden | Markdown omits opposition/gmNotes/complications heat | `PlayerBriefingMarkdownTests` | — |
| F11 | **Pass** | SR5 | Campaign delete | Runs Unassigned, not deleted | `deleteCampaignUnassigningRuns` + confirmation copy | `CampaignsListView` | — |
| F12 | **Pass** | SR5 | Apply awards | Nuyen/karma/SC applied once | Domain probe + `RunAwardApplicatorTests` | — | — |
| F13 | **Pass** | All | Sample characters | One per edition | `SampleCharacters` + Load Samples | — | — |

---

## C. Flow scorecards

### Chargen
| | Result |
|--|--------|
| **SR5** | **Pass** — Priority path covered by `GenerationTests`; unique letters, budgets, steppers, build-to-character |
| **SR6** | **Pass** — Priority default; same wizard infrastructure |
| **SR4** | **Weak** — BP mode with simplified pools and explicit “expands later” copy (**F1**) |
| **House rules** | Present in wizard/browser; dice house rules re-roll covered by unit tests |

### Sheet
| | Result |
|--|--------|
| **Open samples** | Load Samples seeds SR4/SR5/SR6 with portraits |
| **Limits** | SR5 shows Physical/Mental/Social; SR4/SR6 show Derived + edition note (**not** wrong SR5 limits presented as truth) |
| **Persistence** | Live path uses SwiftData; ephemeral probe saves/loads characters and runs |

### Dice
| | Result |
|--|--------|
| **Hits** | 5–6 core; hits-on-4 house rule works all editions |
| **Glitch** | SR4 half-or-more vs SR5/SR6 more-than-half verified |
| **Edge** | Spend/remaining model works; SR6 not full rulebook Edge (**F3**) |
| **Shortcuts** | ⌘D registered in app commands |

### Runs / Campaigns
| | Result |
|--|--------|
| **Create campaign + blank run + template run** | Domain probe **Pass** |
| **Contacts (Johnson)** | Seeded on run; client display prefers Johnson link (existing unit tests) |
| **Session log / complete / awards** | Awards apply nuyen/karma/SC; double-apply guard in engine |
| **Filter / Unassigned** | Campaign delete moves runs to Unassigned |
| **Empty runs** | “No Runs Yet” without duplicate CTA |

### Awards / Reputation
| | Result |
|--|--------|
| **Apply** | Explicit apply path; confirmation UI exists (`ApplyAwardsSheet`) |
| **Rep deltas** | Street Cred / Notoriety / PA on shares |
| **Heat** | Run-level heat; optional heat note on apply |

### Rules / PDF
| | Result |
|--|--------|
| **Seed cards** | `RulesReferenceStore.loadBundled` smoke test; ≥80 cards |
| **Calculators** | Drain/Overwatch/etc. present in UI modules |
| **PDF shelf** | Local-only; empty state clear; search concurrency capped |
| **PDF draft (experimental)** | Heuristic path tested; AI not available on this host |

### Import / Export
| | Result |
|--|--------|
| **SR5 JSON/chum5 fixtures** | **Pass** |
| **SR4/SR6 fixtures** | **Missing** (**F2**) |
| **Package round-trip** | Portable document / package tests pass |
| **PDF character sheet** | Export sheet tests pass |

---

## D. “Vibe coding” trust checklist

| Item | Status |
|------|--------|
| Dead controls / stub screens | No full stub destinations found; empty states are intentional copy-only |
| Placeholder / TODO user copy | SR4 BP “expands later” is **honest** unfinished work (**F1**), not silent wrongness |
| Advancement “custom skill placeholder” status string | Internal/status tone — P3 polish |
| README vs app | README claims experimental PDF draft — present; SR4 BP incompleteness **not** called out in product README |
| Edition options that no-op | Priority vs BP switches correctly; SR4 BP numbers are **approximate** (trust risk) |
| Wrong formula presented as truth | Limits correctly gated by `usesLimits`; glitch thresholds edition-aware in engine |
| Debug strings in UI | None found in primary chrome |
| AI draft oversold | Experimental labeling present in menus/sheet |

---

## E. Recommended fix order (PR stack)

1. **PR-A (P1):** SR4 Build Points honesty + path  
   - Either finish minimal real BP tracking **or** mark SR4 chargen “Simplified / Beta” on the edition card and in README Features.
2. **PR-B (P2):** SR6 Edge chrome  
   - Always show “Simplified session Edge” (or full rules if implemented) on the dice panel for SR6.
3. **PR-C (P2):** Import fixtures  
   - Minimal SR4 + SR6 Chummer JSON for tests and optional “Import sample file” docs.
4. **PR-D (P3):** Advancement `canAfford` on preview; cart add disabled when unaffordable.
5. **PR-E (P3):** Empty-state discoverability + catalog “SR5 reference” badge  
6. **Then** re-run this scorecard + 30-minute manual script before r/Shadowrun share.

---

## F. Edition ruleset ↔ UI consistency

| Check | SR4 | SR5 | SR6 |
|-------|-----|-----|-----|
| **1. Chargen options** | BP default; simplified pools (**F1**) | Priority tables present | Priority tables present |
| **2. Sheet / derived** | Limits **hidden**; armor/movement + non-limit caption | Limits shown | Limits **hidden**; session Edge caption |
| **3. Dice defaults** | Glitch half-or-more | Glitch more-than-half; hits 5–6 | Same hit/glitch as SR5; Edge simplified (**F3**) |
| **4. Advancement costs** | Skill 3→4 = 8 karma (engine) | 8 karma | **20** karma (engine) |
| **5. Rules Reference** | Shared seed with edition notes (filter/edition tags in seed) | Same | Same |

**SR5-shaped risk:** Chargen wizard chrome is shared (good), but SR4 BP **numbers** are not true BP accounting. Dice Edge UI is one model for all editions (OK for SR4/5, simplified for SR6).

---

## G. Method notes & isolation

| Method | Used |
|--------|------|
| Full unit test suite | **Pass** (pre-audit) |
| Domain table-readiness tests (`TableReadinessDomainTests`) | **Pass** (campaign → awards → briefing; dice; lifestyle shortfall; import fixture gap) |
| Code inspection | Generation BP, limits card, dice controller, empty states, shortcuts, briefing spoilers |
| Interactive UI click-through | Limited: confirmed `SHADOWDECK_IN_MEMORY_LIBRARY=1` launches without writing a live library session; full visual matrix remains for maintainer script below |
| Personal live library | **Not used / not modified** |

### Environment for safe interactive QA

```bash
# After Debug build:
export SHADOWDECK_IN_MEMORY_LIBRARY=1
/path/to/ShadowDeck.app/Contents/MacOS/ShadowDeck
```

Uses empty in-memory SwiftData; quitting discards data. **Do not** use this flag for real campaigns.

---

## H. Manual 30–45 minute click-through script

Use **in-memory** launch (above). Skip splash with click/key.

### SR5 (~12 min)
1. Load Samples → open Elena (SR5 mage).  
2. Confirm Summary: attributes, limits (Phys/Ment/Soc), karma, nuyen.  
3. Change a skill rank; switch character and back — rank persisted (memory session).  
4. ⌘D — roll a skill; note hits. House Rules → enable hits on 4+ → re-roll → more hits possible.  
5. Advancement: set karma if needed; plan one skill raise; apply; ledger line.  
6. Lifestyle: add Low lifestyle; Process 1 month with enough nuyen; then force shortfall (optional).

### SR4 / SR6 (~10 min)
7. Open Marcus (SR4) — **Derived** not Limits; note BP chargen if New Character → SR4.  
8. Open Jordan (SR6) — Derived + Edge session note; dice Edge remaining/refresh.  
9. New Character for each edition through edition + metatype + priorities/BP — abandon if long; note BP callout on SR4.

### Runs (~10 min)
10. New Campaign → New Run blank under it.  
11. New Run from template.  
12. Add participant + Johnson contact + objective + player summary + GM note.  
13. Complete run → Apply Awards (¥, karma, +1 SC).  
14. Player briefing — no opposition/GM text; Copy Markdown.  
15. Delete campaign — runs become Unassigned.

### Rules (~5 min)
16. ⌘R — search “glitch”, “karma”, “drain”.  
17. Open a calculator.  
18. Library mode — empty shelf copy; optional drop a legal-owned PDF if available (not required).

### Shortcuts (~2 min)
19. ⌘N, ⌘O, ⌘D, ⌘R, ⌘⇧R — each opens expected path.

---

## I. Success criteria checklist

- [x] All three editions exercised (domain + samples + generation system defaults; interactive matrix script provided)  
- [x] Full run loop domain-exercised (campaign → template → awards → briefing → unassign)  
- [x] This document written with reproducible findings  
- [x] Clear **Not yet** recommendation for public share  
- [x] Prioritized fix list for a human guidance pass  

---

## J. Appendix — commands used

```bash
git checkout develop && git pull
xcodebuild -scheme ShadowDeck -destination 'platform=macOS' test
xcodebuild -scheme ShadowDeck -destination 'platform=macOS' \
  -only-testing:ShadowDeckTests/TableReadinessDomainTests test
export SHADOWDECK_IN_MEMORY_LIBRARY=1
# launch Debug ShadowDeck.app binary
```
