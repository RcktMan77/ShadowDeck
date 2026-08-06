# Table-readiness remediation plan

**Source of truth:** `Docs/TABLE_READINESS_AUDIT.md` (2026-08-05)  
**Base branch:** `develop`  
**Out of scope:** Shared Hub, combat/initiative tracker, new major features beyond audit remediation.

---

## Locked product decisions

| Decision | Lock |
|----------|------|
| **SR4 Build Points** | Implement **real** BP chargen. **Do not** remediate with “Simplified/Beta” labels. |
| **SR6 Edge** | Implement **full SR6 Edge Actions / economy** for dice/sheet. **Do not** ship “simplified session Edge + caption” as the fix for F3. |
| **Notarization** | Sign + notarize packaging is **in-scope** (env-based script path; no secrets in git). |
| **PDF draft (F5)** | Honesty + heuristic stability only; full Apple Intelligence draft quality out of scope unless already shipping. |

Principles:

1. Edition math and Edge behavior must be **real** for advertised editions.
2. Stacked, reviewable PRs; tests green before merge.
3. Release path: Developer ID sign → notarytool → staple → zip via `Scripts/release_build.sh`.
4. Re-audit requires full SR4/SR5/SR6 wizard walkthroughs plus SR6 Edge action exercises.

---

## Finding dispositions

| ID | Disposition |
|----|-------------|
| **F1** | Real SR4 Build Points chargen (**PR-1**) |
| **F3** | Full SR6 Edge Actions path as default (**PR-2**) |
| **F2** | SR4 + SR6 import fixtures + tests (**PR-3**) |
| **F4** | Advancement `canAfford` / block unaffordable plan-add (**PR-4**) |
| **F5** | Experimental PDF draft: accurate AI vs heuristic copy (**PR-5**) |
| **F6** | Empty-state discoverability (**PR-5**) |
| **F7** | Splash: skip control / default after first launch **or** explicit wontfix in re-audit (**PR-5b**) |
| **F8** | Catalog “SR5 reference” badge (**PR-5**) |
| **README** | Reflect real SR4 BP + full SR6 Edge once shipped (**PR-7**) |
| **Release** | Automated sign + notarize path documented and working (**PR-6**) |

---

## DESIGN notes (required)

### SR4 Build Points (PR-1) — v1 wizard scope

**Baseline:** SR4A-oriented **400 BP** total (`SR4Rules.standardBuildPointBudget`).

| Category | BP cost (v1) | In wizard? |
|----------|----------------|------------|
| **Metatype** | Human 0, Ork 20, Dwarf 25, Elf 30, Troll 40 | Yes (metatype step) |
| **Physical/Mental attributes** | **10 BP** per point above racial minimum | Yes (attributes step) |
| **Edge / Magic / Resonance** | **10 BP** per point above path minimum | Yes (attributes / magic) |
| **Active skills** | **4 BP** × rating | Yes (skills step) |
| **Knowledge / language** | **2 BP** × rating | If ranked in draft |
| **Resources** | **1 BP = ¥5,000** (nuyen bought with BP) | Yes (resources step) |
| **Qualities** | Positive: +BP equal to quality cost; negative: −BP refund; **±35 BP caps** | Yes (qualities step) |

**Out of wizard v1 (not free — blocked or zero-cost until later):** skill groups, spells, complex forms, contacts BP, initiate grades. These must **not** be silently free: `buildCharacter` / validation warns if present without BP, or wizard omits them until a later PR.

**Validation:**

- Total spent ≤ 400 (hard block on finish / overspend on steppers).
- Remaining BP displayed continuously.
- Category breakdown (metatype, attributes, skills, qualities, resources) in BP overview.
- Overspend rejected; `generation.buildPointsSpent` / `buildPointBudget` accurate on save.

**Remove:** placeholder attribute/skill point pools for BP mode; “full BP accounting expands later” copy.

### SR6 Edge (PR-2) — required before share

| Topic | Design intent |
|-------|----------------|
| **Default** | Full SR6 Edge path; `simplifiedSR6Edge` **off** by default or removed from normal play |
| **Pool** | Session Edge pool sized from Edge attribute; spend/gain per implemented actions |
| **Actions (v1 completeness)** | At minimum, map ShadowDeck’s test-time Edge options to SR6-appropriate spends (document 1:1 book → control). Include spend for boosted dice / re-roll style options the roller already has, plus any additional Edge Actions defined in DESIGN for completeness |
| **Not allowed** | “SR5 Edge remaining + refresh” as the only model with a caption |

Narrow gaps only: e.g. combat-only Edge Actions deferred to combat tracker PR — must be listed explicitly.

### Notarization (PR-6)

- Env: `CODESIGN_IDENTITY`, `SHADOWDECK_NOTARY_PROFILE` (already).
- Command: `Scripts/release_build.sh --zip --sign --notarize`.
- Document staple + re-zip; no credentials in git.

---

## PR stack

| Order | Branch | Sev | Goal |
|-------|--------|-----|------|
| **1** | `fix/sr4-build-points-chargen` | P1 | Real SR4 BP |
| **2** | `fix/sr6-full-edge` | P1 | Full SR6 Edge Actions |
| **3** | `fix/import-fixtures-sr4-sr6` | P2 | Fixtures + tests |
| **4** | `fix/advancement-can-afford` | P3 | Karma gate on plan-add |
| **5** | `fix/polish-empty-catalog-pdf` | P3 | Empty states, catalog badge, PDF draft honesty |
| **5b** | (fold or separate) | P3 | Splash skip / default / wontfix |
| **6** | `chore/notarized-release-automation` | Required | Sign+notarize smoke docs |
| **7** | `docs/readme-post-remediation` | Docs | README matches shipped reality |

Then: full re-audit → `Docs/TABLE_READINESS_REAUDIT.md`.

---

## Order of execution

1. This document (**done when merged**).  
2. **PR-1 SR4 BP** until green.  
3. **PR-2 SR6 Edge** until green.  
4. PR-3 → PR-4 → PR-5 (+5b).  
5. **PR-6** notarization.  
6. **PR-7** README.  
7. Full re-audit + human review before public share.

---

## Success criteria

- [ ] Real SR4 BP chargen; no placeholder BP UX  
- [ ] Full SR6 Edge Actions path default  
- [ ] SR4/SR6 import fixtures tested  
- [ ] Advancement unaffordable plan-add blocked  
- [ ] Sign + notarize path automated/documented  
- [ ] Re-audit with complete wizards + SR6 Edge exercises  
- [ ] Share verdict based on real edition support  

---

## Implementation status

| Item | Status |
|------|--------|
| Remediation plan doc | **This file** |
| PR-1 Real SR4 BP | **In progress** — `SR4BuildPointEngine`, draft/wizard wiring, DESIGN note, tests |
| PR-2 … PR-7 | Not started |
