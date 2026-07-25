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
| Domain model | Pure `Codable` value types; SwiftData wraps in Phase 2 |

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
| `PortableCharacterDocument` | Export payload schema |

### Edition strategy differences (high level)

| Concern | SR4 | SR5 | SR6 |
|---------|-----|-----|-----|
| Default gen | Build Points (400) | Priority | Priority |
| Limits | No | Physical/Mental/Social | No (Edge-centric) |
| Edge | Attribute | Attribute | Session pool + attribute |
| Sample starting karma | — | 25 | 50 |

### Portable file format (`.shadowdeck`)

User sees **one file/object**. On disk it is a ZIP package:

```
runner.shadowdeck/
  manifest.json      # id, name, edition, formatVersion, hasAvatar
  character.json     # PortableCharacterDocument (JSON, ISO-8601 dates)
  avatar/            # optional portrait bytes
```

- JSON payload is human-debuggable and `Codable`-native.
- ZIP keeps avatars efficient without a proprietary whole-file binary.
- App library (Phase 2) stores characters in SwiftData; export writes `.shadowdeck`.

### House rules (early set)

1. Sum-to-Ten  
2. Karma generation  
3. Bonus starting karma  
4. Free knowledge skills  
5. Expanded contacts  
6. Exceptional Attribute at chargen  
7. Essence cost rounding  
8. Quality budget adjustment  
9. Prime runner package  
10. Alternate attribute costs  

Presets: `.coreBook`, `.popularTable`, `.primeRunner`.

## Open Decisions (ask human before locking)

1. **Avatar storage in library**: SwiftData blob vs Application Support file reference *(default lean: blob for small portraits, file for large/animated)*.
2. **Which core books** first for full data packs in Phase 7.
3. **Chummer version** reference for JSON schema (5a latest vs pinned).
4. **Visual design language**: neon cyberpunk accent vs restrained professional chrome.
5. **Exact SR6 priority table numbers** — Phase 1 uses documented core approximations; confirm against your table’s core book printing when generation wizard lands.

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
| CRUD + avatar persistence | Phase 2 |
| Import mapping fidelity | Phase 3 |
| Generation cost / legality | Phase 4 |
| Derived values / UI logic as pure functions | Ongoing |

## Changelog of Decisions

| Date | Decision |
|------|----------|
| 2026-07-25 | Named **ShadowDeck**; public repo; Phase 0 bootstrap |
| 2026-07-25 | Phase 1: equal edition peers; app library + `.shadowdeck` portability; house-rule framework |
