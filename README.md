# ShadowDeck

**A native macOS campaign companion for Shadowrun** — create runners, track missions, manage lifestyle and karma, and roll dice for Shadowrun **4th, 5th, and 6th edition**.

**Status:** Active single-player development. Core campaign tools below are usable at the table. Shared online / multi-user features are planned later.

ShadowDeck is an unofficial fan project. Build characters with a guided wizard, import from Chummer, keep a living library, run jobs for your table, and export sheets your GM or hub can use.

**Why ShadowDeck?** Chummer remains excellent for deep builds and data. ShadowDeck is for **running the campaign** — play sheets, runs, lifestyle, advancement, contacts, and an edition-aware dice roller in one Mac-native app.

> Shadowrun is a trademark of its respective owners. ShadowDeck is **not** affiliated with or endorsed by Catalyst Game Labs or The Topps Company, Inc.

<p align="center">
  <img src="Docs/Screenshots/01-splash.jpg" alt="ShadowDeck launch splash" width="900" />
</p>

<!-- Character UI thumbs -->
<table align="center" width="900">
  <tr>
    <td width="25%" align="center" valign="top">
      <a href="Docs/Screenshots/02-library.jpg">
        <img src="Docs/Screenshots/thumbs/02-library.jpg" alt="Character library" width="210" />
      </a><br />
      <sub>Character Library</sub>
    </td>
    <td width="25%" align="center" valign="top">
      <a href="Docs/Screenshots/03-generation-role.jpg">
        <img src="Docs/Screenshots/thumbs/03-generation-role.jpg" alt="Character generation — Concept &amp; Role" width="210" />
      </a><br />
      <sub>New Character · Role</sub>
    </td>
    <td width="25%" align="center" valign="top">
      <a href="Docs/Screenshots/04-character-sheet.jpg">
        <img src="Docs/Screenshots/thumbs/04-character-sheet.jpg" alt="Character summary sheet" width="210" />
      </a><br />
      <sub>Play sheet</sub>
    </td>
    <td width="25%" align="center" valign="top">
      <a href="Docs/Screenshots/05-dice-roller.jpg">
        <img src="Docs/Screenshots/thumbs/05-dice-roller.jpg" alt="Dice roller with skill roll and Edge options" width="210" />
      </a><br />
      <sub>Dice roller</sub>
    </td>
  </tr>
</table>

<!-- Feature GIFs: GitHub has no true in-place play control; details/summary expands the looping GIF on the page. -->
<table align="center" width="900">
  <tr>
    <td width="50%" align="center" valign="top">
      <details>
        <summary>
          <img src="Docs/Screenshots/thumbs/07-run-mission-flow-poster.jpg" alt="Run mission flow — expand to play" width="420" /><br />
          <sub><strong>▶ Run / mission flow</strong> — expand to play · create a job, brief the team, log the session, complete objectives, set the outcome, return to the Run Library</sub>
        </summary>
        <p align="center">
          <img src="Docs/Screenshots/07-run-mission-flow.gif" alt="Run mission flow animation" width="420" />
        </p>
      </details>
    </td>
    <td width="50%" align="center" valign="top">
      <details>
        <summary>
          <img src="Docs/Screenshots/thumbs/08-advancement-planner-poster.jpg" alt="Advancement planner — expand to play" width="420" /><br />
          <sub><strong>▶ Advancement Planner</strong> — expand to play · plan skill and attribute raises, apply karma, watch ranks update</sub>
        </summary>
        <p align="center">
          <img src="Docs/Screenshots/08-advancement-planner.gif" alt="Advancement planner animation" width="420" />
        </p>
      </details>
    </td>
  </tr>
</table>

---

## What ShadowDeck is today

A **strong single-user foundation** for tabletop Shadowrun campaigns on the Mac:

| Area | Highlights |
|------|------------|
| **Characters** | Multi-edition chargen, library (list + gallery), interactive play sheet, portraits (including animated GIFs) |
| **Runs** | Mission library, briefing, team, session log, payouts / heat, suggested awards |
| **Lifestyle** | Monthly burn, reserve, process month, ledger |
| **Advancement** | Plan tab with edition costs, cart, Buy Now / Apply, ledger |
| **Contacts** | Tags, favor standing, interaction log, optional soft run links |
| **Dice** | Edition-aware hits & glitches, house-rule toggles, Edge (Push the Limit / Second Chance), one-click from skills & attributes |

That combination is meant to be a **campaign companion** — not only a character keeper.

---

## Features

### Build a runner
- **Edition-aware generation** for SR4, SR5, and SR6
- Guided wizard: metatype, priorities, attributes, skills, qualities, resources, magic/resonance
- **House rules** — Sum-to-Ten, free knowledge, expanded contacts, prime runner packages, **dice rules** (glitch threshold, Rule of Six, hits on 4+, and more), and other popular table toggles
- Role recommendations and painted archetype / metatype art

### Character library & play sheet
- Local library with **search**, **list** and **gallery** views
- Interactive **Summary**: portrait, attributes (base + gear/aug bonuses), condition, karma, nuyen, initiative, armor, pools
- Tabs for **Skills**, **Gear**, **Augs**, **Qualities**, **Contacts**, **Lifestyle**, **Plan** (Advancement Planner), and **Magic**
- **Portraits** — static images or multi-frame GIFs (hybrid storage)
- **Dice roller** (⌘D) — trailing inspector; roll from skills or attributes; Push the Limit and Second Chance with session Edge; optional house-rule dice math

### Contacts (enriched)
- Loyalty / Connection plus profile fields from import or free entry
- **Tags**, **favor standing**, and a dated **interaction log**
- Optional soft link from a log entry to a **Run**
- Search and filter (name, role, tags, pending favors)

