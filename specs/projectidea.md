# Sylvra — Project Idea

> *Sylvra* — a coined word from Latin *silva* / English *sylvan*: forest, wooded.
> **Mood:** a quiet place for focused work.

## 1. Vision

Sylvra is a native macOS app that makes reviewing pull requests in the age of agentic coding **fast, calm and thorough**.

AI agents now write a large share of the code that lands in pull requests. The volume of changes is growing, while the time a human reviewer has stays the same. The bottleneck has moved from *writing* code to *understanding and judging* it. Sylvra is built for exactly that step: it captures the essence of a change in seconds, lets an AI agent do the heavy lifting, and keeps the human firmly in control of the final judgement.

Sylvra is **not a Git client**. It does not stage, commit, rebase or push. It is a highly specialized **PR review client**.

## 2. Problem

Today's review workflow is fragmented and noisy:

- PRs that need my review are often **not assigned to me directly** (team review requests, CODEOWNERS, "someone should look at this"). GitHub's UI makes them easy to miss.
- The GitHub web diff shows files alphabetically. It does not show **where in the architecture** something changed or **what kind** of change it is.
- Opening a PR locally in the IDE takes several manual steps (fetch, checkout, stash, open project, find file).
- Running an AI review means switching to the terminal, writing a prompt, and then manually mapping findings back to code lines.
- AI findings and human comments live in different places. Turning a good AI finding into a PR comment with a code suggestion is copy-paste work.
- Large PRs are tiring. There is no good way to see "what is new since my last review" or to skip the noise (generated code, lockfiles, snapshots).

## 3. Target user

The primary user is **a senior engineer reviewing their team's PRs** on GitHub, who:

- reviews several PRs per day, many of them partially or fully written by AI agents,
- uses JetBrains Rider, Visual Studio Code and Xcode,
- has Claude Code installed and authenticated locally,
- cares about a calm, keyboard-friendly, high-quality tool.

The first goal is to optimize **one person's review process within a team**. Team-wide features come later, if at all.

## 4. Product principles

1. **Essence first.** Before any line of code, show *what* changed, *where*, and *how risky* it is.
2. **Calm by default.** A tidy, quiet interface. Visualizations are state of the art but never loud. No badges for the sake of badges.
3. **Human in control.** The AI suggests, the reviewer decides. Nothing is posted to GitHub without an explicit action.
4. **Local first.** Uses the local Git installation and the locally installed Claude Code. No Sylvra backend, no telemetry by default.
5. **One click.** The frequent actions — open in IDE, run AI review, jump to finding, comment — are one click or one shortcut away.
6. **Never touch my working copy.** PR checkouts happen in isolated Git worktrees managed by Sylvra.
7. **Native.** Swift, SwiftUI, AppKit where needed. Fast, accessible, respects macOS conventions.

## 5. Core features (MVP)

### 5.1 PR inbox (sidebar)
- Lists open PRs across configured repositories and organizations.
- Smart sections: *Review requested from me*, *Review requested from my teams*, *Watched repositories*, *Involved / mentioned*, *My PRs*, *Recently closed*.
- Focus on PRs **not directly assigned** to me: team requests, CODEOWNERS matches, configurable repo/path watch lists.
- Status at a glance: CI state, review state, size, age, draft, conflicts, "updated since my last review".

### 5.2 Change essence
- **Change map**: namespaces/folders as a structural overview (tree + treemap) with additions/deletions per folder.
- **AI summary**: a short description of intent, scope and risk areas.
- Classification of files: source, tests, config, generated, lockfiles, assets, docs. Noise is collapsed by default.

### 5.3 State-of-the-art diff
- Side-by-side and inline (unified) modes.
- **Focused mode**: only changed hunks with configurable context lines (e.g. 3 / 5 / 10).
- **Full-file mode**: complete files with changes highlighted.
- Syntax highlighting, intra-line (word-level) diffs, moved-code detection, whitespace toggle.
- "Changes since my last review" diff.
- Mark files as viewed (synced with GitHub's "Viewed" state).

### 5.4 Open in IDE
- One click opens the PR locally in **JetBrains Rider**, **Visual Studio Code** or **Xcode**.
- Sylvra prepares a worktree for the PR head and opens the project (and optionally the current file at the current line).

### 5.5 AI review with Claude Code
- One-click **"Run AI Review"** using the locally installed Claude Code CLI.
- Selectable **model** and **effort**.
- **Parallel agents**: large PRs are split into shards (by folder/namespace) and reviewed by multiple agents concurrently, then merged and de-duplicated. Maximum concurrency is configurable.
- Findings are structured (file, line range, severity, category, rationale, optional code suggestion) and **linked**: one click jumps to the exact location inline in the diff.
- Findings are highlighted in the diff **Xcode-style**: soft gradient backgrounds and/or gradient borders.
- Custom review guidelines per repository (e.g. reuse the repo's `AGENTS.md`, `CLAUDE.md` or a dedicated review prompt).

### 5.6 AI chat
- A chat panel with an agent that has the PR context (diff, description, findings, worktree).
- Ask questions like "Why was this lock removed?" or "Is this migration backwards compatible?".
- Chat answers can reference code locations, which are clickable.

### 5.7 Review comments
- Create inline PR comments directly in Sylvra, including **GitHub code suggestions** (```` ```suggestion ```` blocks).
- Turn an AI finding into a draft comment with one click, edit it, then add it to the pending review.
- Submit the review as *Comment*, *Approve* or *Request changes*.
- Reply to and resolve existing threads.

## 6. Smart features (post-MVP ideas)

- **Review order suggestion**: the agent proposes the best reading order (entry points → core logic → tests → config).
- **Intent check**: compare the PR against the linked issue / description — does the implementation do what was asked? Anything extra?
- **AI-authored detection**: highlight PRs or commits likely produced by an agent (co-author trailers, bot accounts) and adjust review depth.
- **Risk score**: combine size, touched areas (auth, persistence, concurrency, public API), test coverage delta and CI state.
- **Test gap hints**: changed logic without corresponding test changes.
- **Re-review delta**: after new pushes, only show what changed since the last submitted review, including how earlier comments were addressed.
- **Review checklists** per repository.
- **Personal review stats**: time to first review, review load per day — for myself, not for surveillance.
- **Notifications**: native macOS notifications for new review requests and updates to PRs I reviewed.
- **Comment tone helper**: rephrase a comment to be clear and kind.

## 7. Non-goals

- No Git client features (staging, committing, branching UI, merge conflict resolution).
- No support for GitLab, Bitbucket or Azure DevOps (for now — GitHub only, including GitHub Enterprise later).
- No hosted backend, no account system.
- No replacement for the IDE. Deep code navigation happens in Rider / VS Code / Xcode.
- No Windows / Linux / iOS versions.

## 8. Success criteria

- Time from opening a PR to understanding its essence: **< 30 seconds**.
- Starting an AI review: **1 click**; jumping to a finding: **1 click**.
- Opening a PR in the IDE: **1 click**, without disturbing the main working copy.
- The reviewer catches more relevant issues per review while spending less time on noise.
- The app feels calm: a place one *wants* to review in.

## 9. Assumptions and constraints

- GitHub only (github.com first).
- macOS only, latest major macOS version as the minimum target.
- Git and Claude Code are installed locally. Claude Code is authenticated by the user; Sylvra never handles Anthropic credentials.
- GitHub authentication via the GitHub CLI (`gh`) token or an OAuth device flow; tokens are stored in the Keychain.
