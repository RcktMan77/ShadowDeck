# README marquee screenshots

Stills and short silent GIFs for [README.md](../../README.md).

Maintainer capture automation (if used) is **local-only** and not part of the public repository. Assets in this folder are the source of truth for the README marquee.

| File | View |
|------|------|
| `01-splash.jpg` | Launch splash (hero) |
| `02-library.jpg` | Character Library |
| `03-generation-role.jpg` | Wizard · Concept & Role |
| `04-character-sheet.jpg` | Character play sheet (Summary) |
| `05-dice-roller.jpg` | Skills + dice inspector after a skill roll |
| `06-rules-reference.jpg` | Rules Reference window — cards + calculators |
| `07-run-mission-flow.gif` | Run Library → create job → team/log/objectives → complete → library |
| `08-advancement-planner.gif` | Advancement Planner (scroll skills → plan → apply) |
| `09-pdf-library.jpg` | Rules Reference → Library mode (sample PDF shelf) |
| `thumbs/02–05-*.jpg` | Equal-size UI thumbnails (top marquee) |
| `thumbs/06-rules-reference.jpg` · `thumbs/09-pdf-library.jpg` | Feature-section stills |
| `thumbs/*-poster.jpg` | Mid-GIF stills with play overlay (README click-to-play) |

Full UI stills ~1800px long edge; thumbs ~960px. GIFs are silent and looping; storyboards use settled keyframes plus short crossfades.

**Layout:** The README keeps a **lean top marquee** (splash + character thumbs + mission/advance GIFs). Rules Reference and PDF Library stills live **next to their feature copy** so the page does not stack every screenshot at the top.

**Automation:** The capture script optimizes GIFs, builds still thumbs, generates **click-to-play posters** (play glyph on a mid-GIF frame), copies assets into this folder, then **deletes originals** from the app’s Application Support capture directory so the repo copy is the source of truth.

**Click-to-play:** GitHub has no pause/play control for GIFs and autoplays any embedded GIF. The README uses a `<details>` / `<summary>` poster; expanding reveals the looping GIF on the same page (better than linking to the raw file browser).

**Privacy:** Capture always uses an **in-memory** character library seeded with sample characters only (`LibraryEnvironment.marketingCapture()`). The mission GIF creates its own run. Rules / PDF shots use **synthetic sample PDFs** in a temp shelf (labeled “sample”) with bundled original cover art under `Resources/Brand/MarketingPDFCovers/` — never your on-disk personal PDF library or character data, and never publisher rulebook assets.
