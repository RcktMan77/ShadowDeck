# ShadowDeck Design Notes

Living document for architecture choices, open questions, and non-obvious decisions.  
Updated as phases land. **Human input required** before locking ambiguous items.

## Confirmed (Phase 0–1)

| Decision | Choice |
|----------|--------|
| Application name | **ShadowDeck** |
| Repository | Public GitHub: `ShadowDeck` |
| Bundle ID | `com.shadowdeck.ShadowDeck` |
| UI framework | SwiftUI, macOS 14+ |
| App lifecycle | SwiftUI `App` protocol |
| Sandbox | Enabled; user-selected file read/write for import/export |
| Character library | **App-managed library** (primary) |
| Portability | Single-file **`.shadowdeck`** package (ZIP + JSON) for import/export |
| Edition priority | **Equal peers** — SR4, SR5, SR6 first-class from day one |
| House rules | Core-book default + top ~10 popular toggles early |
| Domain model | Pure `Codable` value types; SwiftData records + JSON payloads (`Character`, `Run`) |
| Avatar storage | **Hybrid**: ≤256KB static inline; large/animated as files |
| Character dashboard | **Interactive play sheet** (Phase 5) + **management tabs** (Phase 6): skills, gear, augs, qualities, contacts, magic |

## Architecture Overview

```
UI  →  View models / observation  →  Domain models (Character, …)
                                      ↑
                         Rules engine (EditionRules: SR4 / SR5 / SR6)
                                      ↑
                         Persistence / Import-Export
```

### Guiding rules

- **Observation + SwiftUI** for state; avoid unnecessary Combine unless bridging.
- **Protocol / strategy** for edition-specific rules (`EditionRules` + `RulesRegistry`).
- **Data-driven** game catalogs over time (JSON under `Resources/`); Phase 1 embeds core tables in rules for testability.
- **Codable** domain snapshots for portable export and tests.
- Prefer **SwiftData** for the app library; **`.shadowdeck`** ZIP package for user-facing single-character files.

## Domain Model (Phase 1)

| Type | Role |
|------|------|
| `Edition` | `.sr4` / `.sr5` / `.sr6` peers |
| `Character` | Full character aggregate (Codable, schemaVersion) |
| `Run` | GM mission/job aggregate (status, objectives, payout, session log, soft-linked character IDs; optional `awardsAppliedAt` / note) |
| `RunLibrary` / `RunRecord` | Parallel to character library (JSON payload + denormalized list fields) |
| `RunAwardApplicator` | Pure preview + apply for equal-split nuyen/karma from a finished run onto available linked characters |
| `Lifestyle` + `LifestyleTracker` | Per-character monthly burn, prepaid months, reserve, process 1–3 months, ledger |
| `Advancement` + `AdvancementEngine` | Character Plan tab: session cart, skill/attribute karma raises, ledger; free Skills-tab edits remain for import/GM fiat; ledger also records `runAward` gains |
| `AttributeRatings` / `AttributeID` | Physical, mental, special (incl. essence) |
| `MetatypeID` + `MetatypeCatalog` | Core five metatypes + bounds |
| `SkillRating` / `SkillGroupRating` | Active, knowledge, language |
| `QualityInstance` | Positive/negative with karma values |
| `GearItem`, `Augmentation` | Inventory + cyber/bioware |
| Spells / adept powers / complex forms | Magic & resonance instances |
| `Lifestyle`, `Contact` | Social/economic tracking |
| `GenerationProfile` | BP / priority / sum-to-ten / karmagen state |
| `HouseRules` | Toggle set + parameters |
| `DerivedStats` | Limits, monitors, initiative, pools |
| `PortableCharacterDocument` | Export payload schema — full `Character` embed; `.shadowdeck` is the fidelity-preserving transfer format |

### Edition strategy differences (high level)

| Concern | SR4 | SR5 | SR6 |
|---------|-----|-----|-----|
| Default gen | Build Points (400) | Priority | Priority |
| Limits | No | Physical/Mental/Social | No (Edge-centric) |
| Edge | Attribute | Attribute | Session pool + attribute |
| Sample starting karma | — | 25 | 50 |

### Portable file format (`.shadowdeck`)

User sees **one file/object**. On disk it is a **directory package** (Mac-native):

