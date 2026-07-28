# Branching model

ShadowDeck uses a lightweight Gitflow-style layout.

| Branch | Role |
|--------|------|
| **`main`** | Stable line. Tagged releases live here (`v0.9.0`, …). Prefer green CI and review before merge. |
| **`develop`** | Integration / day-to-day default for ongoing work. |
| **`feature/*`** | Short-lived work branched from `develop`. |
| **`release/x.y.z`** | Release prep / freeze for a version (docs, version bumps, hotfixes). Branched when `develop` is ready to ship into `main`. |

## Day-to-day

```text
feature/my-change  ──PR──►  develop  ──PR──►  main  ──tag──►  vX.Y.Z
                                │               │
                                │               └── release/X.Y.Z (optional freeze line)
                                └── continue next work
```

1. Branch features from **`develop`**:
   ```bash
   git checkout develop && git pull
   git checkout -b feature/short-description
   ```
2. Open a PR **into `develop`** (not directly into `main` unless it’s a critical hotfix).
3. When a set of features is release-ready, open a PR **`develop` → `main`**.
4. After merge to `main`, cut the release:
   ```bash
   git checkout main && git pull
   git checkout -b release/0.10.0   # if you need a freeze line
   # bump version, notes, Scripts/release_build.sh --zip
   git tag -a v0.10.0 -m "ShadowDeck 0.10.0"
   git push origin main develop release/0.10.0 v0.10.0
   gh release create v0.10.0 dist/ShadowDeck-0.10.0-macos.zip --title "ShadowDeck 0.10.0"
   ```
5. Merge any release-branch fixes back into **`develop`** so nothing is lost.

## Hotfixes

Urgent production fixes may branch from **`main`** (or the current `release/*`), PR into `main`, tag a patch, then merge/cherry-pick into **`develop`**.

## CI

GitHub Actions runs build + test on pushes and PRs targeting `main`, `develop`, and `release/**`.
