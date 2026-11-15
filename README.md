<p align="center">
  <img src="assets/AppIcon-preview.png" alt="Sylvra app icon" width="160">
</p>

<h1 align="center">Sylvra</h1>

<p align="center"><em>A quiet place for focused review.</em></p>

Sylvra is a native macOS app for reviewing **your team's GitHub pull requests**, with your local Claude Code as a second pair of eyes. It is my personal review tool, built around how I review. If it fits your workflow too, you're welcome to use it.

Sylvra is **not a Git client** and not a code generator. It helps you understand a change, find what matters and write clear, factual review comments. You stay the reviewer.

<p align="center">
  <img src="docs/screenshots/app-16-violet.png" alt="Sylvra: inbox, pull request, diff with an inline AI finding, AI inspector" width="100%">
</p>

*The name is a coined word from Latin* silva */ English* sylvan *— forest, wooded.*

## What it focuses on

### 1. Understand the change quickly
- **Inbox** of PRs that need you: review requests to you and your teams, PRs you're involved in, your own PRs.
- **PR at a glance**: description, reviewers, merge status in plain words, checks, commits.
- **Change map** and file tree (with viewed state synced to GitHub).
- **AI summary and reading order**: which files to read first and where the risky areas are. The diff sorts itself accordingly.
- **Since my last review**: only what changed since you last reviewed, plus a banner when someone pushes.

### 2. A diff made for reading
- Side by side with ribbons between old and new, or inline; changed hunks or full files.
- Syntax highlighting, intra-line changes, reveal hidden context step by step (+20 / all).
- Review threads inline under the line they belong to, with emoji reactions.
- Keyboard first: `j`/`k` files, `n`/`p` changes, `v` viewed, `⌘F` find, `⌘K` command palette, `?` for all shortcuts.

### 3. AI as a reviewer's assistant, never as the reviewer
- **One-click AI review** with your locally installed Claude Code, using your repo's `AGENTS.md`, `CLAUDE.md` and specs as context.
- **Several models in parallel** (e.g. Opus + Fable); findings are merged and show who found them. Large PRs are split across agents.
- **Findings in the diff**: highlighted lines and a card below them with rationale and the suggestion as a mini diff.
- **Patterns**: which conventions the change follows, violates or introduces.
- **Discuss code privately**: ask Claude about selected lines in a private chat.
- The AI agents run **read-only** and **never post anything**. A finding becomes a comment only when you turn it into one.

### 4. Factual, short review comments
- Comments with code suggestions, replies, resolve, pending reviews and submit.
- **Writing help**: rephrase factually (observation → effect → suggestion), make it shorter, undo.
- **English or German per comment**: switching translates the draft.
- **Tone check** while you type: flags dismissive, absolute or loaded wording ("obviously", "always", "falsch" …) and offers a factual rephrase.

### 5. Into the code when needed
- **Open in IDE** (Rider, VS Code, Xcode or the default app) in a Sylvra-managed worktree, so your working copy stays untouched.
- **Terminal panel** and your own **custom tools** on files and folders.

<p align="center">
  <img src="docs/screenshots/app-21-tone-check.png" alt="Comment composer with tone check" width="49%">
  <img src="docs/screenshots/app-17-violet-light.png" alt="Sylvra in light mode" width="49%">
</p>

## Principles

1. **You review, the AI assists.** AI content is always marked as such and is never posted on its own.
2. **Comments stay factual.** Sylvra nudges towards short, neutral, constructive wording.
3. **Your working copy is yours.** PR checkouts go into separate worktrees; nothing is stashed or changed silently.
4. **No backend, no telemetry.** GitHub tokens stay in the macOS Keychain. Code reaches an AI model only through your own Claude Code, and only when you start a review or chat.

## Status

A personal project, used and developed for my own reviews. There is **no release yet**: build it from source. Expect rough edges.

## Requirements

- macOS (latest major release) and Xcode (latest release) to build
- `git`
- A github.com account and the [GitHub CLI](https://cli.github.com) (`gh`), logged in (Sylvra uses its token)
- Optional, for the AI features: [Claude Code](https://docs.claude.com/en/docs/claude-code), installed and logged in

## Getting started

```bash
git clone git@github.com:mduu/sylvra.git
cd sylvra
open Sylvra.xcodeproj      # run the "Sylvra" scheme
```

Launch with the argument `--demo` to try the app with sample data, without a GitHub account.

To build an installable, signed and notarized `Sylvra-<version>.dmg` for another Mac (needs a Developer ID certificate):

```bash
xcrun notarytool store-credentials sylvra-notary --apple-id <apple-id> --team-id <team-id>   # once
scripts/release.sh         # → .build/release/Sylvra-<version>.dmg
```

For development:

```bash
scripts/test.sh            # package tests + app build
scripts/lint.sh            # SwiftLint + swift format
scripts/screenshot.sh      # screenshots of the running app (demo data)
```

## Documentation

| Document | Content |
|---|---|
| [specs/projectidea.md](specs/projectidea.md) | Vision, problem, features, non-goals |
| [specs/architecture.md](specs/architecture.md) | Feature slices, integrations (GitHub, git, AI agents, IDEs), CI |
| [specs/ux.md](specs/ux.md) | Layout, interactions, color system, motion, shortcuts |
| [specs/roadmap.md](specs/roadmap.md) · [specs/backlog.md](specs/backlog.md) | What's done and what might come |
| [AGENTS.md](AGENTS.md) | Guidelines for AI coding agents working on this repo |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Issues and pull requests |

## Contributing

Issues and pull requests are welcome. Since this is a personal tool, I'll prioritize what fits my own review workflow and the principles above.

## License

[MIT](LICENSE) © Marc Dürst
