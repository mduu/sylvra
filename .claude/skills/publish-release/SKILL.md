---
name: publish-release
description: Publish a Sylvra build as a GitHub Release so colleagues can download it (tag v<version>, upload the notarized DMG). Only when the user explicitly asks to release/publish a build ("/publish-release", "release das", "auf GitHub veröffentlichen").
---

# Publish a release on GitHub

Publishing is outward-facing: only on the user's explicit request (AGENTS.md: never post to GitHub without an explicit user action).

1. **Which build**: the version in `Sylvra.xcodeproj/project.pbxproj` at `HEAD`. A notarized `.build/release/Sylvra-<that version>.dmg` must exist (`xcrun stapler validate`); `publish.sh` refuses a DMG whose version differs from HEAD. If it is missing or for another version (e.g. on another Mac), build it first with the `new-version` steps 3 (no bump unless HEAD has unreleased changes after the last bump — then ask).
2. **Preconditions** (the script checks them too): working tree committed, `main` pushed, no release `v<version>` yet, `gh auth status` logged in.
3. **Publish**: `scripts/publish.sh` — or `scripts/publish.sh --draft` when the user wants to review it on GitHub first. It tags `v<version>`, pushes the tag and creates the release with install notes and the commits since the previous tag.
4. **Report** the release URL and the download link for colleagues: https://github.com/mduu/sylvra/releases/latest
