# Sylvra — Architecture

Status: **draft / target architecture**. The code base does not exist yet; this document describes the intended design and is updated as decisions are made.

## 1. Overview

Sylvra is a native macOS app (Swift, SwiftUI, AppKit where needed). It talks to external systems only from the user's machine:

```mermaid
flowchart TB
    subgraph App["Sylvra.app"]
        Screens["Screens (containers)"] --> Views["Views (pure, presentational)"]
        Screens --> Features
        subgraph Features["Feature slices"]
            Inbox
            PullRequest
            Diff
            Review
            AIReview
            OpenInIDE
            Terminal
            CustomTools
        end
        Features --> Platform["Platform (shared kernel)"]
    end

    Platform -- "HTTPS (GraphQL / REST)" --> GitHub[("GitHub API")]
    Platform -- Process --> Git["git CLI + worktrees"]
    AIReview -- "Process (AgentProvider)" --> Agents["Claude Code · later Codex, Gemini"]
    OpenInIDE -- "Launch Services / CLI (IDEProvider)" --> IDEs["Rider · VS Code · Xcode · default app"]
    Terminal -- PTY --> Shell["zsh / user shell"]
    Agents -. "reads code in worktree" .-> Git
```

There is **no Sylvra backend**. All data stays on the user's machine, except what is explicitly posted to GitHub and the code an AI agent sends to its provider when the user starts a review or chat.

## 2. Platform and tooling

| Topic | Decision |
|---|---|
| Language | Swift 6, strict concurrency checking enabled |
| UI | SwiftUI first; AppKit (`NSViewRepresentable`) for the diff text rendering, terminal and other performance-critical views |
| Minimum OS | Latest major macOS release (current system materials, e.g. Liquid Glass) |
| State | Observation framework (`@Observable`), no Combine in new code |
| Concurrency | `async/await`, actors for shared mutable state, structured concurrency for parallel agents |
| Project layout | Xcode app target (composition root) + local Swift package `SylvraKit` with one target per feature slice |
| Tests | Swift Testing (`import Testing`); XCTest only for UI tests |
| Lint / format | SwiftLint (lint rules) + `swift format` (formatting), see §14 |
| Dependencies | Keep minimal. Candidates: SwiftTreeSitter (syntax highlighting), GRDB (SQLite cache), SwiftTerm (terminal panel) (updates are built in, see §14.3) |

## 3. Code organization: feature slices

The code is organized **by topic (feature)**, inspired by — but not a strict 1:1 implementation of — *vertical slice architecture*:

- Each **feature slice** owns everything it needs for one topic: screens and views, view models, use cases, feature-specific models and adapters.
- Code shared by several slices lives in a small **shared kernel** (`SylvraCore`, `Platform`, `DesignSystem`). Only truly shared things go there — when in doubt, keep it in the slice.
- Pragmatic deviations from strict vertical slices are allowed: e.g. the GitHub client and the git runner are shared infrastructure in `Platform`, not duplicated per slice.

```
sylvra/
├── Sylvra.xcodeproj
├── App/                        # App target: @main, scenes, windows, menus, composition root (DI), routing
├── Packages/SylvraKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── SylvraCore/         # Domain models + protocols shared across slices (no UI, no I/O)
│   │   ├── Platform/           # Shared infrastructure: GitHubClient, GitRunner, ProcessRunner, Keychain,
│   │   │                       # Persistence (SQLite), Logging, Notifications
│   │   ├── DesignSystem/       # Color tokens (from the app icon), typography, materials, animations,
│   │   │                       # AI highlight styles, reusable components (Avatar + AvatarCache, Badge, CopyableSHA…)
│   │   ├── FeatureInbox/       # PR inbox: sections, filters, polling
│   │   ├── FeaturePullRequest/ # PR details: overview, description, commits, checks, merge status, conversation
│   │   ├── FeatureDiff/        # Diff engine (parse, intra-line, moved code) + diff screens and rendering
│   │   ├── FeatureReview/      # Comments, threads, suggestions, pending review, submit
│   │   ├── FeatureAIReview/    # Agent providers, review runs, sharding, findings, patterns, chat
│   │   ├── FeatureOpenInIDE/   # IDE providers, checkout target (worktree / main clone), Rider hygiene
│   │   ├── FeatureTerminal/    # Terminal panel (tabs, PTY sessions), external terminal launcher
│   │   ├── FeatureCustomTools/ # User-defined commands for files / folders / PRs
│   │   ├── FeatureActivity/    # Background jobs, activity indicator, completion notifications
│   │   ├── FeatureUpdates/     # Self-update from GitHub Releases: check, download, verify, swap, relaunch
│   │   ├── FeatureDelivery/    # A merged pull request's way to production: stages from GitHub, following,
│   │   │                       # approving deployments (see delivery.md)
│   │   ├── FeatureFeedback/    # Feedback to the Sylvra project: form, window snapshot, issue in its repository
│   │   ├── FeatureSettings/    # Settings screens
│   │   ├── LocalReview/        # Composition shared by the app and the CLI: diff → reviewable files, local
│   │   │                       # reviews (git changes, settings, run, Markdown / JSON output), see §8.8
│   │   └── SylvraCLI/          # `sylvra` executable (thin main; shipped in Sylvra.app/Contents/Helpers)
│   └── Tests/                  # One test target per slice and shared module
├── scripts/                    # lint, format, release helpers
├── .github/workflows/          # PR validation (see §14)
├── specs/
└── AGENTS.md
```

