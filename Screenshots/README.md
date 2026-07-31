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
| `07-run-mission-flow.gif` | Run Library → create job → team/log/objectives → complete → library |
| `08-advancement-planner.gif` | Advancement Planner (scroll skills → plan → apply) |
| `thumbs/02–04-*.jpg` | Equal-size UI thumbnails (linked from README) |

Full UI stills ~1800px long edge; thumbs ~960px. GIFs are silent and looping; run/advance storyboards capture multiple samples per step for smoother playback.

**Privacy:** Capture always uses an **in-memory** library seeded with sample characters only (`LibraryEnvironment.marketingCapture()`). The mission GIF creates its own run. Your on-disk personal libraries are never opened during marquee capture.