```
runner.shadowdeck/
  manifest.json      # id, name, edition, formatVersion, hasAvatar
  character.json     # PortableCharacterDocument (JSON, ISO-8601 dates)
  avatar/portrait.*  # optional portrait bytes
```

- JSON payload is human-debuggable and `Codable`-native.
- App library stores characters in **SwiftData**; export/import uses `.shadowdeck`.

### Hybrid avatar storage (Phase 2)

| Case | Storage |
|------|---------|
| No portrait | `AvatarStorageKind.none` |
| Static ≤ 256 KB | SwiftData inline blob (`CharacterRecord.avatarInlineData`) |
| Static > 256 KB | File under Application Support `ShadowDeck/Avatars/<id>/portrait.<ext>` |
| Animated (any size) | Always file |

Domain `Character.avatar.inlineData` is rehydrated on fetch for UI/export convenience; the JSON payload never embeds binary.

### House rules

**Design choice: multi-select individual rules**, not exclusive “rule packs.” Tables almost always stack conveniences (Sum-to-Ten + free knowledge + expanded contacts). Presets (`.coreBook`, `.popularTable`, `.primeRunner`) only seed the set; players can still toggle pieces. The only mutual exclusion is **Karma Generation** vs **Sum-to-Ten / classic priority letters**.

| Rule | Chargen / play effect |
|------|------------------------|
| Sum-to-Ten | Priority values sum to 10; duplicates OK |
| Karma generation | Switches wizard to karmagen budget |
| Bonus starting karma | Adds `bonusKarma` to starting pool |
| Free knowledge skills | Free ranks = fixed or (LOG+INT)×2 |
| Expanded contacts | CHA×3 + `extraContactPoints` |
| Exceptional Attribute at chargen | Natural max +1; augmented ceiling +1 |
| Essence cost rounding | Rounds each aug cost down (effects engine / essence) |
| Quality budget adjustment | Positive quality karma cap override |
| Prime runner package | Karma + contacts + quality cap + ~10% nuyen |
| Alternate attribute costs | Linear post-gen attribute karma |

UI: **Configure…** on the edition wizard step and **House Rules…** on the Summary identity column open a searchable catalog with descriptions and live effect list (`HouseRulesBrowserView` + `HouseRulesEngine`).

## Open Decisions (ask human before locking)

1. **Which core books** first for full data packs in Phase 7.
2. **Chummer version** reference for JSON schema (5a latest vs pinned).
3. **Visual design language**: archetype showcase uses SwiftUI neon/animated Canvas art (not licensed SR art); can swap for custom assets later.
4. **Exact SR6 priority table numbers** — wizard uses rules tables; confirm against your core book printing if a number feels off.
5. **Wizard avatar step** — portrait upload deferred to summary screen (Phase 5); finish step is name + review.

## Import pipeline (Phase 3)

```
.file → CharacterImporter (detect)
          ├─ Chummer JSON  → ChummerJSONParser
          ├─ .chum5 XML    → ChummerXMLParser  (legacy <skills> + modern <newskills>)
          └─ .shadowdeck   → ShadowDeckPackage
                ↓
        ChummerNormalizedCharacter
                ↓
        ChummerMapper → Character + ImportDiagnostics
                ↓
        CharacterLibrary.importAndSave
```

- Original Chummer files are **read-only**; never written back.
- Skill ranks use Chummer `rating` / `base+karma`, **not** dice-pool `total`.
- Attribute sheet values prefer Chummer **`base`** so `CharacterEffectsEngine` can re-apply aug/quality/gear modifiers without double-counting totals. Imported gear/augs/qualities pull modifiers from the bundled catalog by name.
- Personal test fixtures (e.g. Ghostwire) stay outside the repo; CI uses synthetic fixtures under `ShadowDeckTests/Fixtures/`.

## Migration Strategy

- `Character.schemaVersion` + `PortableCharacterDocument.formatVersion` from Phase 1.
- SwiftData versioning from day one of Phase 2.
- Export `.shadowdeck` early so users can recover across breaking changes.
- Chummer import maps into native models; `.chum5` is never the source of truth after import.

## Testing Strategy

