# Sylvra — Delivery: from merge to production

Status: **concept** (nothing built yet). Extends the product from "review a pull request" to "bring a change from pull request to live production". See `projectidea.md` §1 and §5.12.

## 1. Intent

After the review, the work is not done: the pull request gets comments and approvals, is merged, runs through build and deployment stages, and only then shows whether it does in production what it was meant to do. Today that means the GitHub website, the pipeline pages and a monitoring tool. Sylvra shows it in one place:

1. **Tell me** when one of my pull requests gets a comment, an approval or a change request.
2. **Merge** the pull request from Sylvra.
3. **Follow** the deployment stage by stage (build, dev, test, prod — whatever the repository has) and tell me when a stage is through or failed.
4. **Verify** each stage: did the deployment start, did it finish, does the deployed change throw errors — up to production.
5. **Act**: *Ask AI about this* on every stage and result, and an interactive Claude session in the terminal when something needs fixing.

## 2. Principles

- **Read-only, with two exceptions.** Sylvra itself only writes to GitHub on a click: *Merge* and *Approve deployment* (an environment waiting for a reviewer). Everything else is reading.
- **The user's tools and access.** Verification uses what is installed and authenticated locally (Claude Code with its MCP servers such as Datadog, `gh`, other command line tools). Sylvra stores no credentials for them and adds no access of its own: the security rules of each tool and company stay in force.
- **Fixing is the user's session.** Sylvra's own agents never change anything in an environment. A fix happens in an interactive Claude session in the terminal, started from Sylvra with the context and driven by the user.
- **Facts and judgement are kept apart.** The pipeline (stages, states, times) comes from GitHub and is exact. The verification is an AI assessment: it is marked with the AI accent, shows its evidence, and says *could not be checked* instead of guessing.
- **Automatic only when switched on.** Following and verifying my own pull requests without a click is an option (off by default, per repository).

## 3. Scope of the verification

Always checked, as far as tools and repository configuration allow:

| Question | Source |
|---|---|
| Did the deployment start at all after the merge? | GitHub: workflow runs and deployments for the merge commit |
| Did every stage finish, and how? | GitHub: jobs, environments, deployment statuses |
| Is a stage waiting (approval, queue) or stuck? | GitHub: pending deployments, run age against the usual duration |
| Why did a stage fail? | GitHub: failed job, its log excerpt and annotations |
| Does the deployed version throw errors? | Monitoring and logs named in the repository (e.g. Datadog): new or rising errors of the service since the deployment, compared with before |
| Does the change show the effect it was made for? | Only when it leaves a trace in logs or metrics (an error that should disappear, a new endpoint being called, a rate, a monitor) |

Not checked: whether a UI element is there and behaves correctly, and anything else without a signal in logs or metrics. Such points are listed as *not checked* with the reason.

## 4. The flow

```
PR open ──▶ Merge ──▶ Build ──▶ Dev ──▶ Test ──▶ Prod
   │           │        └── each stage: state from GitHub + verification ──┘
 notify      click          notify per stage            final result + notify
```

1. **Before the merge** — notifications for my pull requests: new comment, approval, change request, checks finished (failed / all green). Clicking opens the pull request.
2. **Merge** — a *Merge* button in the header of a pull request that GitHub reports as mergeable. Offers the methods the repository allows (merge, squash, rebase), remembers the last one per repository, shows what blocks a merge (reviews, checks, conflicts) and can enable GitHub's auto-merge instead. Always a click with a confirmation; never automatic.
3. **Follow** — after the merge the pull request shows a **Delivery** tab. Sylvra finds the workflow runs and deployments of the merge commit and polls them while they run (every 30 s; the app must be running). Each finished or failed stage raises a notification.
4. **Plan** — once per pull request an agent reads the title, description, diff summary, AI review result (if there is one) and the repository's `AGENTS.md` / `CLAUDE.md` and writes a short **verification plan**: what the change fixes or introduces, which service is affected, which signals to look at with which tool, per stage. The plan is visible and can be edited before it runs.
5. **Verify** — when a stage is deployed, the agent carries out the plan for that stage after a settling time (default 5 min, configurable) and reports a result. Production gets a second look later (default 30 min) to catch what only shows under load.
6. **Result** — one verdict per stage and one for the whole delivery, with evidence.

Started by hand (*Follow delivery* on any merged pull request) or automatically for my own pull requests when the option is on.

## 5. The Delivery view

A tab of the PR column, wide enough to read as a pipeline; the inbox row of the pull request shows a compact form (dots per stage).