### 3.1 Inside a slice

```
FeatureDiff/
├── Screens/      # DiffScreen — container: owns view model, loading, side effects
├── Views/        # DiffLineView, HunkHeaderView … — pure, presentational
├── ViewModels/   # DiffScreenModel (@Observable, @MainActor)
├── Domain/       # FileDiff, Hunk, DiffLine, IntraLineDiff — slice-specific models and logic
├── Services/     # Use cases, e.g. LoadDiffUseCase, ComputeMovedCode
└── Adapters/     # Slice-specific infrastructure (if any)
```

### 3.2 Dependency rules

```mermaid
flowchart BT
    Core[SylvraCore]
    Platform --> Core
    DesignSystem --> Core
    subgraph Slices["Feature slices"]
        FeatureInbox
        FeaturePullRequest
        FeatureDiff
        FeatureReview
        FeatureAIReview
        FeatureOpenInIDE
        FeatureTerminal
        FeatureCustomTools
        FeatureActivity
        FeatureUpdates
        FeatureSettings
    end
    Slices --> Core
    Slices --> Platform
    Slices --> DesignSystem
    App["App target (composition root, routing)"] --> Slices
```

- Slices **do not import each other**. Cross-slice navigation and composition happen in the `App` target (router / composition root) or via protocols defined in `SylvraCore`.
- `SylvraCore` depends on nothing. `Platform` and `DesignSystem` depend only on `SylvraCore`.

### 3.3 View layer: containers and presentational views

SwiftUI views follow the **container / presentational** pattern (also known as *smart / dumb* views):

| Suffix | Role |
|---|---|
| `*Screen` | Top-level navigation destination (e.g. `PullRequestScreen`). **Container**: owns its `*ScreenModel`, triggers loading and side effects (network, git, agents), maps state to views. |
| `*Panel`, `*Inspector`, `*Sheet` | Containers for a region of a screen (terminal panel, findings inspector, submit-review sheet). May own state and side effects. |
| `*View` | **Presentational and as pure as possible**: data in, closures out. No services, no `Task {}` with side effects, no environment lookups of services. |
| `*Row`, `*Cell`, `*Badge` | Small presentational building blocks. |
| `*ScreenModel` / `*Model` | `@Observable @MainActor` view model of a screen or panel. |

Pure views are easy to preview and test (SwiftUI previews with fixture data); all side effects stay in the containers above them.

## 4. Domain model (core)

```swift
struct RepositoryRef      { owner, name, defaultBranch, localClonePath?, preferredIDE? }
struct UserRef            { login, name?, avatarURL? }
struct PullRequest        { id, number, repo, title, body, author: UserRef, state, isDraft,
                            baseRef, headRef, headRepo, headSHA, baseSHA, labels, assignees,
                            reviewRequests, reviews, milestone?, linkedIssues,
                            mergeState: MergeState, checks: [CheckRun],
                            additions, deletions, changedFiles, createdAt, updatedAt,
                            lastViewedByMeAt? }
struct MergeState         { mergeable, isBehindBase, hasConflicts, blockedReasons, mergeQueueState? }
struct CheckRun           { name, status, conclusion, startedAt?, completedAt?, detailsURL }
struct Commit             { sha, shortSHA, subject, body, author: UserRef, committer: UserRef,
                            authoredAt, isVerified, checkState? }
struct ChangedFile        { path, previousPath?, status, additions, deletions,
                            kind: .source | .test | .config | .generated | .lockfile | .asset | .docs,
                            viewed: Bool }
struct ReviewThread       { id, path, line, side, isResolved, isOutdated, comments: [ReviewComment] }
struct ReviewFinding      { id, path, startLine, endLine, side, severity, category,
                            title, rationale, suggestion?, confidence, sources: [AgentSource] }
struct PatternFinding     { id, name, verdict: .followed | .violated | .introduced,
                            rationale, evidence: [CodeLocation] }
struct ReviewRun          { id, pr, headSHA, commitRange?, agents: [AgentSource], shards, status,
                            findings, patterns, summary, startedAt, finishedAt }
struct AgentSource        { provider, model, effort }
```

