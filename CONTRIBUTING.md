# Contributing to Sylvra

Thanks for your interest in Sylvra! This document explains how contributions work.

## Who can contribute

- **Issues are welcome from everyone**: bug reports, ideas and feedback help a lot. Please search existing issues first.
- **Pull requests are limited to collaborators.** If you would like to contribute code, open an issue first and describe what you want to change. We will get in touch if it fits the direction of the project.

## Before you start

1. Read the specs to understand the scope and design:
   - [`specs/projectidea.md`](specs/projectidea.md) — vision, scope, non-goals
   - [`specs/architecture.md`](specs/architecture.md) — feature slices, integrations, CI and release
   - [`specs/ux.md`](specs/ux.md) — layout, interactions, color system, motion
2. Read [`AGENTS.md`](AGENTS.md). It contains the coding conventions and product rules — for humans and AI agents alike.
3. For larger changes, open an issue or discussion first so we can agree on the approach.

## Development setup

Requirements:

- macOS (latest major release) and Xcode (latest release)
- `git`
- Optional: [GitHub CLI](https://cli.github.com) (`gh`) and [Claude Code](https://docs.claude.com/en/docs/claude-code) for the AI features

```bash
git clone git@github.com:mduu/sylvra.git
cd sylvra
open Sylvra.xcodeproj
```

Before opening a PR, run `scripts/format.sh`, `scripts/lint.sh` and `scripts/test.sh` (SwiftLint: `brew install swiftlint`).

## Workflow

1. Create a branch from `main` (`feature/<short-name>`, `fix/<short-name>`).
2. Make small, focused commits with imperative messages (`Add intra-line diff for modified line pairs`).
3. Keep the specs in sync: if your change contradicts or extends a spec, update it in the same PR.
4. Run lint and tests locally (`scripts/lint.sh`, `scripts/test.sh`) before opening the PR.
5. Open a pull request against `main`:
   - describe **what** changed and **why**,
   - link the related issue,
   - add screenshots or a short screen recording for UI changes (light and dark appearance),
   - state any new dependency and why it is needed.
6. PR validation (lint, build, tests) must pass.
7. PRs are merged with **squash** or **rebase** — no merge commits. Keep the PR title meaningful; with squash it becomes the commit message.

## Code guidelines (short version)

- Everything in the repository is **English**: code, comments, docs, commit messages.
- Swift 6 with strict concurrency, SwiftUI first, `@Observable`, `async/await`.
- Code is organized in **feature slices**; slices never import each other.
- Views follow the **container / presentational** split: `*Screen` owns state and side effects, `*View` stays pure.
- Use the `DesignSystem` for colors, fonts and animations — no hardcoded colors.
- Add tests for logic and a regression test for every bug fix.

The full rules are in [`AGENTS.md`](AGENTS.md).

## AI-assisted contributions

Using AI coding agents is welcome — Sylvra is built for that era. You are responsible for every line you submit: review the generated code, make sure it follows `AGENTS.md`, and that tests pass.

## Reporting security issues

Please do **not** open a public issue for security vulnerabilities. Use GitHub's [private vulnerability reporting](https://github.com/mduu/sylvra/security/advisories/new) instead.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
