<p align="center">
  <img src="assets/AppIcon-preview.png" alt="Sylvra app icon" width="160">
</p>

<h1 align="center">Sylvra</h1>

<p align="center"><em>A quiet place for focused review.</em></p>

Sylvra is a native macOS app for reviewing GitHub pull requests in the age of agentic coding. It captures the essence of a change at a glance, runs AI reviews with your local Claude Code installation, and lets you comment — including code suggestions — without leaving the app.

Sylvra is **not a Git client**. It is a specialized PR review client.

*The name is a coined word from Latin* silva */ English* sylvan *— forest, wooded.*

## Features

- **PR inbox** — open PRs that need your attention, including team requests and watched repos/paths, not only PRs assigned to you.
- **Complete PR view** — description, author, refs, reviewers, merge status, checks and commits (with copyable SHAs); one click to GitHub, e.g. for a failing build.
- **Change essence** — AI summary, a change map of namespaces/folders and *"What patterns are used or missed?"*.
- **A diff with a wow effect** — side-by-side or inline, focused hunks or full files, commit-by-commit review, "changes since my last review".
- **One-click AI review** — runs your local Claude Code (more agents later) with selectable models and effort, in parallel for large PRs, with your repo's `AGENTS.md`/`CLAUDE.md`/specs as context.
- **Linked findings** — AI findings are highlighted inline (Xcode-style gradients); one click jumps to the code.
- **AI chat** — ask questions about the PR in your preferred language.
- **Review comments** — inline comments with code suggestions, replies, resolve threads, submit reviews.
- **Open in IDE** — Rider, VS Code, Xcode or the default app, in a worktree or your main clone.
- **Terminal and custom tools** — terminal panel with tabs and your own commands on files and folders.

## Requirements

- macOS (latest major release)
- Xcode (latest release) to build
- `git` installed
- A GitHub account (github.com)
- Optional: [GitHub CLI](https://cli.github.com) (`gh`) for sign-in
- Optional: [Claude Code](https://docs.claude.com/en/docs/claude-code) installed and logged in, for AI features (other agents planned)

## Getting started

> The project is in its specification phase. Build instructions will be added with the first code.

```bash
git clone <repo-url> sylvra
cd sylvra
open Sylvra.xcodeproj
```

## Documentation

| Document | Content |
|---|---|
| [specs/projectidea.md](specs/projectidea.md) | Vision, problem, features, non-goals |
| [specs/architecture.md](specs/architecture.md) | Feature slices, integrations (GitHub, git, AI agents, IDEs), CI and release |
| [specs/ux.md](specs/ux.md) | Layout, interactions, color system, motion, shortcuts |
| [AGENTS.md](AGENTS.md) | Guidelines for AI coding agents working on this repo |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute: issues, pull requests, workflow |

## Privacy

Sylvra has no backend and no telemetry. Code is only sent to an AI model through your own locally installed AI agent (e.g. Claude Code), and only when you start an AI review or chat. GitHub tokens are stored in the macOS Keychain.

## License

[MIT](LICENSE) © Marc Dürst