- **Pipeline strip** at the top: the stages left to right as connected nodes — state (waiting, running, done, failed, skipped, needs approval), duration, when. The running node pulses; a finished stage ticks over once (short, Reduce Motion respected).
- **Stage card** below, for the selected stage (the current one by default):
  - *Deployment* (from GitHub): workflow, jobs with state and duration, the failed step with its log excerpt, *Open on GitHub*, *Approve deployment* when it waits for me.
  - *Verification* (AI accent): verdict — **Healthy**, **Problems found**, **Could not be checked** — the checks carried out as a list, each with what was looked at (tool, query, time window, before / after figure) and what it means. Unchecked points with the reason.
  - *Ask AI about this* on the card and on every check; *Open Claude session* starts an interactive Claude session in the terminal panel, in the repository's worktree, with the stage, its result and the plan as context.
- **Overall line**: "Live in production since 14:32 — healthy" / "Test failed: migration step" / "Prod deployed — 3 new errors in `billing-api`".
- **Activity**: a followed delivery is a background job in the activity indicator and can be stopped there.

States for the empty cases: no deployment found for the merge commit (after a wait: *No deployment started* — a finding in itself), no monitoring tool known for the repository (only the GitHub part is shown, with a hint how to name the tools in `AGENTS.md`).

## 6. Notifications

Per event type in the settings, each on or off:

- My pull request: new comment, approval, change request, checks finished.
- Delivery: stage finished, stage failed, waiting for approval, verification result, delivery complete.

Notifications are posted when Sylvra is not active or shows another pull request; clicking opens the pull request on the right tab. Several events on one pull request within a short time are combined.

## 7. Architecture

- **New slice `FeatureDelivery`**: domain (`Delivery`, `Stage`, `StageState`, `VerificationPlan`, `StageVerification`, `Check`), the GitHub adapter, the follower (polling), view models and the Delivery views. It imports no other slice; the app composes it (tab in the PR column, terminal session, chat, notifications).
- **GitHub** (`Platform/GitHubClient`): workflow runs and jobs for a commit, deployments and deployment statuses, environments and pending deployments, job logs (only the failed step, truncated), `mergePullRequest` / `enablePullRequestAutoMerge`, approving a pending deployment. Stages are ordered by environment and job dependencies; a repository can name and order its stages in the settings when the automatic mapping is wrong.
- **Deployments outside GitHub** (Argo CD, Octopus, …): visible as far as they report deployment statuses to GitHub. What they do not report, the verification agent may find through the tools named in the repository; the view then marks that stage as *seen by the agent*, not as a fact.
- **Agent** (`AgentProvider`): a new request kind next to review and chat — *verify*. It runs Claude Code in the repository's worktree with the user's own configuration, so the MCP servers and tools set up there are available, restricted to reading: file reads, read-only shell commands and the MCP tools of the monitoring servers; no edits, no writes, no deployments. Output is structured (JSON schema, like the review): verdict, checks with evidence, unchecked points.
- **Tool discovery**: from `AGENTS.md` / `CLAUDE.md` and the repository context discovery that the AI review already uses, plus a per-repository setting ("Monitoring: Datadog service `billing-api`, env tags `dev` / `test` / `prod`") for what the files do not say.
- **Persistence**: followed deliveries, plans and results in the existing cache, so a restart resumes following. Results keep their evidence text, never credentials or full logs.
- **Following needs the running app.** No backend, no daemon: a delivery that finished while Sylvra was closed is caught up at the next start (states from GitHub, verification run then with the right time windows).

## 8. Product rules touched

- *Never post to GitHub without an explicit user action* — unchanged: merge and deployment approval are clicks.
- *AI agents run read-only* — still true, but "no network" no longer holds for the verification agent: it queries monitoring tools through the user's own access. Reviews stay as they are.
- *No Git client scope creep* — reworded: no local Git operations (staging, committing, branching, local merging). Merging a pull request on GitHub is a pull request action and in scope.
- *Code is only sent to an AI provider when explicitly started* — the automatic option is that explicit choice, made once per repository.

## 9. Steps

1. **Notifications for my pull requests and Merge** — small, useful on their own.
2. **Delivery tab without AI** — pipeline strip, stage cards from GitHub, stage notifications, approve deployment.
3. **Verification** — plan, verify per stage, results in the cards, *Ask AI about this*, *Open Claude session*.
4. **Automatic for my own pull requests** — the option, catch-up after a restart, inbox dots.

## 10. Open questions

- Mapping of workflows to stages in repositories with several deployment workflows or a monorepo with several services per pull request.
- Usual duration per stage (for "stuck"): learned from earlier runs or configured.
- Cost of the verification: which model and effort by default (suggestion: Sonnet, medium; production check with the review's main model).
- Merge queues: follow the queue entry as a stage before *Build*.