Diff-specific models (`FileDiff`, `Hunk`, `DiffLine`) live in `FeatureDiff/Domain`; only stable line identities (`CodeLocation`) are shared via `SylvraCore`.

## 5. GitHub integration (`Platform/GitHubClient`)

- **API**: GraphQL v4 for PR lists, PR details, commits, checks, review threads and review mutations; REST v3 where simpler (raw diffs, file contents).
- **Authentication**: token from the GitHub CLI (`gh auth token`) if available, otherwise OAuth device flow. Tokens are stored in the **Keychain** only.
- **Inbox queries**: search qualifiers such as `is:pr is:open review-requested:@me`, `team-review-requested:<org>/<team>`, `involves:@me`, plus configured watched repositories and path rules (CODEOWNERS-like, evaluated locally).
- **Refresh**: polling with conditional requests (`ETag`), adaptive interval (faster when active, slower in background), respecting rate limits.
- **Review parity** — everything GitHub offers for reviewing:
  - pending review with inline comments and ```` ```suggestion ```` blocks (`addPullRequestReview`, `addPullRequestReviewThread`, `submitPullRequestReview`),
  - reply to threads, resolve / unresolve (`resolveReviewThread`, `unresolveReviewThread`), edit / delete own comments, reactions,
  - mark files as viewed (`markFileAsViewed` / `unmarkFileAsViewed`).
- **Stacked pull requests**: GitHub's stack fields (`PullRequest.stack` / `stackEntry`, a preview API) are read in their own small queries, never inside the inbox or detail queries — if GitHub renames them or a GitHub Enterprise Server lacks them, only the stack goes missing. Pull requests that aren't in a GitHub stack get one derived from base and head branches (`BranchStackWalker`), so stacks made with other tools show too. Whether a layer misses commits of the one below comes from `Ref.compare` (`aheadBy`). Merging a whole stack (`merge-async`) and restacking stay on GitHub / the CLI (no Git client scope).
- **Deep links**: every entity keeps its GitHub `url` (PR, commit, check run `detailsURL`, comment) so the UI can open it in the browser with one click.
- **Avatars**: `avatarUrl` of users is loaded via the shared `AvatarCache` (`DesignSystem`, next to `AvatarView`): decoded once at 128 px, kept in memory for the session and on disk (Caches/Avatars) for a week; an avatar seen before draws in the same frame, an old one is kept when offline. Initials as fallback.
- Every write is an explicit user action. AI findings are never posted automatically.

## 6. Local Git integration (`Platform/GitRunner`)

Sylvra uses the **system `git` binary** via `Process` (wrapped in an `actor GitRunner`), not libgit2. This guarantees identical behavior to the user's setup (credentials, LFS, SSH, config).

- **Repository mapping**: each GitHub repo can be mapped to an existing local clone (auto-detected by scanning configured folders and matching `remote.origin.url`). If none exists, Sylvra can create a cache clone in `~/Library/Application Support/Sylvra/repos/`.
- **Local diffs**: full-file mode, very large PRs (GitHub truncates diffs), "changes since last review", **per-commit diffs** (`git show`, `git diff <a>..<b>`), moved-code detection.
- **History for AI context**: `git log` / `git blame` on touched paths and the merge commits / merged PRs that last changed them (see §8.3).

## 7. Diff engine (`FeatureDiff`)

- **Input**: unified diff (GitHub or local git) + optionally both full file versions.
- **Model**: `FileDiff → [Hunk] → [DiffLine]` with stable line identities (path + side + line number) used for anchoring comments and AI findings.
- **Ranges**: whole PR, since last review, single commit, commit range.
- **Intra-line diff**: token/word-level diff (Myers on tokens) for modified line pairs.
- **Presentation modes** (view-model transforms on the same model): side-by-side / inline, focused (N context lines, expandable) / full file.
- **Syntax highlighting**: tree-sitter grammars, tokenized off the main thread, cached per blob SHA.
- **Rendering**: TextKit 2 based `NSTextView` or a custom virtualized `NSView`, hosted in SwiftUI — required for smooth 120 fps scrolling of 10k+ line diffs, custom line backgrounds, gradient AI highlights, connector ribbons between panes and animated hunk expansion (see `ux.md` §6).
- **Decorations layer**: comments, AI findings, pattern evidence and selections are overlays keyed by line identity, independent of the diff text.

## 8. AI integration (`FeatureAIReview`)

### 8.1 Agent providers

Sylvra drives **locally installed AI agent CLIs** as child processes. It never calls provider APIs directly and never handles AI credentials — it uses the user's existing CLI login and settings.

```swift
protocol AgentProvider: Sendable {
    var id: AgentProviderID { get }                 // .claudeCode, later .codex, .gemini
    func detect() async -> AgentInstallation?       // binary path, version, login state
    func capabilities() async -> AgentCapabilities  // models, effort levels, structured output, resume
    func review(_ request: ReviewRequest) -> AsyncThrowingStream<ReviewEvent, Error>
    func chat(_ message: ChatMessage, session: ChatSession) -> AsyncThrowingStream<ChatEvent, Error>
}
```

- **MVP**: `ClaudeCodeProvider` (Claude Code CLI in non-interactive print mode, streaming JSON output: the final `result` line carries the answer and structured output; `rate_limit_event` lines carry the subscription's limits — `five_hour`, `seven_day`, and `seven_day_overage_included` for Fable — which feed the toolbar usage rings via `ClaudeUsageModel`).
- **Later**: `CodexProvider`, `GeminiProvider`, … behind the same protocol.
- **Capability detection** at startup (`--version`, `--help`): supported flags (model, effort, output format, structured output, session resume) are detected at runtime instead of hardcoded.
- **Working directory**: the PR worktree (or main clone), so the agent can read the full code base.
- **Permissions**: review runs use a **read-only tool set** (read, grep, glob, `git diff/log/show/blame`). No file edits, no network side effects.

### 8.2 Model selection

- Global defaults in settings: provider, model (e.g. Opus, Fable), effort.
- **Per-PR override** in a few clicks (stored per PR).
- **Multi-model review** (optional): the same request runs with several `AgentSource`s in parallel; findings are merged and marked with the models that reported them ("found by Opus + Fable").

### 8.3 Review context

A `ReviewRequest` contains:

- PR metadata (title, description, linked issues), base/head SHA, commit list, selected range (whole PR / since last review / commit),
- files in scope (shard),
- **repository AI setup**, discovered by `RepoContextDiscovery`:
  - `AGENTS.md`, `CLAUDE.md` (including `@file` imports), `README.md`,
  - folders referenced from those files — typically `specs/`, `docs/`, `ai/` — and other well-known agent instruction files,
  - Sylvra's per-repo custom review prompt;
- **history context**: recent commits and merged PRs touching the same paths, so the agent can relate the change to earlier decisions ("this reverts the fix from #812"),
- the pull request's **other files** (path and size) when it is sharded, so each agent can judge the change as a whole,
- review rules beyond correctness: **code comments** only where the intent is not evident from the code, and then as short as possible (restating or wordy comments are `style` findings); the **whole pull request** — could it be much more compact or simpler, is it too much code, is it scattered over more places than needed (`overall`); every **pattern** cites one to three evidence locations,
- selected model and effort, the **agent language** (see §8.6) and the required output schema.

### 8.4 Structured output

```json
{
  "summary": "string",
  "findings": [{
    "path": "Sources/Billing/Invoice.swift",
    "startLine": 42, "endLine": 48, "side": "RIGHT",
    "severity": "critical | major | minor | nit",
    "category": "bug | security | performance | concurrency | design | tests | style | pattern",
    "title": "string",
    "rationale": "string (markdown)",
    "suggestion": "optional replacement code for startLine..endLine",
    "confidence": 0.0
  }],
  "overall": [{
    "kind": "simpler | tooMuchCode | scattered | other",
    "title": "string",
    "rationale": "string naming the files concerned"
  }],
  "patterns": [{
    "name": "Repository pattern",
    "verdict": "followed | violated | introduced",
    "rationale": "string (markdown)",
    "evidence": [{ "path": "…", "startLine": 10, "endLine": 20, "side": "RIGHT" }]
  }],
  "history": [{ "ref": "commit SHA or PR number", "relation": "string" }]
}
```

Findings and pattern evidence are **validated** against the actual diff: paths must exist, line ranges must be inside the file (pattern evidence outside the pull request's files is dropped). Shards and models that report the same pattern add their evidence to it; `overall` points are merged when their titles share most word stems. Invalid locations are re-anchored (nearest hunk) or marked "unanchored" instead of silently dropped.

### 8.5 Parallel agents (sharding)

```mermaid
sequenceDiagram
    actor U as Reviewer
    participant S as Sylvra
    participant G as git
    participant C as Agent processes

    U->>S: Run AI Review (models, effort)
    S->>G: fetch PR head, update worktree
    S->>S: discover repo AI setup + history context
    S->>S: plan shards (folders, balanced by size)
    par Shard 1
        S->>C: review(shard 1)
        C-->>S: stream findings (JSON)
    and Shard n
        S->>C: review(shard n)
        C-->>S: stream findings (JSON)
    end
    opt Cross-cutting pass
        S->>C: review(PR summary + shard summaries + patterns)
        C-->>S: cross-cutting findings
    end
    S->>S: validate, re-anchor, de-duplicate, merge models
    S-->>U: findings and patterns inline in diff