| Area | When |
|------|------|
| Smoke / module load | Phase 0 ✅ |
| Domain invariants per edition | Phase 1 ✅ |
| CRUD + avatar persistence | Phase 2 ✅ |
| Import mapping fidelity | Phase 3 ✅ |
| Generation cost / legality | Phase 4 ✅ |
| At-a-glance summary dashboard | Phase 5 ✅ |
| Detailed management (skills/gear/augs/…) | Phase 6 ✅ |
| Character effects (equip → attrs/nuyen/armor) | Phase 7 ✅ |
| House rules catalog + multi-select enforcement | Phase 7 ✅ |
| Packaging / menus / library polish | Phase 8 ✅ |
| Derived values / UI logic as pure functions | Ongoing |

## Phase 8 — Packaging & polish

| Deliverable | Detail |
|-------------|--------|
| **Version** | Marketing version `0.8.0` |
| **UTType** | `com.shadowdeck.character` exported for `.shadowdeck` directory packages (`Info.plist` + `UTType.shadowdeckCharacter`) |
| **Open package** | Finder double-click / `application(_:open:)` → import into library; File → Open Package…; library **Open Package…** |
| **Menus** | File → New Character (⌘N), Import (⇧⌘O), Open Package (⌘O) |
| **Library** | Search/filter by name, street name, concept, edition, metatype |
| **Summary** | Validation banner (errors/warnings from `EditionRules.validate`) |
| **Settings** | About + portable format tips |
| **Release** | `Scripts/release_build.sh` produces unsigned `build/Release/ShadowDeck.app` |

**Extensibility notes (intentional hooks, not full plugin system yet):**

- Catalog is data-driven JSON (`formatVersion` 2) regenerable from Chummer XML.
- House rules are a `Set<HouseRuleID>` + parameters; new rules add an enum case + `HouseRulesEngine` branch.
- Edition rules stay behind `EditionRules` / `RulesRegistry`.

## Character workspace (Phase 5–6)

Segmented tabs on the open character:

| Tab | Role |
|-----|------|
| **Summary** | Play sheet: portrait, attributes, story, vitals, condition, notes |
| **Skills** | Full skill list; rating steppers; add/remove |
| **Gear** | Inventory; equip toggles; quantity; add/remove |
| **Augs** | Cyberware/bioware + essence costs |
| **Qualities** | Positive/negative qualities + karma values |
| **Contacts** | Loyalty / Connection; tags, favor standing, interaction log (enriched v1) |
| **Magic** | Adept powers, spells, complex forms |

Mutations persist immediately through `CharacterLibrary.save`.

## Apply Run Awards (v1)

Explicit GM action on a **Completed** or **Failed** run. Never automatic on status change.

| Piece | Behavior |
|-------|----------|
| Source payout | `actualPayout ?? expectedPayout` (sheet labels which) |
| Split | Equal floor among **available** library characters; remainder ¥/karma → first listed available |
| Missing participants | Skipped with report; all-missing blocks apply |
| Character credit | `nuyen +=`, `karmaAvailable +=`, `karmaTotal +=` (matches Summary manual karma award) |
| Ledger | `AdvancementKind.runAward`; `karmaSpent` negative = gain; `nuyenDelta` + `relatedRunID` |
| Double-apply | `Run.awardsAppliedAt` set after successful apply; second apply blocked |
| UI | Outcome section **Apply Awards…** → confirmation sheet; post-apply collapses prior suggestions |

Pure engine: `RunAwardApplicator.preview` / `.apply`. UI owns multi-entity save (characters, then run).

## Character effects engine (Phase 7)

Equipping gear, installing augmentations, taking qualities, and ranking adept powers dynamically updates the play sheet.

| Concept | Behavior |
|---------|----------|
| **Base attributes** | Stored on `Character.attributes`; Summary ± edits base only |
| **Effective attributes** | `base + Σ modifiers` from augs, qualities, powers, **equipped** gear |
| **Armor** | `max(equipped armorRating) + additive armor modifiers` |
| **Initiative** | Uses effective REA/INT + initiative / initiative-dice modifiers (e.g. Wired Reflexes) |
| **Dice pools / limits** | Recomputed from effective attributes + skill bonuses |
| **Nuyen** | Catalog/custom purchase deducts cost when affordable; soft-add if broke; refund on delete if `purchasedInApp` |
| **Custom items** | Field values + optional `StatModifier` list (target, amount, ×Rating, skill key) |
| **Catalog** | Bundled JSON includes Chummer `<bonus>` extracts (`specificattribute`, `specificskill`, `armor`, `initiativepass`, …) |

