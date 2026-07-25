# ShadowDeck Design Notes

Living document for architecture choices, open questions, and non-obvious decisions.  
Updated as phases land. **Human input required** before locking ambiguous items.

## Confirmed (Phase 0)

| Decision | Choice |
|----------|--------|
| Application name | **ShadowDeck** |
| Repository | Public GitHub: `ShadowDeck` |
| Bundle ID | `com.shadowdeck.ShadowDeck` |
| UI framework | SwiftUI, macOS 14+ |
| App lifecycle | SwiftUI `App` protocol |
| Sandbox | Enabled; user-selected file read/write for import/export |

## Architecture Overview

Separation of concerns (folders map 1:1 for Phase 0; extract SPM packages later only if clarity improves):

```
UI  →  View models / observation  →  Domain models
                                      ↑
                         Rules engine (edition strategies)
                                      ↑
                         Persistence / Import-Export
```

### Guiding rules

- **Observation + SwiftUI** for state; avoid unnecessary Combine unless bridging.
- **Protocol / strategy** for edition-specific rules (priority tables, costs, maxima).
- **Data-driven** game tables (JSON/plist under `Resources/`) rather than magic numbers in code.
- **Codable** domain snapshots where useful for import/export and tests.
- Prefer **SwiftData** for character storage; re-evaluate if relationship graph or migration needs push toward Core Data.

## Planned Domain Sketch (Phase 1)

Not implemented yet. Expected core types:

- `Edition` — `.sr4`, `.sr5`, `.sr6`
- `Character` — identity, edition, metatype, attributes, skills, qualities, gear, etc.
- `Metatype`, `Attribute`, `Skill`, `Quality`, `GearItem`
- Magic / resonance / technomancer entities
- `Cyberware` / `Bioware`, `Lifestyle`, `Contact`
- `EditionRules` protocol + concrete strategies per edition

## Open Decisions (ask human before locking)

1. **Primary generation system defaults** per edition (priority vs karma/BP variants).
2. **Avatar storage**: blob in SwiftData vs file reference in Application Support package.
3. **Document model**: library of characters in app container vs document-based “runner files.”
4. **Which core books** are in-scope for Phase 7 data packs first.
5. **Chummer version** to treat as reference for JSON schema (5a latest vs pinned).
6. **Visual design language**: neon cyberpunk accent vs restrained professional tool chrome.

## Migration Strategy (sketch)

- SwiftData schema versioning from day one of Phase 2.
- Export native portable format early so users can recover across breaking changes.
- Import pipeline maps Chummer → native; never write back to `.chum5` as source of truth.

## Testing Strategy

| Area | When |
|------|------|
| Smoke / module load | Phase 0 |
| Domain invariants per edition | Phase 1 |
| CRUD + avatar persistence | Phase 2 |
| Import mapping fidelity | Phase 3 |
| Generation cost / legality | Phase 4 |
| Derived values / UI logic as pure functions | Ongoing |

## Changelog of Decisions

| Date | Decision |
|------|----------|
| 2026-07-25 | Named **ShadowDeck**; public repo; Phase 0 bootstrap |
