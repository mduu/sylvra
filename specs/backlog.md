# Sylvra — Backlog

Ideas that are agreed but not scheduled yet. Roadmap and finished work live in [`roadmap.md`](roadmap.md).

## macOS integration

Make "what is waiting for my review" reachable without opening Sylvra (idea from Pulldog).

- **Spotlight**: index open PRs of the inbox (`CSSearchableIndex`): title, repo, number, author. Opening a result selects the PR in Sylvra. Remove items when PRs close.
- **Shortcuts / App Intents**: "PRs waiting for my review" (returns a list), "Open PR in Sylvra", "Run AI review on PR". Intents also feed Spotlight and Siri suggestions.
- **Widgets** (WidgetKit): count and list of PRs requested from me, failing checks on my PRs; deep links into Sylvra. Data from the inbox cache, refreshed by the app (no extra GitHub polling from the widget).
- **Menu bar extra** (optional): badge with review requests and a quick list.
- Constraints: read-only, no GitHub token in the widget/extension (shared app-group cache only), respects notification settings.

## Later

- Very large PRs that GitHub won't return as one diff: build the diff from the local worktree.
- Re-run failed checks from the Checks tab.
- Go-to-definition via language servers, only for trusted repositories.