```
Character.attributes (base)
        + gear[equipped].modifiers
        + augmentations.modifiers
        + qualities.modifiers
        + adeptPowers.modifiers
        ↓
CharacterEffectsEngine.resolve → CharacterEffects
        ↓
EditionRules.deriveStats → play sheet (Summary)
```

Regenerate catalog after Chummer data updates:

```bash
python3 Scripts/build_catalog_from_chummer.py /path/to/Chummer/data
```

## Reference catalogs (bundled)

ShadowDeck **ships a built-in SR5 catalog** (`Resources/Catalog/sr5_catalog.json`, ~3.8k entries) derived from Chummer5a’s open **GPL-3.0** data XML. No Chummer install is required.

| Source | Role |
|--------|------|
| **Bundled JSON** | Default for all users (gear, weapons, armor, cyberware, bioware, qualities, contact roles) |
| **NOTICE.txt** | Attribution / GPL notice for redistributed data |
| **Scripts/build_catalog_from_chummer.py** | Regenerate JSON from a Chummer `data/` folder |
| **Settings → external override** | Optional developer path to live Chummer XML |

Add flows use a **searchable browser**; **Custom…** always works offline without the catalog.

**Not done / not planned as scrape:** Shadowrun Wiki scraping is brittle, incomplete for costs, and a poor ToS fit. Named street-contact art DBs do not exist officially — contacts stay freeform (+ role archetypes from catalog).

SR4 / SR6: same pipeline; add `sr4_catalog.json` / `sr6_catalog.json` when packs are curated.

## Changelog of Decisions

| Date | Decision |
|------|----------|
| 2026-07-25 | Named **ShadowDeck**; public repo; Phase 0 bootstrap |
| 2026-07-25 | Phase 1: equal edition peers; app library + `.shadowdeck` portability; house-rule framework |
| 2026-07-25 | Phase 2: SwiftData library; hybrid avatars; `.shadowdeck` package I/O |
| 2026-07-25 | Phase 3: Chummer JSON + `.chum5` import; Ghostwire validated read-only |
| 2026-07-25 | CI: macos-15 + Xcode 26.3; Chummer audit doc |
| 2026-07-25 | Phase 4: multi-page generation wizard, live allocation, archetype showcase |
| 2026-07-25 | Phase 5: at-a-glance character summary dashboard |
| 2026-07-25 | Phase 6: detailed management tabs (skills, gear, augs, qualities, contacts, magic) |
| 2026-07-31 | Enriched contacts v1: tags, manual favor standing, interaction log (historical favor snapshots), optional soft Run link; relationship status from loyalty + recency; still character-scoped |
| 2026-07-31 | Dice roller v1: inspector panel on character sheet; SR4/5/6 hits & glitches; Push the Limit + Second Chance with session Edge; one-click from skills/attributes; ⌘D |
| 2026-07-31 | Dice house rules on `HouseRules.dice`: glitch threshold, Rule of Six always/edge-only, exploded dice vs glitch, hits on 4+, simplified SR6 Edge flag; roller reads character house rules |
| 2026-08-01 | Apply Run Awards v1: explicit Apply Awards… on terminal runs; equal floor split among available participants; remainder to first; `awardsAppliedAt` double-apply guard; advancement `runAward` ledger; no auto-apply |
| 2026-08-01 | Rules Reference v1: structured cards + calculators + local PDF library + page-chip bridge; dedicated `Window` scene (⌘R); no bundled rulebook PDFs |


## Rules Reference (v1)

Searchable mechanical aids and a **personal** PDF shelf. Three layers; copyright posture is intentional.

### Layers

| Layer | Role |
|-------|------|
| **A — Structured reference** | Bundled `RulesSeed.json` → `RuleEntry` cards (original short summaries, formulas, tags, edition filters). `RulesReferenceStore` loads/search. Detail pane + optional calculator. |
| **B — PDF library** | User-owned PDFs only (`PDFLibraryStore` under Application Support). Shelf (gallery/list, sections, covers), continuous PDFKit reader, zoom (Fit Page / Fit Width / Actual Size / %), find-in-document, thumbnails, last page, front-matter `pageOffset`. |
| **C — Page bridge** | `PageRef(bookKey, page, label)` on cards. Book settings bind `bookKey` + offset. Chip → printed page → PDF index → open reader at page. |

