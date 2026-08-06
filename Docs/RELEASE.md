# Release packaging (signed + notarized)

Maintainer path for a **Developer ID–signed, notarized** macOS app zip.

## Prerequisites (local only — never commit secrets)

| Env var | Purpose |
|---------|---------|
| `CODESIGN_IDENTITY` | Full string, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `SHADOWDECK_NOTARY_PROFILE` | `notarytool` keychain profile name |

Create the notary profile once:

```bash
xcrun notarytool store-credentials "$SHADOWDECK_NOTARY_PROFILE" \
  --apple-id YOU@example.com \
  --team-id YOUR_TEAM_ID \
  --password "app-specific-password"
```

List signing identities:

```bash
security find-identity -v -p codesigning
```

Optional: put `export CODESIGN_IDENTITY=…` and `export SHADOWDECK_NOTARY_PROFILE=…` in `~/.bashrc` / `~/.zshrc` (not in the repo).

## One-command release

```bash
# From repo root
Scripts/release_build.sh --zip --sign --notarize
```

What this does:

1. **Release** build of `ShadowDeck.app` (unsigned intermediate in DerivedData).
2. **Codesign** with Hardened Runtime (`--options runtime`) + app entitlements + timestamp.
3. Zip to `dist/ShadowDeck-<version>-macos.zip`.
4. **notarytool submit** + wait.
5. **Staple** the ticket onto the `.app`, re-zip so the distributable contains the stapled app.

Unsigned / zip-only:

```bash
Scripts/release_build.sh              # app only → build/Release/ShadowDeck.app
Scripts/release_build.sh --zip        # + zip, no sign
Scripts/release_build.sh --zip --sign # signed zip (no notary)
```

Help:

```bash
Scripts/release_build.sh --help
```

## Smoke check after notarize

```bash
spctl --assess --type execute -v build/Release/ShadowDeck.app
xcrun stapler validate build/Release/ShadowDeck.app
```

## GitHub Release

After a green notarized zip:

```bash
gh release create "v$VERSION" "dist/ShadowDeck-${VERSION}-macos.zip" \
  --title "ShadowDeck $VERSION" \
  --notes "Signed and notarized macOS build."
```

Tag/version must match `MARKETING_VERSION` / `CFBundleShortVersionString` in the Xcode project.

## Notes

- No identities or passwords live in git (`Scripts/release_build.sh` is env-only).
- Hardened Runtime is required for notarization (`--options runtime` on codesign).
- If notarization fails, re-check the keychain profile and that the identity is **Developer ID Application**, not Apple Development.