### Lifestyle
- Monthly cost, prepaid months, **reserve** (spent first), Process Month (1–3 mo), prepay, short payment ledger
- Summary banner for due / covered / underfunded

### Advancement (Plan tab)
- Edition karma costs for skill and attribute raises
- Persistent plan cart, Buy Now / Apply Plan, suggestions, spend ledger
- Free rank edits on the Skills tab remain for imports and table rulings

### Runs / Mission Tracker (v1)
- **Run Library** — filter by status, character, and **ruleset**
- Briefing: client, location, tags, objectives, opposition, complications
- **Team** limited to library characters that match the run’s ruleset (others greyed with reason)
- Session log, payout & heat, outcome notes, suggested equal-split awards, and **Apply Awards…** (explicit commit of nuyen + karma to linked runners)

### Import & export
| | |
|--|--|
| **Import** | Chummer JSON / `.chum5`, `.shadowdeck` packages — sidebar, File menu (⌘O), drag-and-drop, Finder double-click |
| **Export** | PDF character sheet, Chummer `.chum5` (original payload when available), portable `.shadowdeck` package |

### Catalogs & effects
- Bundled **SR5** reference catalog (gear, weapons, armor, cyberware, bioware, qualities, skills, powers)
- Equipping gear, augs, qualities, and powers updates the play sheet (attributes, armor, initiative, pools)

---

## Getting started

1. Download a [Release](https://github.com/RcktMan77/ShadowDeck/releases), **or** open **ShadowDeck.xcodeproj** in Xcode 16+ and Run, **or** build with `Scripts/release_build.sh`.
2. **Create → New Character** (⌘N), **Import Character…** (⌘O), or **Load Samples** from the Character Library.
3. Open a character for the play sheet; use **Dice** (⌘D) or the dice control on a skill/attribute to roll.
4. **Create → New Run** (⌘⇧R) or **Library → Runs** for missions.

### Sidebar
| Section | Items |
|---------|--------|
| **Library** | Characters · Runs |
| **Create** | New Character · New Run · Import Character… |

### First launch
A short branded splash appears (skip with click or any key). Flavor “loading” quips do not block use — the app is ready immediately.

### Requirements
- **macOS 14.0** or later  
- Development: **Xcode 16+**

---

## Tips for the table

- Profile fields (attributes, gear equip, contacts) **save as you go**.
- Rich-text notes include a format toolbar; **⌘B / ⌘I / ⌘U** work while editing.
- **Lifestyle** is never auto-charged; process months only when you choose.
- **Plan** spends `karmaAvailable` with edition (and house-rule) costs; Skills can still adjust ranks freely for imports/GM fiat.
- **House Rules…** on the character identity area apply after chargen and feed validation, essence, and the **dice roller**.
- Run **Apply Awards…** (on a Completed/Failed run) credits equal-split nuyen and karma to linked runners with a confirmation sheet; it is never automatic.
- Re-import a Chummer file once if you need **byte-faithful** `.chum5` re-export of the original payload.

---

## Roadmap (near term)

Guiding principle: **deepen existing campaign tools** and high-frequency play aids before large multi-user work.

| Priority | Feature | Why | Effort |
|----------|---------|-----|--------|
| **1** | **Rules reference / quick calculators** | Searchable core reference + Drain, Overwatch, and similar calculators for daily play | Medium |
| **2** | **Run Tracker Phase 2** | Templates, stronger contact links from runs, outcome flow, open threads; custom award shares | Medium |
| **3** | **Multi-domain initiative / combat tracker** | Major GM aid; better after the core loop is polished | Larger |
| **4** | **Shared Hub (multi-user)** | Most ambitious; after the single-user experience is solid | Large |

---

## For developers

Branching (`main` / `develop` / `feature/*` / `release/*`): [Docs/BRANCHING.md](Docs/BRANCHING.md). Design notes: [Docs/DESIGN.md](Docs/DESIGN.md). Import: [Docs/CHUMMER_IMPORT.md](Docs/CHUMMER_IMPORT.md). Screenshot pipeline: [Docs/Screenshots/README.md](Docs/Screenshots/README.md).

```bash
# Debug build
xcodebuild -project ShadowDeck.xcodeproj -scheme ShadowDeck \
  -destination 'platform=macOS' build

# Tests
xcodebuild -project ShadowDeck.xcodeproj -scheme ShadowDeck \
  -destination 'platform=macOS' test

# Unsigned Release app → build/Release/ShadowDeck.app
Scripts/release_build.sh

# Refresh README marquees (stills, GIFs, click-to-play posters → Docs/Screenshots/)
Scripts/capture_readme_screenshots.sh
```

Regenerate the bundled catalog from a Chummer `data/` folder:

```bash
python3 Scripts/build_catalog_from_chummer.py /path/to/Chummer/data
```

---

## License

ShadowDeck source code is made available for **personal, non-commercial use**.

You may:
- View, download, and build the source for your own personal use
- Modify it for your own personal campaigns
- Submit pull requests or suggestions

You may **not**:
- Sell, sublicense, or commercially redistribute the source code or compiled binaries derived from it
- Offer ShadowDeck (or a substantially similar product based on this codebase) as a paid service or commercial product without explicit written permission

Commercial licensing and future paid features (if any) will be handled separately.  
See the [LICENSE](LICENSE) file for the full terms.

### Credits

- Bundled catalog data derived from Chummer5a open data (GPL-3.0); see `ShadowDeck/Resources/Catalog/NOTICE.txt`
- Brand fonts: Orbitron / Rajdhani (SIL Open Font License) under `Resources/Fonts/`
- Splash and icon art are original generated assets for this fan tool

**Shadowrun** names and setting elements remain trademarks of their owners. Use this app for personal tabletop play; respect the rights of book publishers when importing your own materials.