### Presentation

- Dedicated SwiftUI `Window("Rules Reference", id: "rules-reference")` — not a trailing inspector (Dice remains inspector-style).
- Mode chrome: **Reference** | **Library**. Library is full-width shelf or single-book reader (not a split strip).
- Cold launch: restored Rules window is suppressed so splash stays front (`AppLaunchWindowPolicy`).
- Entry: menu **Rules Reference…**, ⌘R, play-sheet toolbar; **Look up** on Skills, Plan, Lifestyle, Magic, Contacts, Gear, Augs, Qualities, Dice, House Rules, and Run detail (`RulesReferenceOpener.request` + optional `RulesCalcContext`).
- Page chips prefer open-character edition first, then SR4 → SR5 → SR6.
- Related card IDs are tappable; calculators prefill from character when available.
- Library shelf supports full-text search across owned PDFs (capped results).
- Reference/library UI state (mode, query, selection, layout, zoom map) persists in `UserDefaults`.

### Key types & files

| Piece | Location |
|-------|----------|
| `RuleEntry`, `PageRef`, categories, calculator IDs | `Models/RulesReference.swift` |
| Seed load + search | `Rules/RulesReferenceStore.swift`, `Resources/Rules/RulesSeed.json` |
| Calculators | `Rules/Calculators/*` + `UI/Rules/RulesCalculatorViews.swift` |
| PDF library model/store | `Models/PDFLibrary.swift`, `Persistence/PDFLibraryStore.swift` |
| Session / window open | `UI/Rules/RulesReferenceSession.swift`, `RulesReferenceOpener` |
| UI | `RulesReferenceView`, `RuleDetailCard`, `PDFViewerView`, `PDFLibraryShelfViews` |

### Zoom (reader)

Canvas = host view bounds (window points), **not** magnified clip bounds.  
`scaleFactor` only — do not reset `NSScrollView.magnification` (PDFKit couples them).  
Fit Page: one full page, aspect preserved, single-edge vertical pad (continuous top-align).  
Fit Width: page width = canvas − side pad. Actual Size ≡ 100% ≡ scale `1.0`.  
H-scroller only when **current** page is wider than canvas (documents may contain landscape spreads).

### Search

| Scope | v1 behavior |
|-------|-------------|
| Structured cards | In-memory filter on title, tags, summary, formula (`RulesReferenceStore.search`) |
| Open PDF | Preview-style find in the continuous reader (`PDFSearchBridge` + `PDFDocument.findString`) |
| Whole shelf | Not indexed yet — open a book and use in-document find; optional background shelf index later |

### Legal / non-goals

- **No** Catalyst (or other) rulebook prose in seed data; **no** shipping or downloading PDFs.
- **No** cloud sync of the PDF shelf (Shared Hub later if ever).
- **No** OCR requirement; in-document search uses PDFKit on text-based PDFs.
- Seed depth targets ~80–120 high-frequency mechanical cards (`RulesSeed.json`); expand JSON over time without UI rewrites.
- Page chips always display **SR4 → SR5 → SR6 → other** (`PageRef.sortedForDisplay`), not library-add order or character edition.

### Tests

- `RulesReferenceTests` — seed load, search tokens, edition/category filters, zoom math.
- `RulesCalculatorTests` — Drain / Overwatch / related pure math.
- `PDFLibraryStoreTests` — add/remove, keys, covers, page offset, last page.

## Phase 9A — Brand kit

- Custom macOS app icon (cyberpunk deck / card motif) in `AppIcon.appiconset`.
- Launch splash (`Resources/Brand/launch_splash.jpg`) with role cast; shown once until dismissed (`hasSeenLaunchSplash`).
- Unofficial fan art; not Catalyst IP.

## Phase 9B — Campaign sheet export

| Artifact | Module |
|----------|--------|
| Validation snapshot | `CampaignSheetReport` |
| Pretty PDF | `CharacterSheetPDF` (US Letter, 2 pages) |
| Chummer best-effort | `ChummerXMLExporter` → `.chum5` |

Chummer export is **lossy / best-effort**. Prefer PDF + `.shadowdeck` as ShadowDeck source of truth. Online hubs that require `.chum5` get a re-importable core sheet with a fidelity report.
