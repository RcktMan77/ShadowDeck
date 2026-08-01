# README marquee screenshots

Stills and short silent GIFs for [README.md](../../README.md). Regenerate with:

```bash
Scripts/capture_readme_screenshots.sh
```

| File | View |
|------|------|
| `01-splash.jpg` | Launch splash (hero) |
| `02-library.jpg` | Character Library |
| `03-generation-role.jpg` | Wizard · Concept & Role |
| `04-character-sheet.jpg` | Character play sheet (Summary) |
| `05-dice-roller.jpg` | Skills + dice inspector after a skill roll |
| `07-run-mission-flow.gif` | Run Library → create job → team/log/objectives → complete → library |
| `08-advancement-planner.gif` | Advancement Planner (scroll skills → plan → apply) |
| `thumbs/02–05-*.jpg` | Equal-size UI thumbnails (linked from README) |
| `thumbs/*-poster.jpg` | Mid-GIF stills with play overlay (README click-to-play) |

Full UI stills ~1800px long edge; thumbs ~960px. GIFs are silent and looping; storyboards use settled keyframes plus short crossfades.

**Automation:** The capture script optimizes GIFs, builds still thumbs, generates **click-to-play posters** (play glyph on a mid-GIF frame), copies assets into this folder, then **deletes originals** from the app’s Application Support capture directory so the repo copy is the source of truth.

**Click-to-play:** GitHub has no pause/play control for GIFs and autoplays any embedded GIF. The README uses a `<details>` / `<summary>` poster; expanding reveals the looping GIF on the same page (better than linking to the raw file browser).

**Privacy:** Capture always uses an **in-memory** library seeded with sample characters only (`LibraryEnvironment.marketingCapture()`). The mission GIF creates its own run. Your on-disk personal libraries are never opened during marquee capture.
