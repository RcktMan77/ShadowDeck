# ShadowDeck

**Create, import, and run Shadowrun characters on your Mac** — for Shadowrun 4th, 5th, and 6th edition.

**Status:** Active development. Character generation, library, Run tracker, Lifestyle, and Advancement Planner are usable. Shared online campaign features are planned.

ShadowDeck is an unofficial fan-made character and **campaign** companion for tabletop Shadowrun. Build runners with a guided wizard, pull in sheets from Chummer, keep a living library of characters, plan and track missions for your table, and export what your GM or online hub needs.

**Why ShadowDeck?** Built as a native macOS campaign companion—not just chargen—with mission tracking, lifestyle upkeep, and karma planning in one place (Chummer remains excellent for builds and data; ShadowDeck is for running the table).

> Shadowrun is a trademark of its respective owners. ShadowDeck is **not** affiliated with or endorsed by Catalyst Game Labs or The Topps Company, Inc.

<p align="center">
  <img src="Screenshots/01-splash.jpg" alt="ShadowDeck launch splash" width="900" />
</p>

<!-- Character UI thumbs -->
<table align="center" width="900">
  <tr>
    <td width="33%" align="center" valign="top">
      <a href="Screenshots/02-library.jpg">
        <img src="Screenshots/thumbs/02-library.jpg" alt="Character library" width="280" />
      </a><br />
      <sub>Character Library</sub>
    </td>
    <td width="33%" align="center" valign="top">
      <a href="Screenshots/03-generation-role.jpg">
        <img src="Screenshots/thumbs/03-generation-role.jpg" alt="Character generation — Concept &amp; Role" width="280" />
      </a><br />
      <sub>New Character · Role</sub>
    </td>
    <td width="33%" align="center" valign="top">
      <a href="Screenshots/04-character-sheet.jpg">
        <img src="Screenshots/thumbs/04-character-sheet.jpg" alt="Character summary sheet" width="280" />
      </a><br />
      <sub>Play sheet</sub>
    </td>
  </tr>
</table>

<!-- Feature GIFs: poster + play affordance; click opens the full looping GIF -->
<table align="center" width="900">
  <tr>
    <td width="50%" align="center" valign="top">
      <a href="Screenshots/07-run-mission-flow.gif" title="Click to play">
        <img src="Screenshots/thumbs/07-run-mission-flow-poster.jpg" alt="Run mission flow — click to play" width="420" />
      </a><br />
      <sub><strong>Run / mission flow</strong> — from the Run Library, create a job, fill the briefing, link runners, log a session, complete objectives, set the outcome, then return to the library with the completed status on the run row. <em>Click to play.</em></sub>
    </td>
    <td width="50%" align="center" valign="top">
      <a href="Screenshots/08-advancement-planner.gif" title="Click to play">
        <img src="Screenshots/thumbs/08-advancement-planner-poster.jpg" alt="Advancement planner flow — click to play" width="420" />
      </a><br />
      <sub><strong>Advancement Planner</strong> — scroll to skills, add raises to the plan, watch karma totals, apply, and see ranks and available karma update. <em>Click to play.</em></sub>
    </td>
  </tr>
</table>

---

## What you can do

### Build a runner
- **Edition-aware generation** for SR4, SR5, and SR6
- Step-by-step wizard: metatype, priorities, attributes, skills, qualities, resources, magic/resonance
- **House rules catalog** — Sum-to-Ten, free knowledge, expanded contacts, prime runner packages, and more (stack individual rules or start from presets)
- Role recommendations and painted archetype / metatype art

### Keep a character library
- Local **Character Library** of all your runners (search and filter)
- **Interactive play sheet**: attributes (base + gear/aug bonuses), condition monitors, karma, nuyen, initiative, armor, dice pools
- Tabs for skills, gear, augmentations, qualities, **contacts** (tags, favors, interaction log), **lifestyle**, **Plan** (Advancement Planner), and magic
- **Dice roller** — edition-aware hits/glitches (SR4/5/6), one-click from skills and attributes, Push the Limit / Second Chance Edge, session history (⌘D)
- **Lifestyle tracker** — monthly burn, prepaid months, reserve (used first when paying), Process Month (1–3 mo), prepay, and a short payment ledger
- **Advancement Planner** — plan skill/attribute raises with edition karma costs, session-persistent cart, Buy Now / Apply Plan, suggestions, and a short spend ledger (free rank edits on Skills remain for imports and house rulings)
- Portraits (including animated GIF support via hybrid storage)

