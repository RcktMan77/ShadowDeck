# ShadowDeck

**Create, import, and run Shadowrun characters on your Mac** — for Shadowrun 4th, 5th, and 6th edition.

ShadowDeck is an unofficial fan-made character and campaign companion for tabletop Shadowrun. Build runners with a guided wizard, pull in sheets from Chummer, keep a living library of characters, and export what your table or online hub needs.

> Shadowrun is a trademark of its respective owners. ShadowDeck is **not** affiliated with or endorsed by Catalyst Game Labs or The Topps Company, Inc.

<p align="center">
  <img src="Screenshots/01-splash.jpg" alt="ShadowDeck launch splash" width="900" />
</p>

<!-- Three equal UI thumbs; click opens the matching full-size screenshot. -->
<table align="center" width="900">
  <tr>
    <td width="33%" align="center" valign="top">
      <a href="Screenshots/02-library.jpg">
        <img src="Screenshots/thumbs/02-library.jpg" alt="Character library" width="280" />
      </a><br />
      <sub>Library</sub>
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

---

## What you can do

### Build a runner
- **Edition-aware generation** for SR4, SR5, and SR6
- Step-by-step wizard: metatype, priorities, attributes, skills, qualities, resources, magic/resonance
- **House rules catalog** — Sum-to-Ten, free knowledge, expanded contacts, prime runner packages, and more (stack individual rules or start from presets)
- Role recommendations and painted archetype / metatype art

### Keep a character library
- Local library of all your runners (search and filter)
- **Interactive play sheet**: attributes (base + gear/aug bonuses), condition monitors, karma, nuyen, initiative, armor, dice pools
- Tabs for skills, gear, augmentations, qualities, contacts, and magic
- Portraits (including animated GIF support via hybrid storage)

### Import what you already have
- **Chummer** JSON and **`.chum5`** files
- Native **`.shadowdeck`** packages
- Ways to import: sidebar **Import…**, **File → Import Character…** (⌘O), drag-and-drop onto the library or Import drop zone, or double-click a `.shadowdeck` package in Finder (also works dropped on the Dock icon)
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
2. **New Character** from the sidebar (or ⌘N) to run the wizard, **or**
3. **Import…** / **File → Import Character…** a Chummer (`.json` / `.chum5`) or **`.shadowdeck`** package (drag-and-drop also works), **or** load sample runners from the library toolbar.
4. Open a character for the play sheet; use **Export…** for PDF, Chummer, or a portable package.

### First launch
You’ll see a short branded splash (skip with click or any key). Loading-style quips are flavor only — the app is already ready.

---

## Requirements

- **macOS 14.0** or later
- For development: **Xcode 16+**

---

## Tips

- **Profile fields** (contacts, attributes, gear equip) save as you go.
- **Rich-text notes** use **Save Notes** (or collapse a contact to commit its notes).
- **House Rules…** on the character identity area apply after chargen and affect validation/essence ceilings.
- Re-import a Chummer file once if you want **byte-faithful** `.chum5` re-export of that original file.

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