```

1. **Shard planning**: group changed files by namespace/folder, balance by changed-line count, keep related files (source + tests) together, exclude noise.
2. **Execution**: one agent process per shard (× per model), limited by `maxParallelAgents` (setting) via a `TaskGroup` with a concurrency limiter.
3. **Cross-cutting pass** (optional): catches issues spanning shards and consolidates pattern analysis.
4. **Merge**: de-duplicate findings, order by severity, attach sources (the higher impact / likelihood wins). A finding is a duplicate when it is in the same file and either within 2 lines with similar wording (shared word stems of the title, or of title and rationale; same category on the same line) or up to 6 lines apart with the same category and clearly the same title. Deliberately cautious: merging two different problems hides one.
5. **Consolidate** (only when several models ran): one more agent call (Sonnet, low effort) gets the merged findings and whole-PR points and returns groups that describe the same problem in other words, another language or at another line. Each group becomes its most severe finding with all sources; groups across files or with invalid indices are ignored; on any failure the merged result stays. Shown as a progress row "Combining the models' findings".

Small PRs automatically use a single agent (threshold configurable).

### 8.6 Chat and language

- One chat session per PR, run in the PR worktree, resumable via the provider's session mechanism.
- Answers containing `path:line` references become clickable links into the diff.
- Answers are short by instruction: the answer first, no preamble or closing summary, usually 1–4 sentences or a few bullets; longer only when asked or truly needed.
- **Agent language** (setting, default: system language): all agent-to-user communication (summaries, rationales, chat) is requested in this language.
- **Comment language** (separate setting, default: English): used when a finding is turned into a GitHub comment, since repositories are usually English.

### 8.7 Persistence of AI results

Review runs and chat transcripts are stored locally, keyed by `(repo, pr, headSHA, range)`. After new pushes, findings from older runs are shown as **outdated**, with best-effort line re-mapping.

### 8.8 Local reviews (`sylvra` command line tool)

`sylvra review` runs the AI review of §8.1–8.5 on a local branch instead of a pull request, for the terminal and for coding agents (Claude Code through the `sylvra-review` skill).

- **Composition**: the `LocalReview` library composes `FeatureDiff` and `FeatureAIReview` (like the app target); the app uses it too, for turning diffs into `ReviewableFile`s. `SylvraCLI` is a thin `main.swift` over it.
- **What is reviewed**: `git diff <merge-base>` against the base branch (`--base`, else `origin/HEAD`, `origin/main`, `main`, `origin/master`, `master`), i.e. commits plus uncommitted changes, plus untracked files (`git ls-files --others --exclude-standard`, ≤ 512 KB, diffed with `--no-index`); `--committed` limits it to `base...HEAD`. Git runs with argument arrays, fixed `a/`/`b/` prefixes and no external diff tools; the repository is only read.
- **Reviewer hints**: `--hint "…"` (repeatable) names points the reviewers should pay particular attention to — an addition to the usual review, not a limit on it. The prompt gets a *Reviewer hints* section; problems about them come back as normal findings, and every agent answers each hint in one or two sentences (`hints` in the structured output). `ReviewMerger.hintAnswers` keeps every agent's answer per hint with its model (matched by wording, or by position when an agent rephrased but answered all), stored as `ReviewResult.hints` and shown in a *Reviewer hints* section after the summary. The app doesn't ask for hints yet.
- **Settings**: the app's default AI review settings (`aiReview.defaultSettings` in the `com.marcduerst.sylvra` defaults domain — the app isn't sandboxed), overridable with `--models`, `--effort`, `--agents`, `--language`. Several models review in parallel and are merged and consolidated exactly as in the app.
- **Agents**: the same isolation as in the app (read-only tools, user settings only, no MCP); the repository is added with `--add-dir`. Child processes don't inherit the variables of a Claude Code session the tool was started from (`CLAUDECODE`, `CLAUDE_CODE_*`), so review agents are sessions of their own.
- **Output**: Markdown on standard output (the format of *Copy for an agent*: summary, mergeability, risk, slop signs, what is worth remembering, reading order, whole-change points, findings most severe first, patterns, failed agents), or JSON (`--json`: base, branch, settings, Sylvra's `ReviewResult`). Progress goes to standard error as short lines meant to be followed by a person or an agent (`LocalReviewProgress`): `[2/4 · 1:12] ✓ Core · Opus` per agent step (finished/total agents, elapsed time; the step combining several models isn't counted), `… 2 of 4 agents done, 2 running · 1:31` every 30 seconds while agents run, and `Done in 2:41: 7 findings (2 major, 5 minor), merge risk medium, acceptable, slop some`. Exit codes: 0 reviewed, 1 failed, 2 usage.
- **Shipping**: `scripts/release.sh` builds the tool (`swift build -c release --product sylvra`), puts it in `Sylvra.app/Contents/Helpers/sylvra` (not `Contents/MacOS`: `sylvra` would replace `Sylvra` on a case-insensitive volume), signs it with the Developer ID and hardened runtime and re-signs the app keeping its entitlements. Development builds have no tool; the settings say so.
- **Claude Code skill**: AI review settings → *Use from Claude Code* installs `~/.claude/skills/sylvra-review/SKILL.md` (`ClaudeSkillInstaller`), with the tool's absolute path (no `PATH` setup). The skill runs the review in the background (it takes minutes) with the result written to a file (`-o`), so the command's output holds only the progress; where Claude Code can stream a background command's output (Monitor), it passes each finished agent on to the user as one short line, otherwise it answers from the last progress lines when asked. It presents summary, mergeability, risk and findings, and treats findings as suggestions to verify before changing code. A skill for another copy of Sylvra (moved app) shows as outdated until reinstalled. After an update of Sylvra whose skill differs from the installed one, Sylvra asks once at launch whether to update it (`ClaudeSkillUpdateModel`: *Update* / *Later*; asked again only for another skill, never when no skill is installed, nor in development builds without the tool or in demo mode).
- A future *Show in Sylvra* could open such a result in the app's diff and findings views; not built yet (the views expect a pull request).

## 9. IDE integration (`FeatureOpenInIDE`)

### 9.1 Providers

```swift
protocol IDEProvider: Sendable {
    var id: IDEProviderID { get }        // .rider, .vsCode, .xcode, .defaultApp, later .cursor, .zed, .intelliJ …
    func isInstalled() async -> Bool
    func open(project: URL, file: URL?, line: Int?) async throws
}
```

| IDE | Detection | Open project | Open file at line |
|---|---|---|---|
| JetBrains Rider | Bundle ID / Toolbox paths, `rider` launcher | launcher or `open -a` | launcher `--line <n> <file>` |
| Visual Studio Code | Bundle ID, `code` CLI | `code <dir>` | `code --goto <file>:<line>:<col>` |
| Xcode | Bundle ID, `xed` | `xed <dir / .xcodeproj / .xcworkspace>` | `xed --line <n> <file>` |
| Default app | Launch Services (`NSWorkspace`) | app registered for the project file / folder | — |

- **Per-repo default IDE** plus **quick switch** on every "Open in…" action (e.g. open a VS Code project in Rider).
- Project detection: `.sln` / `.slnx`, `.xcworkspace` / `.xcodeproj`, `.code-workspace`, folder.

### 9.2 Checkout target

| Target | When | Behavior |
|---|---|---|
| **Worktree** (default) | Normal review | `git fetch origin pull/<n>/head` → worktree at `headSHA` in `~/Library/Application Support/Sylvra/worktrees/<repo>/…`. The main working copy is untouched. |
| **Main clone** | Projects that cannot run from a worktree, or when the reviewer wants to run the app in their usual setup | Explicit choice per click or per repo. Sylvra checks for a clean working tree; if dirty, it asks (stash with a named message / cancel) — never silently. Checks out a local branch `review/pr-<n>` at the PR head and offers to switch back to the previous branch afterwards. |

```mermaid
flowchart LR
    A["Open in IDE"] --> T{"Checkout target"}
    T -- worktree --> W{"Worktree exists?"}
    W -- no --> C["fetch PR head + worktree add"]
    W -- yes --> D["update to headSHA"]
    T -- "main clone" --> M{"Working tree clean?"}
    M -- no --> Q["ask: stash (named) / cancel"]
    M -- yes --> B["fetch + switch to review/pr-n"]
    Q -- stash --> B
    C --> F["Detect project<br/>.sln · .xcworkspace · folder"]
    D --> F
    B --> F
    F --> G["Launch chosen IDE"]
    G --> H["Jump to selected file:line (optional)"]
