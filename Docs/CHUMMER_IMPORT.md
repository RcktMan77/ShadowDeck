# Chummer Import Format Audit

**Purpose:** Document how Chummer5a data relates to ShadowDeck’s **native** models, what we map today, and what remains intentionally out of scope or deferred.

**Principle:** ShadowDeck’s source of truth is the clean native `Character` model + `.shadowdeck` packages. Chummer is an **import source**, not a storage format we re-export.

**Validated against:** Chummer **5.225.0** (Ghostwire sample, read-only), plus synthetic fixtures in `ShadowDeckTests/Fixtures/`.

---

## 1. Native vs import: two different jobs

| Concern | ShadowDeck native | Chummer import |
|---------|-------------------|----------------|
| Schema | Stable, edition-aware, human-owned | Large, version-volatile, stringly typed |
| Skills | `SkillRating` with explicit rank | Dual layout (`skills` vs `newskills`); `total` often dice pool |
| Attributes | `AttributeRatings` (sheet values) | `base` / `total` / metatype bounds; augs may already be in `total` |
| Gear | Flat `GearItem` list (for now) | Nested gear under armor/weapon/cyber; locations |
| Advancement | Karma/nuyen fields + future history | `expenses`, `improvements`, career flags |
| Portrait | Hybrid avatar store | `mugshots` (not yet mapped) |

We **keep** dual-path parsers for known Chummer evolution. We **do not** mirror Chummer’s internal tree in SwiftData.

---

## 2. File shapes

### `.chum5` (XML)

```text
<?xml …?>
<character>
  … identity, priorities, flags …
  <attributes><attribute>…</attribute></attributes>
  <newskills>                    <!-- modern (5.2xx) -->
    <skills><skill/>…</skills>
    <knoskills><skill/>…</knoskills>
    <groups>…</groups>
  </newskills>
  <!-- legacy alternative: top-level <skills><skill/> -->
  <qualities>…</qualities>
  <cyberwares>…</cyberwares>
  <powers>…</powers>
  <gears>…</gears>
  <weapons>…</weapons>
  <armors>…</armors>
  <contacts>…</contacts>
  <lifestyles>…</lifestyles>
  <vehicles>…</vehicles>
  <improvements>…</improvements>
  <expenses>…</expenses>
  <calculatedvalues>…</calculatedvalues>
  …
</character>
```

### JSON export

Typically XML→JSON:

```json
{ "?xml": {…}, "characters": { "character": { … } } }
```

Oddities we handle:

- UTF-8 **BOM**
- Attributes as `["0", { "attribute": [ … ] }]`
- Single child vs array for repeating elements
- Numbers as strings (`"48,051"`)

---

## 3. Dual-format / version notes

| Area | Legacy | Modern (observed 5.225) | ShadowDeck stance |
|------|--------|-------------------------|-------------------|
| **Skills** | Top-level `<skills>` | `<newskills>/<skills|knoskills|groups>` | Support **both**; prefer modern when present |
| **Attributes** | `<attributes>` | Same container | Single path; no `newattributes` |
| **Qualities / contacts / lifestyles** | Long-standing lists | Same | Single path |
| **Cyber / bio / powers / spells** | List containers | Same | Single path |
| **Gear** | Top-level + **nested** under armor/weapon/cyber | Same complexity | Top-level + weapons/armor mapped; **nested incomplete** |
| **Improvements** | Growing system | Heavy use in career chars | **Not mapped** (diagnostics-friendly later) |
| **Mugshots** | Base64 / indices | Same family | **Not mapped** yet (Phase 2 avatars are native) |

**Conclusion:** Skills are the clear “old vs new root” migration. Most other sections kept names but gained **depth** (nesting, improvements, calculated blocks)—not parallel `new*` roots. Keeping legacy skill support is cheap compatibility, not native-schema cruft.

---

## 4. Mapping fidelity matrix

| Domain field | Import status | Notes |
|--------------|---------------|--------|
| Name / alias / metatype / edition | ✅ | |
| Priorities A–E | ✅ | Sum-to-ten when indicated |
| Build method → generation system | ✅ | Priority / BP / karma heuristics |
| Attributes (sheet totals) | ✅ | Prefer `total`, then `base` |
| Essence | ✅ | Prefer `totaless` |
| Active / knowledge skills (ranks) | ✅ | Use `rating` / `base+karma`, **not** pool `total` |
| Skill specializations | ✅ | |
| Skill groups | ⚠️ Partial | Legacy + `newskills/groups` |
| Qualities | ✅ | Karma may be 0 on some built-ins |
| Cyberware / bioware | ✅ | Essence, grade, rating |
| Adept powers | ✅ | |
| Spells / complex forms | ✅ | When present |
| Top-level gear / weapons / armor | ✅ | Unarmed attack rows skipped |
| Nested gear (in armor/weapon) | ❌ Gap | Listed under parent in Chummer only |
| Vehicles / drones | ❌ Gap | Present on Ghostwire; not mapped |
| Contacts / lifestyles | ✅ | |
| Metamagic / initiation grade | ❌ Gap | Data present; future magic depth |
| Expenses / karma history | ❌ Gap | |
| Improvements | ❌ Gap | Derived bonuses may already be in totals |
| Mugshots | ❌ Gap | |
| Condition monitors (filled) | ❌ Gap | `calculatedvalues` / filled boxes available |
| Tradition / spirits | ❌ Gap | |

“Gap” means **not in native model yet or not mapped**—not that we should store raw Chummer XML.

---

## 5. What stays clean on the ShadowDeck side

Native design goals (unchanged by Chummer complexity):

1. **`Character` is edition-aware and Codable** — not a dump of Chummer keys.  
2. **Rules live in `EditionRules`** — costs, bounds, derived stats.  
3. **Portable file is `.shadowdeck`** — package with `character.json` + optional avatar.  
4. **Import is lossy-by-design for exotic nodes**, with `ImportDiagnostics` warnings when we approximate.  
5. **Never write back to `.chum5`** as source of truth.

When import is incomplete, the user still gets a playable core sheet (identity, attributes, skills, qualities, augs, contacts, nuyen/karma) and can refine in ShadowDeck.

---

## 6. Recommended follow-ups (not blocking Phase 4)

1. Nested gear flatten pass (accessories → notes or child items).  
2. Vehicle/drone model + import.  
3. Mugshot → hybrid avatar.  
4. Optional “import report” UI listing unmapped sections by count.  
5. Pin CI/sample matrix: Chummer 5.225 JSON + chum5; re-verify on major Chummer upgrades.

---

## 7. Test coverage

| Test | Role |
|------|------|
| `minimal_sr5.json` / `.chum5` | CI-stable synthetic shapes |
| Ghostwire JSON/XML (local only) | Real-world fidelity when files exist |
| Library save + `.shadowdeck` re-export | Round-trip after import |

Ghostwire paths are **never** required on GitHub Actions (files absent → tests skip).
