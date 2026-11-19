---
name: new-version
description: Build a new Sylvra version for testing and put the DMG on iCloud Drive (commit, bump version, signed + notarized DMG, push). Use when the user asks for a "new version", "neue Version", "/new-version" or a build on iCloud Drive. Does NOT publish on GitHub — that is /publish-release.
---

# New version (iCloud Drive)

1. **Check**: `scripts/lint.sh` and `scripts/test.sh` must pass. Uncommitted work: commit it in small, focused commits (imperative messages, no `Co-Authored-By` trailer). Never commit `docs/screenshots/*` scratch files unasked.
2. **Bump** in `Sylvra.xcodeproj/project.pbxproj` — both values, two occurrences each:
   - `MARKETING_VERSION` (patch +1, e.g. 0.5.28 → 0.5.29)
   - `CURRENT_PROJECT_VERSION` (+1)
   Verify with `grep -c` (4 matches), commit `Bump version to <version>`.
3. **Build**: `scripts/release.sh` (archive, Developer ID, styled DMG, notarize, staple; several minutes — run in the background). Output: `.build/release/Sylvra-<version>.dmg`. If notarization credentials are missing on this Mac, tell the user to run `xcrun notarytool store-credentials sylvra-notary --apple-id <apple-id> --team-id UYT5K989XD` (`!` prefix) — or build with `SKIP_NOTARIZE=1` only if they agree.
4. **iCloud Drive**: copy the DMG to `~/Library/Mobile Documents/com~apple~CloudDocs/` and delete older `Sylvra-*.dmg` there.
5. **Push** `main`.
6. Report version, build number and that the DMG is on iCloud Drive. Do not create a GitHub release.
