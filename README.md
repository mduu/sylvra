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
- **Change essence** — AI summary and a change map of namespaces/folders, so you see where a PR changed before reading a single line.
- **Modern diff** — side-by-side or inline, focused hunks with configurable context or full files, syntax and intra-line highlighting, "changes since my last review".
- **One-click AI review** — runs your local Claude Code with selectable model and effort; large PRs are reviewed by multiple agents in parallel.
- **Linked findings** — AI findings are highlighted inline (Xcode-style gradients); one click jumps to the code.
- **AI chat** — ask questions about the PR with full code base context.
- **Review comments** — inline comments with GitHub code suggestions, turn AI findings into comments, submit reviews.
- **Open in IDE** — one click opens the PR in JetBrains Rider, Visual Studio Code or Xcode, using an isolated Git worktree.

## Requirements

- macOS (latest major release)
- Xcode (latest release) to build
- `git` installed
- A GitHub account (github.com)
- Optional: [GitHub CLI](https://cli.github.com) (`gh`) for sign-in
- Optional: [Claude Code](https://docs.claude.com/en/docs/claude-code) installed and logged in, for AI features

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
| [specs/architecture.md](specs/architecture.md) | Modules, integrations (GitHub, git, Claude Code, IDEs), data flow |
| [specs/ux.md](specs/ux.md) | Layout, interactions, visual language, shortcuts |
| [AGENTS.md](AGENTS.md) | Guidelines for AI coding agents working on this repo |

## Privacy

Sylvra has no backend and no telemetry. Code is only sent to an AI model through your own Claude Code installation, and only when you start an AI review or chat. GitHub tokens are stored in the macOS Keychain.

## License

TBD
