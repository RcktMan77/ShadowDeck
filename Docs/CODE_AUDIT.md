# ShadowDeck Codebase Health Audit

**Date:** 2026-08-01 (cleanup pass completed same day)  
**Branch audited:** `develop` after Rules Reference merge + audit PRs 1–12  
**Build:** macOS Debug — **succeeded**  
**Tests:** full scheme — **succeeded** (no failures)  
**Linters:** none configured (SwiftLint / swift-format not present; not introduced)

---

## A. Executive summary

### Overall health: **Great**

ShadowDeck is in solid shape for a solo-maintained macOS campaign app: pure domain engines, good test density on rules/import/persistence, and recent features (Runs, Lifestyle, Advancement, Dice, Apply Awards, Rules Reference) mostly follow the same “engine + UI + ledger” pattern. Audit cleanup PRs 1–12 addressed the top maintainability and performance risks (lazy catalog, unified lookup cache, Rules observation/results cache, PDF search concurrency, view extractions, AppPreferences, launch coordinator tests, accessibility on PDF chrome).

### Top 5 risks

1. **God views** (`CharacterAtAGlanceView` ~1.6k LOC, `RulesReferenceView` ~1.4k, `ContentView` ~1.2k, `RunDetailView` ~1.2k) — high regression cost and redraw surface.
2. **Catalog load on main** (`CatalogStore.init` → full `sr5_catalog.json` ~1.2 MB decode) — launch / first-browser jank risk.
3. **Rules Reference PDF path** — dual `PDFDocument` loads (reader + thumbnails), parallel multi-book search holding many large documents; memory spikes on big CRBs.
4. **Observation split brain** — `@Observable` `LibraryEnvironment` vs `ObservableObject` for Catalog / Rules / Dice; easy to misuse invalidation and `@ObservedObject` ownership.
5. **Window/splash policy complexity** (`AppDelegate` / `AppLaunchWindowPolicy` ~340 LOC) — fragile launch races; hard to test; future breakage risk.

### Top 5 quick wins

1. Extract pure subviews from `CharacterAtAGlanceView` (portrait, attributes, vitals, condition) without behavior change.
2. Lazy-load catalog (first `CatalogBrowser` open or background task), not in `CatalogStore.init`.
3. Fix `RulesReferenceWindowRoot` to observe `RulesReferenceSession` properly (not a one-shot `controller` assignment).
4. Unify catalog access (`CatalogStore` vs `CatalogLookup`) behind one cache.
5. Gate DEBUG `print` in `PDFViewerView` (already `#if DEBUG` — confirm no release logging; remove or use `os.Logger` at `.debug`).

---

## B. Findings by severity

### P0 — Correctness / data loss / crash likelihood

| ID | Location | What’s wrong | Why it matters | Recommended fix | Effort |
|----|----------|--------------|----------------|-----------------|--------|
| P0-1 | *None confirmed in this pass* | Build + full tests green; no clear data-loss path found in static review | — | Re-validate after merge to `develop` | — |

*Note:* Splash/window frame persistence and PDF page-offset mapping are complex but currently intentional. Treat regressions as product bugs when found, not as audit rewrites.

---

### P1 — Maintainability / performance (hurt soon)

