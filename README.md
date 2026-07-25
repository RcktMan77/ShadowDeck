# ShadowDeck

**Native macOS character creation & campaign management for Shadowrun 4th, 5th, and 6th edition.**

ShadowDeck is a production-grade SwiftUI app designed to rival (and eventually surpass) the feature set of Chummer5a on Windows—while feeling fully at home on the Mac.

## Vision

- Beautiful, HIG-compliant macOS experience
- Multi-edition character generation and long-term campaign tracking
- Rich **at-a-glance** character summary with portrait/avatar
- Reliable import from Chummer (JSON first, then `.chum5`)
- Edition-aware rules engine; data-driven where practical
- Clear architecture a single developer can own long-term

## Tech Stack

| Layer | Choice |
|--------|--------|
| Language | Swift 5 / Swift 6 concurrency readiness |
| UI | SwiftUI (macOS 14+) |
| Architecture | Observation + protocol-oriented design |
| Persistence | SwiftData (preferred; Core Data if needed) |
| Packaging | Xcode project; SPM modules if modularity helps |
| Tests | XCTest for domain, rules, import, persistence |

**Bundle ID:** `com.shadowdeck.ShadowDeck`  
**Deployment target:** macOS 14.0+  
**Category:** Role-Playing Games

## Project Layout

```
ShadowDeck/
├── App/              # App entry, scene configuration
├── Models/           # Domain models (Phase 1+)
├── Rules/            # Edition-aware rules engine (Phase 1+)
├── Persistence/      # SwiftData / storage (Phase 2+)
├── Import/           # Chummer JSON & .chum5 (Phase 3+)
├── UI/               # Views and view models
├── Resources/        # Game data files (JSON/plist)
└── Assets.xcassets   # Icons, accent color, images
```

## Phased Delivery

| Phase | Focus | Status |
|-------|--------|--------|
| **0** | Project bootstrap & foundation | ✅ Complete |
| **1** | Core domain models & multi-edition support | ✅ Complete |
| **2** | Persistence layer (SwiftData + avatars) | ✅ Complete |
| **3** | Import pipeline (Chummer JSON / `.chum5`) | ✅ Complete |
| **4** | Character generation wizard | Pending |
| **5** | Main character summary (at-a-glance) | Pending |
| **6** | Detailed management views | Pending |
| **7** | Polish, export, packaging | Pending |
| **8** | Extensibility (optional stretch) | Pending |

See [Docs/DESIGN.md](Docs/DESIGN.md) for architecture notes and open decisions.

## Requirements

- macOS 14.0 or later (runtime)
- Xcode 16+ (development)
- Accept the Xcode license: `sudo xcodebuild -license`

## Build & Run

```bash
# Open in Xcode
open ShadowDeck.xcodeproj

# Or build from the command line
xcodebuild \
  -project ShadowDeck.xcodeproj \
  -scheme ShadowDeck \
  -destination 'platform=macOS' \
  build
```

Run tests:

```bash
xcodebuild \
  -project ShadowDeck.xcodeproj \
  -scheme ShadowDeck \
  -destination 'platform=macOS' \
  test
```

## Principles

1. Prefer clarity and long-term maintainability over cleverness.
2. Ask early about visual design, prioritization, and ambiguous rules.
3. Focused commits with descriptive messages (`Phase N complete: …`).
4. Tests for logic that would be painful to regress.
5. No hard-coded large game-data tables when a data file is feasible.
6. Document non-obvious decisions in code comments or `Docs/DESIGN.md`.

## License

Source available under the terms specified in [LICENSE](LICENSE).  
Shadowrun is a trademark of its respective owners. This project is an unofficial fan tool and is not affiliated with or endorsed by Catalyst Game Labs or The Topps Company, Inc.
