# AGENTS.md

Guidelines for AI coding agents (Claude Code, Codex, Copilot, …) working on this repository.

## Project

**Sylvra** is a native macOS PR review client for GitHub, written in Swift and SwiftUI. It is *not* a Git client. Read these before making non-trivial changes:

- `specs/projectidea.md` — vision, scope, non-goals
- `specs/architecture.md` — modules, integrations, data model
- `specs/ux.md` — layout, interactions, visual language

If a change contradicts the specs, point it out and update the spec in the same change (or ask first if it is a product decision).

## Language

- Everything in the repository is **English**: code, comments, commit messages, docs, UI strings (localizable via String Catalogs).

## Tech stack

- Swift 6 with strict concurrency checking; no warnings in new code.
- SwiftUI first; AppKit via `NSViewRepresentable` only where needed (diff rendering, performance-critical text).
- Observation (`@Observable`), `async/await`, actors. No Combine in new code.
- Swift Testing (`import Testing`) for unit tests.
- Minimal third-party dependencies. Do not add a dependency without stating why in the PR description.

## Repository layout (planned)

```
App/                      App target (entry point, scenes, DI wiring)
Packages/SylvraKit/       Local Swift package
  Sources/SylvraCore      Domain models and protocols (no UI, no I/O)
  Sources/GitHubClient    GitHub GraphQL/REST
  Sources/LocalGit        git process wrapper, worktrees
  Sources/DiffEngine      Diff model, parsing, intra-line diff
  Sources/SyntaxHighlight tree-sitter tokenization
  Sources/ReviewAgent     Claude Code integration
  Sources/IDEBridge       Rider / VS Code / Xcode launchers
  Sources/Persistence     SQLite cache, settings, Keychain
  Sources/DesignSystem    Colors, typography, components
  Sources/Features        Feature UI modules
specs/                    Product and technical specs
```

Respect the dependency rule: `SylvraCore` depends on nothing; infrastructure modules depend only on `SylvraCore`; `Features` uses protocols, the `App` target wires concrete implementations.

## Build and test

```bash
# Build the app
xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -destination 'platform=macOS' build

# Run all tests
xcodebuild -project Sylvra.xcodeproj -scheme Sylvra -destination 'platform=macOS' test

# Package tests only (faster)
swift test --package-path Packages/SylvraKit
```

Run the relevant tests before reporting a task as done. If you cannot run them, say so.

## Coding conventions

- Follow the Swift API Design Guidelines. Prefer value types; use `final class` only when reference semantics are needed.
- No force unwraps (`!`) or `try!` outside tests.
- Keep views small; move logic into view models or services that can be unit-tested.
- All I/O (network, git, agent processes, disk) runs off the main actor.
- Spawn processes with argument arrays — never build shell command strings from user or GitHub data (branch names, paths, titles).
- Use `Logger` (OSLog) with a subsystem/category; never log tokens or full code contents.
- Public types and non-obvious logic get concise doc comments. No comments that restate the code.
- Use the design system (`DesignSystem`) for colors, fonts and AI highlight styles; no hardcoded colors in feature views.

## Product rules (must not be violated)

1. **Never modify the user's working copy.** PR checkouts happen only in Sylvra-managed Git worktrees.
2. **Never post to GitHub without an explicit user action.** AI findings are suggestions, not comments.
3. **AI review agents run read-only.** No file edits, no pushes, no network side effects.
4. **Secrets only in the Keychain.** No tokens in `UserDefaults`, files or logs.
5. **No Git client scope creep.** No staging, committing, branching or merging UI.
6. **AI content is always visually marked** with the AI accent style.

## Testing guidelines

- Unit-test parsers and transforms thoroughly (`DiffEngine`, finding validation, shard planning, file classification) using fixture diffs in `Tests/Fixtures`.
- Abstract `Process` and networking behind protocols so services can be tested with fakes. Tests must not call the real GitHub API or Claude Code.
- Add a regression test with every bug fix.

## Git workflow

- Small, focused commits with imperative messages (`Add intra-line diff for modified line pairs`).
- Do not commit or push unless asked.
- Do not commit secrets, `.DS_Store`, `xcuserdata` or build products.