| ID | Location | What’s wrong | Why it matters | Recommended fix | Effort |
|----|----------|--------------|----------------|-----------------|--------|
| **P1-1** | `UI/Summary/CharacterAtAGlanceView.swift` (~1644 lines) | Single file owns dashboard layout, toolbar, story/notes, condition UI, dice open, house rules, export hooks | Slow reviews; accidental coupling; SwiftUI body invalidation hard to reason about | Split into `PortraitColumn`, `AttributesColumn`, `VitalsGrid`, `ConditionCard`, `IdentityColumn` files; keep mutations via shared `updateCharacter` | M |
| **P1-2** | `UI/Rules/RulesReferenceView.swift` (~1375) + `RulesReferenceController.swift` (~868) | UI + persistence + shelf PDF search + reader chrome in two mega-types | Rules feature will ossify; search/zoom bugs expensive | Extract `LibraryShelfView`, `LibraryTextSearchResults`, `BookSettingsSheet` (already private), pure `PDFLibrarySearchEngine` | M |
| **P1-3** | `UI/ContentView.swift` (~1176) | Navigation hub + import + marketing hooks + library selection | Same as above for shell | Extract marketing handlers, package open, library list into helpers/views | M |
| **P1-4** | `Catalog/ChummerCatalogLoader.swift` + `CatalogStore` | `CatalogStore.shared` reloads full catalog on init (main actor); separate `CatalogLookup` static cache duplicates load path | Double decode risk; startup cost; import vs UI cache divergence | Single source of truth: lazy `CatalogStore` load; `CatalogLookup` delegates to it or shared locked cache filled once | M |
| **P1-5** | `RulesReferenceController.runLibraryTextSearch` | Parallel `TaskGroup` opens multiple full `PDFDocument`s (SR5 ~1000 pages each) | Peak memory / thrashing on multi-book shelves | Cap concurrency (e.g. 2 books at a time); prefer search open book first; consider cancellable serial for low-memory machines | M |
| **P1-6** | `UI/Rules/PDFViewerView.swift` | Separate continuous reader + hidden thumbnail driver both load `PDFDocument` | 2× document memory for one open book | Share one document model for thumbs + reader, or lighter thumb generation from cover/cache only | M |
| **P1-7** | `RulesReferenceController.results` | Computed property re-runs `store.search` on every observer fire / body access | Extra CPU on typing/filtering | Cache results; invalidate on query/category/edition change only | S |
| **P1-8** | Observation models mixed | `@Observable` env for library; `ObservableObject` for Rules session, Catalog, Dice, PDFSearchBridge | Inconsistent lifecycle; `@ObservedObject var x = Singleton.shared.controller` is fragile | Standardize: app services as `@Observable` or single `ObservableObject` session owned by `@StateObject` | L |
| **P1-9** | `RulesReferenceWindowRoot` | `@ObservedObject private var controller = RulesReferenceSession.shared.controller` | Does not own the object; may miss updates if observation graph is wrong | `@StateObject`/`@ObservedObject` on `RulesReferenceSession.shared` or inject controller from environment | S |
| **P1-10** | `App/AppDelegate.swift` (`AppLaunchWindowPolicy`) | Large launch/splash/frame policy with timers + UserDefaults + autosave | Launch regressions hard to reproduce; already saw multi-iteration bugs | Extract to `LaunchWindowCoordinator` + unit-testable pure size helpers; document state machine | M |
| **P1-11** | UserDefaults keys | Scattered string keys (`RulesRef.*`, `ShadowDeck.mainWindowFrame`, catalog prefs) | Typos, no schema, hard to reset | Single `AppPreferences` enum / struct with typed keys | S |

---

### P2 — Consistency / style / polish

| ID | Location | What’s wrong | Why it matters | Recommended fix | Effort |
|----|----------|--------------|----------------|-----------------|--------|
| **P2-1** | `ShadowDeckTests/ShadowDeckTests.swift` | Placeholder `XCTAssertTrue(true)` only | Noise; false sense of coverage | Delete placeholder or replace with real smoke (e.g. seed load) | S |
| **P2-2** | `Docs/DESIGN.md` Phase 8 | Still lists marketing version `0.8.0` | Docs drift | Align with `MARKETING_VERSION` 0.9.0 in project | S |
| **P2-3** | `project.pbxproj` | App `0.9.0` vs test target `0.1.0` | Confusion in archives | Align test target marketing version or document intentional split | S |
| **P2-4** | Accessibility | Sparse `accessibilityLabel` outside a few Rules controls; many icon-only buttons rely on `.help` only | VoiceOver gaps on macOS | Pass over toolbar/reader chrome: labels for zoom, look up, search next/prev | M |
| **P2-5** | Look-up / confirm patterns | Most mutations save immediately; awards use confirmation sheet — good — but not documented as a rule | Future features may skip confirms for irreversible actions | Encode in conventions (below) | S |
| **P2-6** | `DispatchQueue.main.async` vs `Task { @MainActor }` | Mixed deferral styles for “avoid publish during view update” | Harder to audit concurrency | Prefer `Task { @MainActor in await Task.yield(); … }` consistently | S |
| **P2-7** | File naming | `CharacterLibraryGallery.swift` at UI root vs feature folders | Navigation friction | Move under `UI/Library/` or similar when touching that area | S |
| **P2-8** | Rules seed page refs | Many pages approximate; 16 high-traffic cards tightened | Wrong chip pages erode trust | Optional: scripted PDFKit page audit against bound keys | M |
| **P2-9** | Splash docs | Splash every cold launch; legacy `hasSeenLaunchSplash` cleared in `init` | README/DESIGN may still imply once-per-install | Update DESIGN Phase 9A splash notes | S |

---

### P3 — Nice-to-have

| ID | Location | What’s wrong | Why it matters | Recommended fix | Effort |
|----|----------|--------------|----------------|-----------------|--------|
| **P3-1** | Project root | No SwiftLint / swift-format | Style drift over time | Optional lightweight SwiftLint later (not blocking) | S |
| **P3-2** | `public` on many models | Broad public API surface for a single-app target | Unnecessary exposure | Default to `internal` unless tests/modules need public | M |
| **P3-3** | Marketing exporter | Large AppKit snapshot path intertwined with production app | Testability | `#if DEBUG` or separate target for marquee capture | M |
| **P3-4** | Swift 6 readiness | `nonisolated(unsafe)` caches, mixed MainActor | Future language mode pain | Gradual MainActor audit when enabling strict concurrency | L |