### Plan and track missions (Run Library)
GM-facing **Run / Mission Planner** for jobs at your table:
- **Run Library** — list and filter missions by status (Planning / Active / Completed / Failed) and involved characters
- **Structured briefing** — client / Mr. Johnson, location, tags, primary & secondary objectives, opposition, complications
- **Team** — link one or more library runners to a run
- **Payout & heat** — expected vs actual nuyen and karma; simple heat delta
- **Session log** — timeline notes (session beats, complications, heat, objectives)
- **Outcome & suggested awards** — aftermath summary plus equal-split award *suggestions* (does not auto-apply to characters)
- Rich-text GM notes and story fields with shared format toolbar (bold, lists, etc.)

### Import what you already have
- **Chummer** JSON and **`.chum5`** files
- Native **`.shadowdeck`** packages
- Ways to import: sidebar **Import Character…**, **File → Import Character…** (⌘O), drag-and-drop onto the character library or Import drop zone, or double-click a `.shadowdeck` package in Finder (also works dropped on the Dock icon)
- Original Chummer payload is stored when you import, so you can re-export a faithful `.chum5` later

### Export for the table
| Format | Best for |
|--------|----------|
| **PDF character sheet** | GMs, Discord, printable review (includes portrait when set) |
| **Chummer `.chum5`** | Online hubs that expect Chummer files (original import when available, else best-effort regenerate) |
| **`.shadowdeck` package** | Backups and moving between Macs |

### Catalogs & effects
- Bundled **SR5 reference catalog** (gear, weapons, armor, cyberware, bioware, qualities, skills, adept powers) — no Chummer install required
- Equipping gear, installing augs, qualities, and powers **updates attributes, armor, initiative, and pools** on the summary sheet
- Custom items can carry their own stat modifiers

---

## Getting started

1. Download a [Release](https://github.com/RcktMan77/ShadowDeck/releases) build, **or** open **ShadowDeck.xcodeproj** in Xcode 16+ and Run, **or** build with `Scripts/release_build.sh`.
2. **Create → New Character** (or ⌘N) for the wizard, **or** **Import Character…** a Chummer / `.shadowdeck` package, **or** load samples from the Character Library toolbar.
3. Open a character for the play sheet; use **Export…** for PDF, Chummer, or a portable package.
4. **Create → New Run** (or ⌘⇧R) to plan a job, or open **Library → Runs** to browse the **Run Library**.

### Sidebar at a glance
| Section | Items |
|---------|--------|
| **Library** | Characters · Runs |
| **Create** | New Character · New Run · Import Character… |

### First launch
You’ll see a short branded splash (skip with click or any key). Loading-style quips are flavor only — the app is already ready.

---

## Requirements

- **macOS 14.0** or later
- For development: **Xcode 16+**

---

## Tips

- **Profile fields** (contacts, attributes, gear equip) save as you go.
- **Rich-text notes** (character notes, contacts, run GM notes / outcome fields) include a format toolbar; long text scrolls inside the editor.
- **Lifestyle** tab surfaces due / covered / underfunded on the Summary banner; process month only when you choose (no automatic calendar charge).
- **Plan** tab (Advancement Planner) spends `karmaAvailable` with edition rules; the Skills tab can still adjust ranks without cost when you need to fix an import or apply a table ruling.
- **House Rules…** on the character identity area apply after chargen and affect validation/essence ceilings.
- Re-import a Chummer file once if you want **byte-faithful** `.chum5` re-export of that original file.
- Run **suggested awards** are planning aids only — apply karma/nuyen on each character sheet when you choose.

---

## For developers

Branching (`main` / `develop` / `feature/*` / `release/*`) is described in [Docs/BRANCHING.md](Docs/BRANCHING.md). Build, test, and packaging notes live under [Docs/DESIGN.md](Docs/DESIGN.md) and [Docs/CHUMMER_IMPORT.md](Docs/CHUMMER_IMPORT.md).

```bash
# Debug build
xcodebuild -project ShadowDeck.xcodeproj -scheme ShadowDeck \
  -destination 'platform=macOS' build

# Tests
xcodebuild -project ShadowDeck.xcodeproj -scheme ShadowDeck \
  -destination 'platform=macOS' test

# Unsigned Release app → build/Release/ShadowDeck.app
Scripts/release_build.sh

# Refresh README marquee screenshots (in-app capture → Screenshots/)
Scripts/capture_readme_screenshots.sh
```

Regenerate the bundled catalog from a Chummer `data/` folder:

```bash
python3 Scripts/build_catalog_from_chummer.py /path/to/Chummer/data
```

---

## License & credits

- Application source: see [LICENSE](LICENSE).
- Bundled catalog data is derived from Chummer5a open data (GPL-3.0); see `ShadowDeck/Resources/Catalog/NOTICE.txt`.
- Brand fonts: Orbitron / Rajdhani (SIL Open Font License) under `Resources/Fonts/`.
- Splash and icon art are original generated assets for this fan tool.

**Shadowrun** names and setting elements remain trademarks of their owners. Use this app for personal tabletop play; respect the rights of book publishers when importing your own PDFs or materials.
