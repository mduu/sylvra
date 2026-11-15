# AGENTS.md

Guidelines for AI coding agents (Claude Code, Codex, Copilot, …) working on this repository.

## Project

**Sylvra** is a native macOS PR review client for GitHub, written in Swift and SwiftUI. It is *not* a Git client. Read these before making non-trivial changes:

- `specs/projectidea.md` — vision, scope, non-goals
- `specs/architecture.md` — feature slices, integrations, data model, CI and release
- `specs/ux.md` — layout, interactions, color system, motion

If a change contradicts the specs, point it out and update the spec in the same change (or ask first if it is a product decision).

## Language

- Everything in the repository is **English**: code, comments, commit messages, docs, UI strings (localizable via String Catalogs).

## Tech stack

- Swift 6 with strict concurrency checking; no warnings in new code.
- SwiftUI first; AppKit via `NSViewRepresentable` only where needed (diff rendering, terminal, performance-critical text).
- Observation (`@Observable`), `async/await`, actors. No Combine in new code.
- Swift Testing (`import Testing`) for unit tests.
- Minimal third-party dependencies. Do not add a dependency without stating why in the PR description.

## Code organization: feature slices

Code is organized **by topic**, inspired by vertical slice architecture (not a strict 1:1 implementation). See `specs/architecture.md` §3.

```
App/                          App target: @main, scenes, composition root, routing
Packages/SylvraKit/Sources/
  SylvraCore/                 Shared domain models and protocols (no UI, no I/O)
  Platform/                   Shared infrastructure: GitHubClient, GitRunner, ProcessRunner, Keychain, Persistence …
  DesignSystem/               Color tokens, typography, animations, AI highlight styles, shared components
  Feature<Name>/              One slice per topic: Inbox, PullRequest, Diff, Review, AIReview,
                              OpenInIDE, Terminal, CustomTools, Activity, Settings
    Screens/ Views/ ViewModels/ Domain/ Services/ Adapters/
```

Rules:
- Feature slices **never import each other**. Compose them in the `App` target or via protocols in `SylvraCore`.
- Put code into a shared module only if at least two slices really need it. When in doubt, keep it in the slice.
- `SylvraCore` depends on nothing; `Platform` and `DesignSystem` depend only on `SylvraCore`.

## SwiftUI conventions

- **Container / presentational** split:
  - `*Screen` — top-level destination; owns its `*ScreenModel`, loading and side effects.
  - `*Panel`, `*Inspector`, `*Sheet` — containers for screen regions; may own state and side effects.
  - `*View`, `*Row`, `*Badge` — **pure** presentational views: data in, closures out. No services, no side-effecting `Task {}`, no service lookups from the environment.
- `*ScreenModel` / `*Model` are `@Observable @MainActor`.
- Every presentational view has a SwiftUI preview with fixture data.
- Colors, fonts, spacing and animations come from `DesignSystem` — no hardcoded colors.
- Follow Apple's Human Interface Guidelines. Any deviation must be listed with its reason in `specs/ux.md` §2.
- Animations must help understanding, be short and interruptible, and respect Reduce Motion.
- Support Auto / Light / Dark appearance.
- Accessibility: take the cheap wins (labels, keyboard navigation), but functionality and ease of use take priority.

## Build, lint and test

```bash
# Build the app
xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -destination 'platform=macOS' build

# Run all tests
xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -destination 'platform=macOS' test

# Package tests only (faster)
swift test --package-path Packages/SylvraKit

# Lint and format
scripts/lint.sh        # SwiftLint + swift format lint
scripts/format.sh      # swift format (in place)
```

Run lint and the relevant tests before reporting a task as done. If you cannot run them, say so.

## Coding conventions

- Follow the Swift API Design Guidelines. Prefer value types; use `final class` only when reference semantics are needed.
- No force unwraps (`!`) or `try!` outside tests.
- All I/O (network, git, agent processes, terminal, disk) runs off the main actor.
- Spawn processes with argument arrays — never build shell command strings from user or GitHub data (branch names, paths, titles). User-configured custom tools are the only exception.
- AI agents and IDEs are accessed only through the `AgentProvider` / `IDEProvider` protocols — no provider-specific code outside its adapter.
- Use `Logger` (OSLog) with a subsystem/category; never log tokens or full code contents.
- Public types and non-obvious logic get concise doc comments. No comments that restate the code.

## Product rules (must not be violated)

1. **Don't touch the user's working copy unasked.** PR checkouts happen in Sylvra-managed worktrees by default. The main clone is only used after an explicit user choice; a dirty working tree is never stashed or changed silently.
2. **Never post to GitHub without an explicit user action.** AI findings are suggestions, not comments.
3. **AI review agents run read-only.** No file edits, no pushes, no network side effects.
4. **Secrets only in the Keychain.** No tokens in `UserDefaults`, files or logs.
5. **No Git client scope creep.** No staging, committing, branching or merging UI.
6. **AI content is always visually marked** with the AI accent style.
7. **Long-running work is visible** (activity indicator) and cancellable.

## Testing guidelines

- Unit-test parsers and transforms thoroughly (`FeatureDiff` domain, finding validation, shard planning, file classification, repo context discovery) using fixture data in `Tests/Fixtures`.
- Abstract `Process`, PTY and networking behind protocols so services can be tested with fakes. Tests must not call the real GitHub API or real AI agents.
- Add a regression test with every bug fix.

## CI

- PR validation runs on GitHub Actions (`.github/workflows/`). Keep it lean: no new workflows, triggers, matrix builds or artifact uploads without a clear reason.
- Releases (TestFlight / App Store / Developer ID) are built locally, not on CI.

## Git workflow

- Small, focused commits with imperative messages (`Add intra-line diff for modified line pairs`).
- Do not commit or push unless asked.
- Do not commit secrets, `.DS_Store`, `xcuserdata` or build products.