---

## C. Stale code inventory

| Candidate | Path | Recommendation |
|-----------|------|----------------|
| Placeholder test | `ShadowDeckTests/ShadowDeckTests.swift` | Remove or replace with meaningful smoke test |
| Legacy splash key wipe | `ShadowDeckApp.init` removes `hasSeenLaunchSplash` every launch | Remove wipe once no installs need migration; document in DESIGN |
| Empty test marketing version 0.1.0 | `project.pbxproj` test target | Align or document |
| Commented history in DESIGN testing table | `Docs/DESIGN.md` | Append Rules Reference / Awards phases as ✅ (docs only) |

**Not stale (keep):** `MarketingScreenshotExporter`, sample characters, dual import paths (JSON/XML), house-rule matrix — all product-used.

**No mass deletions performed** in this audit (per constraints).

---

## D. Performance notes

| Hotspot | Detail |
|---------|--------|
| **Catalog JSON** | ~1.2 MB `sr5_catalog.json` decoded on first `CatalogStore` access (currently at app feature touch via shared singleton init). Prefer lazy load. |
| **Rules seed** | ~90 KB JSON — fine at Rules window open; avoid re-decoding (store already holds entries). |
| **Character sheet** | Large view tree + management tabs; equipping gear re-resolves effects — OK if engines stay pure and UI invalidates narrowly. |
| **PDF open** | Continuous reader + thumbnail strip share one `PDFDocument` via `SharedPDFDocumentSession` (thumbnail still uses a hidden driver `PDFView`). Large CRBs remain heavy but no longer double-decode. |
| **PDF shelf search** | Parallel full-document `findString` per book; improved ranking but still O(books × pages × tokens). Cap concurrency; show progress (done). |
| **Library list** | Character/run lists appear fine; watch `PersistenceTests.testPerformanceDozensOfCharacters` (~1.2s) if library grows a lot. |
| **Import Ghostwire** | Tests show multi-second chum5 import — acceptable offline; keep off UI thread if not already (importer is `@MainActor` — **watch** for large file UI stalls). |

---

## E. ShadowDeck conventions (proposed)

Patterns already successful in Lifestyle / Advancement / Dice / Runs / Awards:

1. **Pure engines** live under `Rules/` (or `Rules/Calculators/`). Input: values/DTOs. Output: results / previews. No SwiftUI, no disk.
2. **UI owns side effects**: confirm sheets for irreversible multi-entity commits (e.g. Apply Awards); auto-save for single-character field edits.
3. **Ledgers** for karma/nuyen/lifestyle history — prefer append-only records with kind enums over silent mutation.
4. **Edition strategy**: `EditionRules` / `RulesRegistry`; avoid `switch edition` scattered in views.
5. **Persistence**: Codable domain `Character` / `Run` in SwiftData JSON payloads; version fields for future migrations.
6. **Feature folders**: `UI/<Feature>/`, tests named `*Tests.swift` next to engine concerns.
7. **Windows**: long-lived tools (Rules) as `Window(id:)`; transient tools (Dice) as inspector/panel on the sheet.
8. **Look up**: `RulesReferenceOpener.request` / `open` with optional `RulesCalcContext` — do not deep-link by inventing new notification names per tab.
9. **Defer publishes**: never write `@Published` during `updateNSView` / view body; use `Task { @MainActor; await Task.yield() }`.
10. **Naming**: `*Engine` pure, `*Store` load/search, `*Controller` UI session, `*View` SwiftUI.

---

## F. Test gap list

| Area | Current | Gap |
|------|---------|-----|
| Dice roller engine | Strong | Edge session edge cases with house rules combos |
| Advancement / lifestyle / awards | Strong | — |
| Rules calculators | Strong | — |
| Rules seed / search | Good | Related-id integrity; prefer-edition chip order tested |
| PDF library store | Good | Missing: text-search ranking unit tests (pure function extract) |
| PDF zoom math | Good | — |
| RulesReferenceController | Little | State persistence round-trip; search navigation index |
| AppLaunchWindowPolicy | None | Pure helpers for splash vs main frame (hard full UI test) |
| Chummer import | Strong | — |
| Character sheet UI | Indirect | No UI tests (acceptable); keep engine tests as safety net |
| Catalog search | Light | Filter correctness / performance smoke |

---

## G. Cleanup PR sequence — **completed**

