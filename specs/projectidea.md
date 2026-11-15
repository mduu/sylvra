# Sylvra — Project Idea

> *Sylvra* — a coined word from Latin *silva* / English *sylvan*: forest, wooded.
> **Mood:** a quiet place for focused work.

## 1. Vision

Sylvra is a native macOS app that makes reviewing pull requests in the age of agentic coding **fast, calm, thorough — and fun again**.

AI agents now write a large share of the code that lands in pull requests. The volume of changes keeps growing, while the time a human reviewer has stays the same. The bottleneck has moved from *writing* code to *understanding and judging* it. Sylvra is built for exactly that step: it captures the essence of a change in seconds, lets AI agents do the heavy lifting, and keeps the human firmly in control of the final judgement.

Reviews should stop being an ever-growing burden. Sylvra should be a tool one **genuinely enjoys** opening every day — beautiful and practical, again and again.

Sylvra is **not a Git client**. It does not stage, commit, rebase or push. It is a highly specialized **PR review client**.

## 2. Problem

Today's review workflow is fragmented and noisy:

- PRs that need my review are often **not assigned to me directly** (team review requests, CODEOWNERS, "someone should look at this"). GitHub's UI makes them easy to miss.
- The GitHub web diff shows files alphabetically. It does not show **where in the architecture** something changed or **what kind** of change it is.
- Carefully structured PRs (one logical step per commit) lose their structure in a flat diff.
- Opening a PR locally in the IDE takes several manual steps (fetch, checkout, stash, open project, find file).
- Running an AI review means switching to the terminal, writing a prompt, and then manually mapping findings back to code lines.
- AI findings and human comments live in different places. Turning a good AI finding into a PR comment with a code suggestion is copy-paste work.
- Large PRs are tiring. There is no good way to see "what is new since my last review" or to skip the noise (generated code, lockfiles, snapshots).
- Reviews feel like a chore rather than a craft.

## 3. Target user

The primary user is **a senior engineer reviewing their team's PRs** on GitHub, who:

- reviews several PRs per day, many of them partially or fully written by AI agents,
- uses JetBrains Rider, Visual Studio Code and Xcode (and sometimes opens VS Code projects in Rider),
- has Claude Code installed and authenticated locally,
- cares about a calm, keyboard-friendly, high-quality tool,
- may prefer to talk to the AI in their native language (e.g. German) while the repository stays in English.

The first goal is to optimize **one person's review process within a team**. Team-wide features come later, if at all.

## 4. Product principles

1. **Reviews are fun again.** Every feature is measured against: does it reduce the burden and make reviewing more enjoyable?
2. **Essence first.** Before any line of code, show *what* changed, *where*, and *how risky* it is.
3. **Calm by default, wow where it matters.** A tidy, quiet interface. The diff view is the showpiece and should create a real *wow* effect. Micro-animations explain, they never distract.
4. **Human in control.** The AI suggests, the reviewer decides. Nothing is posted to GitHub without an explicit action.
5. **Local first.** Uses the local Git installation and locally installed AI agents. No Sylvra backend, no telemetry by default.
6. **One click.** The frequent actions — open in IDE, run AI review, jump to finding, comment, open on GitHub — are one click or one shortcut away.
7. **Don't touch my working copy unasked.** PR checkouts happen in Sylvra-managed Git worktrees by default. Using the main clone is an explicit choice.
8. **Native and Apple-like.** Swift, SwiftUI, AppKit where needed. Follow Apple's Human Interface Guidelines; deviate only with a clearly documented *why*.
9. **Open for more.** Claude Code and three IDEs first, but agents and IDEs are pluggable providers.

## 5. Core features (MVP)

### 5.1 PR inbox (sidebar)
- Lists open PRs across configured repositories and organizations.
- Smart sections: *Review requested from me*, *Review requested from my teams*, *Watched repositories*, *Involved / mentioned*, *My PRs*, *Recently closed*.
- Focus on PRs **not directly assigned** to me: team requests, CODEOWNERS matches, configurable repo/path watch lists.
- Status at a glance: author avatar, CI state, review state, merge state, size, age, draft, conflicts, "updated since my last review".

