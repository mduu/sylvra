# Sylvra — Roadmap

Working plan for the MVP. Each milestone is a vertical slice that ends in a runnable app, a commit on `main` and fresh screenshots in [`docs/screenshots/`](../docs/screenshots/).

Status: ✅ done · 🚧 in progress · ⏳ open

| # | Milestone | Status |
|---|---|---|
| M0 | Project skeleton: Xcode project, `SylvraKit` package with slices, lint, CI, scripts | ✅ |
| M1 | Platform basics: process runner, `gh` token, GitHub GraphQL client, screenshot pipeline | ✅ |
| M2 | Inbox: sections (requested from me, my teams, involved, my PRs), PR rows with avatars, refresh | ✅ |
| M3 | PR details: overview, description, refs, reviewers, merge state, checks, commits (copy SHA), open on GitHub | ✅ |
| M4 | Diff engine: unified diff parser, hunks, intra-line diff, file classification (unit-tested) | ✅ |
| M5 | Diff view: side-by-side / inline, focused / full file, file tree by namespace, change map, viewed toggle | ✅ |
| M6 | Review: existing threads, reply, resolve, new comments with suggestions, pending review, submit | ⏳ |
| M7 | Open in IDE: worktree manager, main-clone option, Rider / VS Code / Xcode / default app | ✅ |
| M8 | AI review: Claude Code provider, repo context discovery, structured findings, sharding, patterns, highlights | ⏳ |
| M9 | AI chat, agent language, multi-model | ⏳ |
| M10 | Activity indicator, notifications, terminal panel, custom tools, settings | ⏳ |
| M11 | Polish: syntax highlighting, animations, wow diff details, persistence cache | ⏳ |

## Decisions taken autonomously

Decisions made while building without the product owner present. Revisit when convenient.

- Package tests run via `swift test`; the app scheme only builds (Xcode does not pick up local-package test targets in app schemes).
- SwiftLint pinned to 0.65.1 in CI.
- Screenshots: `scripts/screenshot.sh <name> [app args]` builds, launches and captures the main window into `docs/screenshots/`.
- Launch argument `--demo` switches all loaders to fixture data (used for screenshots; real GitHub data otherwise).
- Inbox hides empty sections; the "Watched" and "Recently closed" sections follow with settings (M10).
- Team requests use `review-requested:@me -user-review-requested:@me` (GitHub expands teams), so no team list is needed.
- Diff view is SwiftUI (LazyVStack) for now; the AppKit/TextKit renderer for huge diffs, connector ribbons and configurable context lines (focused mode uses GitHub's 3 lines) follow in M11.
- The file navigator (change map + files) lives in `FeatureDiff` and is placed into the PR column through a view slot of `PullRequestScreen`, so the slices stay independent.
- Open in IDE uses one stable review worktree per repository (`~/Library/Application Support/Sylvra/worktrees/<owner>/<repo>`), so Rider keeps a single valid recent project; cleanup of Rider's recent list is not needed for now.
- Without a local clone, a blobless cache clone in Application Support backs the worktree.
- Main-clone checkout uses branch `review/pr-<n>` and asks before stashing (named stash).