| # | PR title | Status |
|---|----------|--------|
| 1 | **Docs: align version + splash notes** | ✅ DESIGN 0.9.0, splash every cold launch, testing table |
| 2 | **Replace placeholder ShadowDeckTests smoke** | ✅ Seed load + catalog lookup smoke |
| 3 | **Lazy CatalogStore load** | ✅ `ensureLoaded()` on first browser/settings |
| 4 | **Unify CatalogLookup → shared cache** | ✅ `CatalogCache` single path |
| 5 | **Fix RulesReferenceWindowRoot observation** | ✅ Observes `RulesReferenceSession` |
| 6 | **Cache RulesReferenceController.results** | ✅ Invalidate on query/category/edition |
| 7 | **Extract CharacterAtAGlance subviews** | ✅ Portrait / identity / condition columns |
| 8 | **Extract Rules Library shelf + search UI** | ✅ `LibraryShelfBrowseView` + `PDFLibrarySearchEngine` |
| 9 | **PDF: cap search concurrency** | ✅ Max 2 concurrent book opens |
| 10 | **AppPreferences typed UserDefaults** | ✅ Central key schema |
| 11 | **Accessibility pass: toolbars + PDF chrome** | ✅ Labels on zoom, find, nav, shelf |
| 12 | **LaunchWindowCoordinator extract + pure tests** | ✅ Geometry helpers unit-tested |

---

## Automated check summary

| Check | Result |
|-------|--------|
| `xcodebuild … build` (macOS) | **Succeeded** |
| `xcodebuild … test` | **Succeeded** |
| Compiler warnings (app code) | None significant (only AppIntents metadata noise) |
| SwiftLint / swift-format | **Optional** — `.swiftlint.yml` + `Scripts/lint.sh` (install via Homebrew) |
| Dead code auto-removal | **Not run** (no tool); inventory is manual |

---

## Architecture map (current)

```
ShadowDeck/
  App/           # Scene, commands, launch/splash policy, marketing capture
  Models/        # Codable domain (Character, Run, Rules, PDF meta, …)
  Rules/         # Pure engines + calculators + rules seed store
  Persistence/   # SwiftData libraries, PDF library files, avatars
  Import/ Export/ Catalog/
  UI/            # Feature folders: Summary, Management, Runs, Dice, Rules, Generation, …
  Resources/     # Catalog JSON, RulesSeed, brand, chargen art, fonts
ShadowDeckTests/ # Engine-heavy unit tests (good density)
```

**Layering (generally good):** UI → libraries/env → models; rules engines pure.  
**Weak spots:** UI files absorbing session + I/O (Rules controller, Character sheet).

---

## Consistency across newer features

| Feature | Engine purity | UI pattern | Ledger / confirm | Notes |
|---------|---------------|------------|------------------|-------|
| Lifestyle | Good | Management tab | Process month explicit | Solid template |
| Advancement | Good | Plan tab | Apply plan confirm | Solid |
| Dice | Good | Inspector | Session Edge in controller | Solid |
| Apply Awards | Good | Sheet confirm | Multi-entity save in UI | Best “dangerous action” pattern |
| Rules Reference | Mixed | Dedicated window | N/A | Youngest; highest complexity debt |
| Runs | Models OK | Large detail view | Status/outcome flows | Extract sections next |

---

## Security / privacy

| Topic | Assessment |
|-------|------------|
| Secrets in repo | None found |
| PDF handling | Copies into Application Support; good. No network upload. |
| Logging | One DEBUG zoom `print` in PDF viewer — keep `#if DEBUG` only |
| Sandbox | Entitlements present; security-scoped access used on import/add PDF |

---

## Docs accuracy

| Doc | Gap |
|-----|-----|
| README | Rules Reference marked Done — OK on this branch; ensure `develop` matches after merge |
| DESIGN | Phase 8 version 0.8.0 stale; splash “once” narrative stale; Rules Reference section present and useful |
| CODE_AUDIT | This file |

---

## Success criteria checklist

- [x] `Docs/CODE_AUDIT.md` with prioritized findings and cleanup sequence  
- [x] Stale/dead candidates listed with paths  
- [x] Performance notes specific to catalog/PDF/sheet  
- [x] Conventions from Lifestyle / Advancement / Dice / Runs  
- [x] Build green; tests green; no non-trivial deletions applied  
- [x] No feature work mixed into audit  

---

*Cleanup PRs 1–12 + follow-ups applied (ContentView/RunDetail extracts, shared PDF session, SwiftLint, concurrency notes). Later: **Swift 6 language mode**, comprehensive SwiftLint defaults+opt-ins, ContentView shell thinning (`MainSidebarView` / export actions / file drop), **async off-main Chummer import**. Remaining optional: further god-view splits, import progress UI polish, expand SwiftLint toward zero warnings. Ask before any non-trivial deletion or architecture rewrite.*