### 5.2 Complete PR information
Everything GitHub shows about a PR, in a calmer layout:
- **Overview**: title, rendered description, author (with avatar), refs (`head → base`, fork origin), labels, assignees, requested reviewers and their review states, milestone, linked issues, created/updated timestamps.
- **Merge status**: mergeable / conflicts / behind base / blocked (required reviews, required checks, branch protection) / merge queue state.
- **Checks**: all check runs and statuses with result and duration. One click opens a failing build in the browser on GitHub.
- **Commits**: list with short SHA (one-click copy of short and full SHA), message (subject + body), author and committer (with avatars), date, signature verification, per-commit CI status.
- **Conversation**: PR comments, reviews and timeline events.
- **Open on GitHub** everywhere: PR, file, line, commit, check run, comment.

### 5.3 Change essence
- **Change map**: namespaces/folders as a structural overview (tree + treemap) with additions/deletions per folder.
- **AI summary**: a short description of intent, scope and risk areas.
- **Patterns**: *"What patterns are used or missed?"* — the AI names the architectural and code patterns the change uses, follows or violates (see 5.7).
- Classification of files: source, tests, config, generated, lockfiles, assets, docs. Noise is collapsed by default.

### 5.4 State-of-the-art diff (the *wow* view)
- Side-by-side and inline (unified) modes.
- **Focused mode**: only changed hunks with configurable context lines (e.g. 3 / 5 / 10).
- **Full-file mode**: complete files with changes highlighted.
- Syntax highlighting, intra-line (word-level) diffs, moved-code detection, whitespace toggle.
- **Commit-by-commit review**: step through a structured PR commit by commit (or any commit range), with per-commit viewed state.
- "Changes since my last review" diff.
- Mark files as viewed (synced with GitHub's "Viewed" state).

### 5.5 Open in IDE
- One click opens the PR locally in the chosen IDE: **JetBrains Rider**, **Visual Studio Code**, **Xcode** — or any app via the **macOS default app** for the project.
- **IDE choice**: default IDE per repository, quick switch per click (e.g. open a VS Code project in Rider).
- **Checkout target**: a Sylvra-managed **worktree** (default) *or* the **main local clone** (explicit choice, e.g. because some projects cannot run from a worktree).
- **Rider hygiene**: worktrees should not pile up as broken entries in Rider's recent projects (stable review worktree per repo and/or cleanup of stale entries).

### 5.6 AI review
- One-click **"Run AI Review"** using a local AI agent — **Claude Code** first; Codex, Gemini and others later.
- Selectable **model** (e.g. Opus, Fable) and **effort**; defaults in settings, **override per PR in a few clicks**.
- **Multiple models at once** (optional): run the same review with several models and see where they agree.
- **Parallel agents**: large PRs are split into shards (by folder/namespace) and reviewed concurrently, then merged and de-duplicated. Maximum concurrency is configurable.
- **Repository AI setup as context**: `AGENTS.md`, `CLAUDE.md`, `README.md` and folders referenced from them (typically `specs/`, `docs/`, `ai/`).
- **History awareness**: relate the change to earlier commits and merged PRs that touched the same areas.
- Findings are structured (file, line range, severity, category, rationale, optional code suggestion) and **linked**: one click jumps to the exact location inline in the diff.
- Findings are highlighted in the diff **Xcode-style**: soft gradient backgrounds and/or gradient borders.

### 5.7 Pattern analysis
- The AI lists the patterns the change touches (e.g. repository pattern, MVVM, error handling conventions, naming conventions, documented architecture rules from `specs/`).
- For each: **followed**, **violated** or **newly introduced**, with linked evidence in the diff.
- Answers the question *"What patterns are used or missed?"* at a glance.

### 5.8 AI chat
- A chat panel with an agent that has the PR context (diff, description, commits, findings, worktree).
- Ask questions like "Why was this lock removed?" or "Is this migration backwards compatible?".
- Chat answers reference code locations, which are clickable.
- **Agent language** is configurable (e.g. German or English) — independent of the language of comments posted to GitHub.

### 5.9 Review comments (GitHub parity)
- Inline PR comments, including **GitHub code suggestions** (```` ```suggestion ```` blocks).
- Turn an AI finding into a draft comment with one click, edit it, then add it to the pending review.
- Reply to threads and review questions, resolve / unresolve threads, edit / delete own comments, reactions.
- Submit the review as *Comment*, *Approve* or *Request changes*.

### 5.10 Terminal and custom tools
- **Terminal panel** (toggleable) with one or more terminal sessions as tabs, starting in the PR worktree or clone.
- **Open in external terminal** with one click.
- **Custom tools**: user-defined commands, run from the context menu on files, folders or the whole PR (e.g. "Run tests for this project", "Open in Fork", "Format file").

### 5.11 Background work and notifications
- A visible **activity indicator** whenever Sylvra works in the background (AI review, fetch, worktree preparation).
- A **macOS notification** when long-running work finishes while the app is not focused (configurable per job type).

## 6. Smart features (post-MVP ideas)

- **Review order suggestion**: the agent proposes the best reading order (entry points → core logic → tests → config).
- **Intent check**: compare the PR against the linked issue / description — does the implementation do what was asked? Anything extra?
- **AI-authored detection**: highlight PRs or commits likely produced by an agent (co-author trailers, bot accounts) and adjust review depth.
- **Risk score**: combine size, touched areas (auth, persistence, concurrency, public API), test coverage delta and CI state.
- **Test gap hints**: changed logic without corresponding test changes.
- **Re-review delta**: after new pushes, only show what changed since the last submitted review, including how earlier comments were addressed.
- **Review checklists** per repository.
- **Personal review stats**: time to first review, review load per day — for myself, not for surveillance.
- **Notifications**: new review requests and updates to PRs I reviewed.
- **Comment writing help** (built): comments stay **factual, short and neutral**. In the composer: EN/DE per comment (remembered per repository; switching only translates), *Rephrase factually* (at most two sentences, observation → effect → suggestion, no judgment or absolutes), *Shorter and crisper*, *Undo rewrite*. A local, instant **tone check** flags dismissive, absolute, loaded or shouted wording and offers *Rephrase*. Suggestion blocks are never changed; nothing is posted without the reviewer's action.

## 7. Non-goals

- No Git client features (staging, committing, branching UI, merge conflict resolution). Checking out a PR head for local review is the only Git write operation.
- No support for GitLab, Bitbucket or Azure DevOps (for now — GitHub only, including GitHub Enterprise later).
- No hosted backend, no account system.
- No replacement for the IDE. Deep code navigation happens in Rider / VS Code / Xcode.
- No Windows / Linux / iOS versions.

## 8. Success criteria

- Time from opening a PR to understanding its essence: **< 30 seconds**.
- Starting an AI review: **1 click**; jumping to a finding: **1 click**; opening a failing build on GitHub: **1 click**.
- Opening a PR in the IDE: **1 click**, in the right IDE, without disturbing the main working copy (unless chosen).
- The reviewer catches more relevant issues per review while spending less time on noise.
- The app feels calm and beautiful: a place one *wants* to review in — reviews are fun again.

## 9. Assumptions and constraints

- GitHub only (github.com first).
- macOS only, latest major macOS version as the minimum target.
- Git and at least one supported AI agent (Claude Code first) are installed locally and authenticated by the user; Sylvra never handles AI provider credentials.
- GitHub authentication via the GitHub CLI (`gh`) token or an OAuth device flow; tokens are stored in the Keychain.
- An Apple Developer account is available for signing, notarization and App Store / TestFlight distribution.
- Distribution as notarized DMG (Sparkle updates), optionally via an own Homebrew tap (`brew install --cask sylvra`); App Store only if the App Sandbox allows it (see `architecture.md` §14.3).
- Accessibility is welcome but not a priority now: when it conflicts with functionality or ease of use, functionality wins (see `ux.md`).
