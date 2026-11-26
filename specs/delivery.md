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
4. **Plan** — the agent states what the change is meant to fix or introduce (`intent`, from the description and, if needed, the diff) and derives the checks from it, reading the repository's `AGENTS.md` / `CLAUDE.md` and the user's monitoring notes for the repository. In the first version this happens within each check and is shown with its result; a separate plan that can be edited before it runs is a later step.
5. **Verify** — on a click (*Check with AI* on the card of a deployed environment or a failed stage), or for followed deliveries with *Check Followed Deliveries with AI* switched on (off by default): a deployed environment after a settling time (5 min), production once more later (30 min after its deployment; production is the last environment named like it, else the last environment), a failed stage at once. A passed build stage is not checked. The delivery stays followed until its checks are through. Planned checks live in memory: a restart drops them (catch-up comes with step 4).
6. **Result** — one verdict per stage and one for the whole delivery, with evidence.

Started by hand (*Follow delivery* on any merged pull request) or automatically for my own pull requests when the option is on.

## 5. The Delivery view

A merged pull request shows its delivery in the **main area, instead of the diff** — after the merge the diff is done with, the delivery is what matters, and it needs the room. A segmented control in the toolbar (*Diff · Delivery*) switches back to the diff; the choice is kept per pull request while Sylvra runs. The terminal panel stays below as with the diff. The PR column keeps its tabs. Preview: the design canvas *Sylvra Delivery – grosse Ansicht* (V2).