```

#### Worktree lifecycle

- **Two kinds**: one stable worktree per repository for the IDE and the terminal (`worktrees/<owner>/<repo>`, re-pointed to the PR opened last) and one per pull request for AI agents (`agent-worktrees/<owner>/<repo>/pr-<n>`, so a running review never sees another PR's code).
- **Created / updated** on demand only: *Open in IDE*, terminal tabs and custom tools (IDE worktree), every AI review run and chat question (agent worktree). Each time `pull/<n>/head` is fetched again and the worktree is checked out detached at it; a push alone changes nothing.
- **Registry**: `worktrees.json` in the storage folder records every worktree Sylvra creates (path, purpose, PR, clone, created, last used). Worktrees found on disk without an entry (older versions) are adopted; entries whose folder is gone are dropped.
- **Cleanup** (`WorktreeCleaner`), at launch and every 15 minutes, and on demand: a worktree goes away when its PR is merged or closed on GitHub, or when it was unused for 7 days. Never removed automatically: the PR selected or under AI review, worktrees a terminal tab runs in, worktrees with changed files (`git status` not clean; removable manually after a confirmation). Removal is `git worktree remove` in the owning clone, then `git worktree prune`; only paths inside the storage folder are ever deleted.
- **Existing checkout first** (IDE and terminal tools): when the user already has the PR's head branch checked out — in their clone or one of its worktrees, outside Sylvra's storage — and it contains the PR head (up to date or ahead), Sylvra opens that directory as is: no worktree, no checkout, nothing recorded for cleanup. A branch behind the PR head (someone pushed since) gets the review worktree, so the IDE shows the code under review. AI agents always use their own per-PR worktree.
- **Owning clone** (disk space is precious): the user's local clone whenever the locator finds one (`RepositoryLocator`: the folders from Settings → Repositories — by default existing folders with typical names, any spelling, e.g. `~/Dev` or `~/dev` — up to three levels deep, then Spotlight if enabled for folders named like the repository anywhere in the home folder; only real clones whose `origin` is the repository count, nothing under `~/Library`) — the worktree shares its objects and appears in Git clients that list worktrees, e.g. Fork. Only without one does Sylvra keep a blobless cache clone in `repos/<owner>/<repo>`. A clean worktree that still belongs to the cache clone moves to the user's clone on its next use (one with changed files stays). The cleanup removes cache clones no worktree belongs to any more; they are cloned again when needed.

### 9.3 Rider hygiene

Rider keeps every opened folder in its *recent projects*; deleted worktrees remain there as broken entries. Mitigations (in order of preference):

1. **Stable review worktree per repo**: one worktree path per repository that is re-pointed to the PR under review — Rider sees a single, always-valid recent entry.
2. **Cleanup**: when Sylvra removes a worktree, it removes matching entries from Rider's recent-projects storage (in `~/Library/Application Support/JetBrains/Rider*/options/`), only while Rider is not running and with a backup.
3. **"Don't track as recent" launch option**: to be investigated — no supported Rider CLI flag is known so far.

## 10. Terminal and custom tools

- **Terminal panel** (`FeatureTerminal`): embedded terminal emulator (SwiftTerm) with PTY sessions in tabs; new sessions start in the PR worktree / clone; sessions survive switching PRs.
- **External terminal**: "Open in Terminal" with the configured app (Terminal, iTerm2, Ghostty, Warp, …).
- **Custom tools** (`FeatureCustomTools`): user-defined commands with scope (*file*, *folder*, *PR*), working directory and placeholders such as `{file}`, `{folder}`, `{repoRoot}`, `{worktree}`, `{prNumber}`, `{headSHA}`, `{baseSHA}`. Placeholders are passed as escaped arguments; output goes to a terminal tab or a background job.

## 11. Background work and notifications (`FeatureActivity`)

- Every long-running operation (AI review, chat answer, fetch, worktree preparation, custom tool) is a **job** registered with an `ActivityCenter` (`@Observable`): progress, cancellation, result.
- The UI shows an activity indicator in the toolbar and an activity popover listing running jobs.
- When a job finishes and the app is **not active**, a macOS notification (UserNotifications) is posted — configurable per job type. Clicking it opens the related PR / result.

## 12. Persistence

| Data | Storage |
|---|---|
| GitHub tokens | Keychain |
| User settings | `UserDefaults` / `@AppStorage` (non-secret) |
| PR cache, review runs, findings, patterns, chat transcripts, viewed state, last-reviewed SHA, per-PR overrides | SQLite (GRDB) in Application Support |
| Worktrees, cache clones | `~/Library/Application Support/Sylvra/` (configurable) |
| Avatars | `URLCache` (memory + disk) |
| Syntax token cache | In-memory LRU + on-disk cache keyed by blob SHA |

## 13. Security and privacy

- No telemetry by default. No third-party analytics.
- Tokens only in Keychain; never logged.
- Code is only sent to an AI provider via the user's own agent CLI, and only when an AI review or chat is explicitly started.
- AI agents run with read-only tools. Reviews and chat use no MCP servers. Only the delivery check (see `delivery.md` §7) sees the user's own MCP servers, and there every tool call needs the user's own permission rules.
- All `Process` invocations use argument arrays (no shell string interpolation) to avoid injection via branch names, paths or PR titles. Custom tools are the only place where user-configured shell commands run.

## 14. Quality: linting and CI

### 14.1 Local

- **SwiftLint** (`.swiftlint.yml`) for lint rules, **`swift format`** (`.swift-format`) for formatting.
- `scripts/lint.sh`, `scripts/format.sh` and `scripts/test.sh` (package tests + app build); optional Git pre-commit hook.
- SwiftLint also runs as an Xcode build phase (warnings in the IDE).

### 14.2 GitHub Actions (PR validation)

The repository is public (MIT), so standard GitHub-hosted runners are free. The workflow is still kept lean — fast feedback, low noise, no waste of shared resources:

| Rule | Implementation |
|---|---|
| Run only where needed | Trigger on `pull_request` to `main` only (no duplicate `push` runs); `paths-ignore` for `**/*.md`, `specs/**`, `assets/**`. |
| Fast first | `lint` job on `ubuntu-latest` (SwiftLint + `swift format lint`); the slower macOS job runs only if lint passes. |
| Short macOS job | `build-and-test` on `macos-latest`: `xcodebuild test`, `timeout-minutes: 20`. |
| No waste | `concurrency` with `cancel-in-progress: true`; no artifact uploads; small SPM cache keyed on `Package.resolved`. |
| Updates | Dependabot for GitHub Actions and SPM, monthly. |

There is **no CD on GitHub**. Releases are built and uploaded locally.

### 14.3 Release (local)

Like SolarLens, releases are done from the developer machine, driven by Claude Code commands (e.g. `/deploy-testflight`, `/deploy-release`):

1. Bump build number in the Xcode project.
2. `xcodebuild archive` into Xcode's dated archive folder (so it shows up in Organizer).
3. `xcodebuild -exportArchive` with a checked-in `ExportOptions-*.plist`.
4. Tag and GitHub release with generated "What's New" notes.

**Distribution channel and sandboxing** — important constraint: the Mac App Store **and TestFlight for macOS require the App Sandbox**. Sylvra spawns `git`, AI agent CLIs, IDE launchers and terminal shells, which the sandbox largely forbids. Therefore:

- **Primary channel**: Developer ID signed + notarized build (`ExportOptions-developer-id.plist`, `notarytool`), distributed as DMG; the app updates itself from the GitHub Releases (see *Self-update* below). The DMG opens a styled installer window (`scripts/dmg/`: violet background rendered from the app icon with a golden vein arrow to *Applications* (one fine glowing line like the veins in the icon, slim open arrowhead), Sylvra's icon as volume icon), laid out with `dmgbuild` (pinned, installed into a venv under `.build`) so no Finder automation is needed. `scripts/publish.sh` tags `v<version>` and publishes the notarized DMG as a GitHub Release with the commits since the previous release as notes (only when run explicitly).
- **Homebrew** (option): `brew install --cask sylvra` via an own tap (`mduu/homebrew-tap`, cask `sylvra`). Builds on the notarized DMG; the cask declares `auto_updates true` because the app updates itself. The release script bumps `version` and `sha256` in the cask. The official `homebrew/cask` repository is only an option once Sylvra is public and popular enough to meet its notability rules.
  - DMGs are published as **GitHub Releases** of the public `mduu/sylvra` repository.
- **Self-update** (`FeatureUpdates`, no third-party dependency instead of Sparkle): `GitHubReleaseFetcher` asks `api.github.com/repos/mduu/sylvra/releases/latest` without a token (finished releases with a `.dmg` asset; tag `v<version>` compared part by part with `CFBundleShortVersionString`; notes = the *Changes since …* section written by `scripts/publish.sh`). `SystemUpdateInstaller` downloads the DMG with `URLSession`, then — all tools with argument arrays — checks the DMG (`codesign --verify --deep --strict`, `spctl --assess --type open --context context:primary-signature`), mounts it read-only (`hdiutil attach -nobrowse -readonly`), checks the app (`codesign`, `spctl --type execute`, `TeamIdentifier` must be Sylvra's team `UYT5K989XD`), copies it with `ditto` next to the running app (same volume) and detaches the image. A constant `/bin/sh` script (arguments: pid, staged app, target) waits for Sylvra to quit, swaps the bundles (the old one is restored if the move fails) and opens the new one. Only when the app lives in a writable `Applications` folder; otherwise the DMG is opened in the Finder. Release notes, URLs and versions never become part of a command string. Tests use fake fetchers, installers and process runners; the swap script runs on temporary folders; an opt-in test (`SYLVRA_E2E_DMG`) runs the real checks on a real DMG.
- **App Store / TestFlight**: only if a sandbox-compatible design is found (see open questions). Sandbox-incompatible features would have to be disabled in that build.

## 15. Performance targets

- Inbox visible from cache in < 300 ms after launch; refreshed in background.
- PR essence (change map + file list) in < 1 s for typical PRs.
- Diff view: 120 fps scrolling and animations on ProMotion displays for files with 10k+ lines.
- Main thread never blocks on I/O, git, agent or terminal processes.

## 16. Open questions

- GitHub App vs. OAuth App for the device flow.
- Exact agent CLI flags per provider/version — resolved via runtime capability detection.
- Rider: is there a supported way to open a project without adding it to recent projects?
- App Sandbox feasibility (security-scoped bookmarks for clones, helper tools) — decides whether a Mac App Store / TestFlight build is possible.
- GitHub Enterprise Server support timing.
