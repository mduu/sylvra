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
| M6 | Review: existing threads, reply, resolve, new comments with suggestions, pending review, submit | ✅ |
| M7 | Open in IDE: worktree manager, main-clone option, Rider / VS Code / Xcode / default app | ✅ |
| M8 | AI review: Claude Code provider, repo context discovery, structured findings, sharding, patterns, highlights | ✅ |
| M9 | AI chat, agent language, multi-model | ✅ |
| M10 | Activity indicator, notifications, terminal panel, custom tools, settings | ✅ |
| M11 | Polish: syntax highlighting, animations, wow diff details, persistence cache | ✅ |

## After the MVP (done)

Ideas taken over from comparable review tools (Review Buddy, Lo, Pulldog, review-man):

- ✅ Since my last review: diff scope from the last reviewed commit, banner, push detection with Refresh.
- ✅ AI reading order with risky areas; diff sorted by it.
- ✅ Discuss selected code privately with Claude; answers → factual draft comment.
- ✅ Keyboard: single keys (`j`/`k`, `n`/`p`, `v`, `?` …), command palette (⌘K).
- ✅ Find in diff (⌘F).
- ✅ Reveal hidden context step by step (+20 / all).
- ✅ Emoji reactions on review comments.
- ✅ Comment writing help: factual rephrasing, shorter, EN/DE per comment, tone check.

More ideas: [`backlog.md`](backlog.md).

## Next (after the MVP)

- **Delivery** ([`delivery.md`](delivery.md)): notifications for my pull requests and merge → Delivery tab (pipeline from GitHub) → AI verification per stage up to production → automatic for my own pull requests.

- Pagination beyond 100 changed files / 100 review threads / 50 comments per thread.
- Outdated and file-level review threads in a separate list.
- Horizontal scrolling for long lines in the side-by-side diff (currently truncated).
- Restore-stash helper after a main-clone checkout; cleanup of old per-PR agent worktrees.
- Translate AI findings into the comment language when turning them into comments.
- Watched repositories / path rules in the inbox, GitHub OAuth device flow as alternative to `gh`.
- Release pipeline (Developer ID, notarization, self-update from GitHub Releases, Homebrew tap).

## Decisions taken autonomously

Decisions made while building without the product owner present. Revisit when convenient.