- **Headline**: where the delivery stands ("test is running", "dev failed", "Deployed to prod"), when it was merged and the merge commit, the bell to follow it, and the options (AI checks for followed deliveries, monitoring notes).
- **Workflow graph**, drawn like GitHub draws a run: each stage a band with its name and duration; its jobs as boxes in columns by what they wait for (`needs:` read from the workflow file at the merge commit — splits and joins included; without the file the jobs of a stage stand side by side), joined by smooth curves from box edge to box edge with a dot at each end, the walked ones green. Where several boxes all wait for the same several boxes (nine test jobs for nine build jobs), the lines gather in one ringed junction between them — n + m lines instead of n × m. A reusable workflow's job ("deploy / deploy-infrastructure") shows its own name, the caller below. Boxes fill their cell, 200 × 76 pt (rounded rectangles, not pills), with two-line titles; the AI check's are 270 pt wide. Boxes have soft corners and shadows; their state is a round filled badge (check, cross, turning arrows while running, an outlined ring while waiting). A running or failed job shows its current (or failed) step and its steps as small segments — done green, running violet, failed red, still to come grey ("4/7 Run migrations"); the tooltip lists them, a pending job a dashed border, an environment waiting for approval a box of its own. Wider than the window, the graph **scrolls sideways** and starts at the current stage. A click on a band selects the stage, on a box the job.
- **AI check card** at the end of the graph, joined to the last stage by a dashed line — an assessment, not a workflow step, so it has its own form (AI accent, no job boxes). On top the result in one sentence (the last checked stage's summary, or *Checking test…*, or *Not checked yet*), the time and *reads only*, *Check All (Again)*; tools Claude Code blocked with *Allow…*; then one row per stage that can be checked (a deployed environment or a failed stage) or was checked: badge, stage, verdict, "2 checked · 2 open", the checks as chips (filled dot checked, ring open, red on a problem), or *Check with AI* / *Stop* / *Retry*. A row selects the stage's AI check in the details, a chip one of its checks; the stage's own details show only a line *AI check · Healthy ›* that leads there. Preview: canvas *Sylvra Delivery – grosse Ansicht*, V3 variant A.
- **Split**: the graph takes at most half of the height (it scrolls down for stages with many jobs, as well as sideways), the details at least 260 pt; a grip between them sets the share, remembered across launches.
- **Details of the selected stage**, framed in the same colour as the selected band, so they read as its details: on the left the stage (state, *Open on GitHub*, *Approve Deployment…* when it waits for the user), its jobs, the AI check (verdict, what the change is meant to do, the checks, *Not checked*, *What the agent did*; a running check can be stopped — the agent is terminated, an earlier result stays), *Ask AI about this* and *Open Claude Session* (prominent as *Fix with Claude Code* on a problem; a click opens Sylvra's terminal, the menu the external one). On the right what the selected row stands for — the selected row takes the pane's colour and runs into it:
  - a **job**: its steps as GitHub lists them (state, number, name, duration; folded to "7 steps · all done" when the job went through, open with the current step marked when it runs or failed), the errors it reported, its **log** from GitHub — an excerpt around the first error (else the end), timestamps shortened to the time, groups as headings, errors red; *Show all* opens the rest. A running job's log reloads with the delivery.
  - a **check**: the finding, the query or command as run, the figures before and after the deployment, the telling lines of the log (all from the agent; AI accent).
  - *Not checked* with the reasons; *What the agent did*: every tool call of the check, in order (read-only).
  - With nothing clicked, the details start with what matters: a failed job, a check with a problem, the first check, the running job, the last job.
- **Inbox**: deliveries are cached across launches (the 60 most recently merged); unfinished ones are loaded once at launch, and pull requests the inbox lists as recently closed get theirs loaded without being opened (at most 15 per refresh, each once per launch unless still on its way). A merged pull request with a delivery shows the stages as joined dots and the outcome — a green check with *Live* / *Live · checked healthy*, a red exclamation mark with *dev failed* / *Live · problems found*, while it runs the headline ("test is running").
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
- **Agent** (`AgentProvider.investigate`): a request kind next to review and chat. Claude Code runs in an empty Sylvra-owned directory with the pull request's worktree added for reading, with the user's settings only (no settings, hooks or MCP servers from the repository) — but, unlike a review, with the user's own MCP servers, where monitoring tools live. Built-in tools: Read, Grep, Glob, and Bash only for a fixed list of read-only `gh` / `git` commands (`gh run view`, `gh pr view`, `gh pr diff`, `git log` …). `--permission-mode dontAsk`: every other tool call — each MCP tool included — runs only if the user allowed it in their own Claude Code settings; a denied call is reported as *not checked* with the reason. So the access rules of the user's tools and company stay in force, and Sylvra adds none. Output is structured (JSON schema): verdict, summary, intent, checks with evidence, unchecked points. MCP servers a repository defines in its own `.mcp.json` are not loaded yet (open question below). **Blocked tools**: Claude Code reports the tool calls it refused (`permission_denials`). The AI check shows them (*Claude Code blocked tools this check needed: datadog · analyze_datadog_logs …*) with *Allow for AI Checks…*: after a confirmation that names the tools and says they are then called without asking in every repository, Sylvra keeps them in its own list (global — they belong to the agent setup on this Mac, not to a repository) and passes them with every AI check (`--allowedTools`), then checks again. The user's other Claude sessions keep their own rules. The options menu (…) lists them with *Stop Allowing*.
- **Tool discovery**: from `AGENTS.md` / `CLAUDE.md` and the repository context discovery that the AI review already uses, plus a per-repository setting ("Monitoring: Datadog service `billing-api`, env tags `dev` / `test` / `prod`") for what the files do not say.
- **Persistence**: followed deliveries, plans and results in the existing cache, so a restart resumes following. Results keep their evidence text, never credentials or full logs.
- **Following needs the running app.** No backend, no daemon: a delivery that finished while Sylvra was closed is caught up at the next start (states from GitHub, verification run then with the right time windows).

## 8. Product rules touched

- *Never post to GitHub without an explicit user action* — unchanged: merge and deployment approval are clicks.
- *AI agents run read-only* — still true, but "no network" no longer holds for the verification agent: it queries monitoring tools through the user's own access. Reviews stay as they are.
- *No Git client scope creep* — reworded: no local Git operations (staging, committing, branching, local merging). Merging a pull request on GitHub is a pull request action and in scope.
- *Code is only sent to an AI provider when explicitly started* — the automatic option is that explicit choice, made once per repository.

## 9. Steps

1. **Notifications for my pull requests and Merge** — small, useful on their own. *(built: see `ux.md` §6.1 and §13; merge queues not yet handled)*
2. **Delivery tab without AI** — pipeline strip, stage cards from GitHub, stage notifications, approve deployment. *(built)* How stages are formed: a workflow's jobs that deploy nowhere are a build stage (several such workflows side by side are combined into *Build & checks*); every environment a job deploys to is a stage; deployments reported by other systems add a stage per environment. Only runs started by the merge count (push, `workflow_run`, dispatch, deployment, release), not the pull request's own checks or schedules on the same commit. A merge through Sylvra is followed automatically; any other merged pull request with the bell in its Delivery tab. A followed delivery ends five minutes after its last stage (a chained workflow may still start), at once on a failure, or when nothing started five minutes after the merge.
3. **Verification** — check per stage, results in the cards, *Ask AI about this*, *Open Claude Session*. *(built; composition in the app: `FeatureDelivery` knows what to ask, `FeatureAIReview` how to run the agent. Model, effort and language are the AI review's defaults. Monitoring notes per repository in the Delivery tab's options menu.)*
4. **Automatic for my own pull requests** — the option, catch-up after a restart, inbox dots.

## 10. Open questions

- Mapping of workflows to stages in repositories with several deployment workflows or a monorepo with several services per pull request.
- Usual duration per stage (for "stuck"): learned from earlier runs or configured.
- Cost of the verification: which model and effort by default (suggestion: Sonnet, medium; production check with the review's main model).
- Merge queues: follow the queue entry as a stage before *Build*.
- MCP servers from the repository's `.mcp.json` (often where a team's monitoring server is defined): loading them means running commands the repository names — only with an explicit opt-in per repository.
- An editable verification plan, and settling times per repository.