- Package tests run via `swift test`; the app scheme only builds (Xcode does not pick up local-package test targets in app schemes).
- SwiftLint pinned to 0.65.1 in CI.
- Screenshots: `scripts/screenshot.sh <name> [app args]` builds, launches and captures the main window into `docs/screenshots/`. README screenshots come in pairs: `<name>.png` (light, `--appearance=light`) and `<name>-dark.png` (`--appearance=dark`), shown by the reader's theme via `#gh-light-mode-only` / `#gh-dark-mode-only`, dark first, each linked to its full-size file; below the hero image the README shows a detail crop (`<name>-detail[-dark].png`) that links to the full screenshot.
- Launch argument `--demo` switches all loaders to fixture data (used for screenshots; real GitHub data otherwise).
- Inbox hides empty sections; the "Watched" and "Recently closed" sections follow with settings (M10).
- Team requests use `review-requested:@me -user-review-requested:@me` (GitHub expands teams), so no team list is needed.
- Diff view is SwiftUI (LazyVStack) for now; the AppKit/TextKit renderer for huge diffs, connector ribbons and configurable context lines (focused mode uses GitHub's 3 lines) follow in M11.
- The file navigator (change map + files) lives in `FeatureDiff` and is placed into the PR column through a view slot of `PullRequestScreen`, so the slices stay independent.
- Open in IDE uses one stable review worktree per repository (`~/Library/Application Support/Sylvra/worktrees/<owner>/<repo>`), so Rider keeps a single valid recent project; cleanup of Rider's recent list is not needed for now.
- Without a local clone, a blobless cache clone in Application Support backs the worktree.
- Main-clone checkout uses branch `review/pr-<n>` and asks before stashing (named stash).
- AI review runs `claude --print --output-format json --json-schema … --tools Read Grep Glob` with the prompt on stdin, in the review worktree (read-only tools). Verified against Claude Code 2.1.
- Agent language defaults to the system language (e.g. German); per-PR model/effort/agents overrides are stored in UserDefaults.
- Review threads reach the diff the same way: `DiffScreen` has a `lineAccessory: (CodeLocation) -> View` slot and an `onStartComment` callback; `ReviewScreen` (FeatureReview) wraps the diff and owns loading, the toolbar counter and the submit sheet. `CodeLocation` lives in `SylvraCore`.
- Threads (and the composer) render full width below the line in both layouts instead of in the left/right half, so cards stay readable in narrow windows.
- *Comment now* is only offered without a pending review (like GitHub); it posts a review with event `COMMENT` containing one thread. Replies join the pending review when one exists, otherwise they post immediately.
- Comment ranges: ⇧-click a second line (gutter `+` or line number) on the same side to extend the draft to a range. Drag-to-select and the `C` shortcut follow later.
- Outdated threads are anchored to their `originalLine`; file-level threads (no line) are loaded but not shown yet.
- Deferred to M11: reactions, live mini-diff for suggestions, Markdown block elements beyond prose and fenced code (lists, headings render as plain text), pagination beyond 100 threads / 50 comments per thread.
- Launch arguments `--submit-review` (opens the submit sheet) and `--compose path:line` (opens the composer) exist for screenshots.
- AI findings reach the diff as `LineHighlight`s (FeatureDiff) set by the app; *Turn into comment* prefills the review composer (bold title, rationale, suggestion block). Translation into the comment language is not done yet — the reviewer edits the text.
- Window screenshots need an unlocked screen; while the Mac is locked no screenshots are taken (an offscreen renderer was tried and rejected because it does not reproduce materials and lists correctly).
- AI chat uses one resumable Claude Code session per PR (`--resume`); the first message carries the PR context (title, description, commits, AI summary and findings); `path:line` references in answers are links into the diff.
- Syntax highlighting is a lightweight line-based tokenizer (Swift, C#, TS/JS, Python, Go, Kotlin, Rust, Java, shell, JSON, YAML) instead of tree-sitter for now — no grammar dependencies, good enough for diffs; can be swapped behind `SyntaxHighlighter`.
- Terminal uses SwiftTerm 1.10.0 (MIT), pinned exactly: newer releases (1.11+) add a SwiftPM build-tool plugin (needs plugin trust in Xcode/CI) and, from 1.13, a Metal shader that requires the separately downloaded Metal toolchain. Only `FeatureTerminal` depends on it.
- Terminal sessions are owned by `TerminalModel` (views cached per session outside the SwiftUI hierarchy), so they survive switching PRs and hiding the panel. The panel sits below the diff in the detail column (`VSplitView`); ⌃\` and View ▸ Show Terminal toggle it; showing an empty panel opens a first tab.
- New tabs start in the PR's review worktree when it exists, otherwise in the home directory. Shells start as login shells (`argv[0]` prefixed with `-`); shell and external terminal app (Terminal, iTerm2, Ghostty, Warp or any bundle identifier) are configurable in Settings ▸ Terminal & Tools.
- The terminal stays dark violet in both appearances (`terminalBackground` is a slightly lighter violet in light mode), like most terminal themes; caret uses the gold accent.
- Custom tools run in a new terminal tab: the command (placeholders replaced by single-quote shell-escaped values) is passed to the shell as an argument, followed by an interactive login shell so output stays readable. Non-POSIX shells (fish, nu) run the command via zsh. `{repoRoot}` and `{worktree}` both resolve to the checkout root; `{file}`/`{folder}` are absolute paths in it. Missing values (e.g. `{headSHA}` before details load) abort with a message instead of running.
- Tools need the review worktree: an existing worktree is reused as is (not refreshed to the latest head); otherwise it is prepared first (visible as an activity job). In demo mode tools run in the home directory.
- File rows offer file tools, folder rows folder tools, and the terminal toolbar menu and panel header offer PR tools. Two PR-scope examples (“Run tests”, “Open in Fork”) are shown until the user edits the list. Command palette integration and background-job output for tools are deferred.
- A Fable code review (2026-11-15) found 28 issues; fixed: agent isolation (empty cwd + `--add-dir`, user settings only, no MCP, `dontAsk`), process cancellation/SIGPIPE/lossy decoding, REST query encoding, parser edge cases (phantom line, quoted paths), per-PR agent worktrees with per-repo git serialisation, PR-bound async state (diff, review), cancellable AI reviews, symlink-safe context, single main window, selection by ID, IDE launch, lazy and cached diff rendering.
- Open follow-ups from that review: pagination beyond 100 files/threads, outdated/file-level threads in a separate list, per-line draft observation in review panels, restore-stash helper after main-clone checkout, cleanup of old per-PR agent worktrees.
- Persistence is a small JSON cache in Application Support (inbox snapshot, AI review results) instead of GRDB/SQLite — enough for now, no dependency.
- 0.5.12–0.5.17 (2026-11): window layouts (automatic with a 1700/1760 pt band, wide, compact, focus, two windows), Comments tab, *Waiting on others* and reply notifications, *Ask AI* on threads, Commands panel, Markdown blocks and auto-scroll in the AI chat, AI text size, terminal font size, clickable repository / `#number` in the title, double-click on empty toolbar space, overlay scroll bars (stable column content with a mouse or Universal Control), app version in Settings. Launch argument `--ask=question` asks the AI chat for screenshots.
