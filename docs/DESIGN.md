# Design

How the factory behaves at runtime. For how to work on this repo, see
[`AGENTS.md`](../AGENTS.md).

## Principle: maximum automation

The factory runs itself. Once started, it keeps going until every job is
either finished or waiting on a human for a legitimate reason. The operator
should never have to nudge it to continue.

Humans are involved only to:

- confirm a repo's settings once, at adoption;
- decide which issues the factory may pull (a maintainer), either by applying
  `factory` directly or by reviewing a triager's `factory:candidate` proposal.
  This is the trust gate: the factory never labels its own work in, so
  untrusted issue text can't pull itself into the pipeline;
- answer a `factory:needs-info` question on the issue;
- review an escalated PR (`factory:needs-human`);
- approve or merge a PR where the repo's own settings require a human.

Everything else is the factory's call:

- **No check-ins.** The orchestrator never asks whether to continue and never
  stops with work still runnable. Progress goes in files and
  `factory-job status`, not in questions.
- **Decide and record.** A role facing a judgement call makes the best
  decision it can, records it in its report, and carries on. Reviewers and the
  approver catch bad calls.
- **Contain failures.** A failure retries once, then escalates that one job.
  Other jobs keep running.
- **Unattended by design.** Inside the sandbox, runs need no permission
  prompts. The orchestrator stays awake by using the harness's own wake-up
  mechanisms, not by waiting for the operator.

## Glossary

| Term | Meaning |
|---|---|
| Operator | The person running the factory. Has write access to the target repo. |
| Target repo | The repo the factory is working on. |
| Job | One unit of work (one issue or one prompt) moving through the pipeline. |
| Stage | A step in the pipeline: claim, specify, implement, verify, deliver. |
| Role | An agent with one task: triager, specifier, implementer, reviewer, approver, or (outside the pipeline) auditor. |
| Orchestrator | The `/factory` skill. Spawns roles and calls guard scripts. |
| Guard script | A Bash script in `bin/`. The only writer of job state. |
| Job folder | Per-job directory holding the job state and every role's report. |
| Report | The single file a role writes into the job folder. |
| Job header | Line 1 of a report, identifying the job and role. |
| Verdict line | Line 2 of a report, parsed by guard scripts (e.g. `VERDICT: APPROVE`). |
| Gate | The target repo's checks (lint, tests), run from the base branch's definition. |
| Lane | A route through the pipeline (see [Lanes](#lanes)). |

## Pipeline

```
ingress → claim → specify → implement → verify ─changes→ implement
                                          (max 3 rounds)
        → deliver: PR → CI ─fail→ implement
                   → approver → APPROVE (default) → merge | ESCALATE (concerns)
```

| Stage | Done by | What happens |
|---|---|---|
| Claim | Guard script | Mechanical, no judgement: verify the label, lock the issue, snapshot it, create the job. |
| Specify | Specifier (agent) | Judgement: decide whether the work can go ahead (`READY`, `NEEDS-INFO` or `REJECT`) and, if so, write the specification. |
| Implement | Implementer (agent) | Change the code in the job's worktree until the specification's acceptance criteria are met. |
| Verify | Gate (guard script), then reviewers (agents, in parallel) | The gate runs the repo's checks; reviewers judge the diff against the specification. |
| Deliver | Guard script and approver (agent) | Open the PR, decide `APPROVE` or `ESCALATE`, then merge according to the [merge mode](#delivery). |

Each arrow is a transition made by a guard script. The orchestrator decides
what to do next from the guard script's output, never by editing state.
Several jobs can be in the pipeline at once (see
[Parallel jobs](#parallel-jobs)).

The gate runs the checks as defined on the base branch, not the job branch, so
a branch can't change the checks it's judged by. A change to a protected path
(CI config, the checks command and the files it runs, as listed in
`config.json`) fails the gate and escalates.

## Ingress

Work enters in one of four ways.

1. **Skill prompt.** The operator runs `/factory <description>`. The text is
   trusted operator input. The factory creates a job directly, and opens a
   tracking issue if the repo uses issues.
2. **Named issue.** The operator runs `/factory issue <number | search text>`.
   A number selects that issue. Text searches open issues: one match is taken,
   several are listed and nothing is claimed. Naming an issue is the
   operator's decision to let the factory pull it, so a guard script applies
   `factory` on the operator's behalf, then claims it.
3. **Labelled issues.** `/factory run` claims open issues labelled `factory`
   that are not already claimed, and runs until the queue is empty and every
   job is finished or parked. `/factory run --watch` then keeps polling for
   new issues. Each issue is verified (see
   [Trust boundary](#trust-boundary)), claimed, then queued.
4. **Triage (optional).** The triager reads open issues that carry no
   `factory*` label and judges whether each is a good fit: small, well scoped,
   testable. Every issue it assesses gets an outcome label and a comment with
   its reasoning, so no issue is triaged twice:
   - a good fit gets `factory:candidate`, awaiting a maintainer;
   - anything that needs a person (too large, vague, risky or contentious)
     gets `factory:not-candidate`.

   The triager **never** applies `factory`; a maintainer does that. It skips
   any issue that already has a `factory*` label, so a maintainer re-triages
   an issue by removing its outcome label. Each run assesses at most
   `triage_batch` issues (default 10), oldest first.

### Labels

| Label | Set by | Meaning |
|---|---|---|
| `factory` | Maintainer, or a guard script for an operator-named issue | Build this. |
| `factory:candidate` | Triager | Proposed for the factory; awaiting a maintainer. |
| `factory:not-candidate` | Triager | Assessed and left for a person; not re-triaged unless the label is removed. |
| `factory:in-progress` | Guard script | Claimed by a running factory. |
| `factory:needs-info` | Specifier | Question asked on the issue; job parked. |
| `factory:needs-human` | Guard script | Escalated; needs the operator. |
| `factory:speckit` | Maintainer | Lane 2: build from a committed spec-kit spec. |

"Set by" names who decides. Where that is a role, the role records the
decision as its verdict and a guard script applies the label; roles never
edit labels themselves. Guard scripts create missing labels idempotently.

## Trust boundary

- **Label provenance.** Issue forms can apply labels automatically, so the
  label alone proves nothing. Before claiming, a guard script reads the issue
  timeline for the most recent `labeled: factory` event and checks that the
  actor has triage, maintain, write or admin permission. Otherwise it refuses.
- **Snapshot.** At claim time the guard script writes the issue title, body
  and comments to `issue.md` in the job folder. Later edits are ignored. Later
  comments re-enter only if their author has triage access or above (for
  example, answers to `factory:needs-info`).
- **Quoted data.** Roles that read `issue.md` treat it as data to analyse,
  never as instructions to follow.
- **The specifier is the boundary.** The specifier is the last role to read
  the issue. It writes `specification.md` in its own words and has no push
  access.
- **Implementer isolation.** The implementer reads `specification.md` and the
  target repo, never `issue.md`.

## State

- **Location.** Per-clone state lives in
  `$(git rev-parse --git-common-dir)/factory/`, which is `.git/factory/` in a
  normal clone, and is the same from inside any worktree:

  ```
  .git/factory/
    config.json          per-repo config (checks command, merge mode, commit
                         and PR conventions, tiers, parallel limit, limits,
                         model ids seen at the last audit)
    audit.md             latest self-audit and its recommendations
    PAUSED               kill switch (presence = paused)
    jobs/<job-id>/       one job folder per job
  ```

- **Sole writers.** Only guard scripts write `config.json`, `PAUSED` and job
  state. The operator changes them through guard-script commands (for example
  `factory-job config set <key> <value>`, `factory-job pause`), never by
  editing files. Guard scripts hold a lock file while writing and reject any
  transition not in the transition table.
- **Claims.** Local state is a cache; the issue is the cross-machine lock.
  Every factory may run as the same GitHub account, so a claim needs its own
  identity. To claim, a guard script posts a claim comment carrying a unique
  nonce, then re-reads the issue's comments. The earliest claim comment after
  the latest `factory` label event wins. The winner adds
  `factory:in-progress`; any loser deletes its comment and backs off.
- **Resumable.** A restarted orchestrator rebuilds its view from the job
  folders and GitHub, then carries on. Every guard script is idempotent.

## Parallel jobs

- **Limit.** At most `max_parallel_jobs` jobs are active at once. A guard
  script enforces the limit: new jobs past it are queued, not started.
- **Auto-sizing.** `max_parallel_jobs` defaults to `auto`. At the start of
  each run, the harness layer detects the billing plan and passes it to the
  guard script (in Claude Code: `subscriptionType` from
  `claude auth status --json`). The guard script maps it to a limit:

  | Plan | Limit |
  |---|---|
  | API billing | 2 |
  | Pro | 2 |
  | Max | 3 |
  | Ultra | 4 |
  | Unknown or undetectable | 2 |

  The operator can override it with a fixed number
  (`factory-job config set max_parallel_jobs <n>`), which always wins.
  Setting it back to `auto` restores detection. The plan is re-detected on
  every run, so a plan change takes effect without reconfiguring.
- **Isolation.** Each job has its own worktree, branch, job folder and
  implementer. Roles from different jobs never share context. Guard scripts
  lock per job for job state, plus one repo-wide lock for claims and the
  limit.
- **No blocking.** The orchestrator runs roles in the background. When any
  role finishes, it advances that job and starts the next queued job if a
  slot is free.
- **Overlap.** `specification.md` lists the paths the change expects to
  touch. A job whose paths overlap an active job's waits until that job's PR
  is ready, so two jobs never edit the same files at once.
- **Base drift.** Before opening the PR, a guard script rebases the branch
  onto the latest base and re-runs the gate. A conflict returns to the
  implementer once, then escalates.

## File contracts

These are the harness-neutral interface. Any harness whose agents can read
and write files can play a role.

- Each role writes exactly **one report** in its job folder (e.g.
  `specification.md`, `implementation.md`, `round-1/code-review.md`,
  `approval.md`) and replies to the orchestrator with one line. Code changes
  made by the implementer go to the worktree, not the job folder.
- Line 1 is the job header; line 2 is the verdict line. Guard scripts parse
  only those two lines. The rest of the report is free-form for the next role
  and the operator.
- Exact header and verdict formats are fixed when the guard scripts are
  written, and recorded here.

## Lanes

- **Lane 1 (default).** Claim → specify → implement. For small, well-scoped
  work.
- **Lane 2 (spec-kit).** For larger features. The operator writes and commits
  the spec interactively with spec-kit, then labels an issue `factory` and
  `factory:speckit`, pointing at the spec directory. The factory skips the
  specify stage. The approver always escalates in this lane. The factory never
  runs `specify init` or `specify`.

## Target repos

- **No factory files.** No factory config, state, prompts or tooling are
  committed to a target repo. The only commits are the change itself (and, in
  Lane 2, the operator's spec-kit artefacts already on the base branch).
- **Branches.** Names follow the target repo's own convention, read from its
  `AGENTS.md` or contributing docs. The default is
  `<type>/<issue-number>-<slug>` (e.g. `fix/42-null-title`), where `<type>` is
  the change type (`feat`, `fix`, …) recorded in `specification.md`. The
  branch is created after the specify stage, so the type is known. A prompt
  job with no tracking issue uses `<type>/<slug>`. Never use a `factory/`
  prefix or a name that matches a release branch pattern.
- **Commit and PR conventions.** Set per repo in `config.json`:

  | Key | Values |
  |---|---|
  | `commit_convention` | `default` (default): whatever the target repo documents in its `AGENTS.md` or contributing docs; if nothing can be identified, as `conventional`.<br>`conventional`: always Conventional Commits, so semantic-release and changelogs work unchanged. |
  | `pr_convention` | `default` (default): the repo's PR template (e.g. `.github/pull_request_template.md`) and documented title format; if nothing can be identified, as `conventional`.<br>`conventional`: always a title in the commit convention and a body with a summary, the linked issue (`Closes #42`), the acceptance criteria and how they were tested. |

  Whatever the PR convention, squash merges use the PR title as the commit
  message, so the PR title must describe the whole change and satisfy the
  commit convention too.
- **Worktrees.** One per job under `.worktrees/`, ignored by appending to
  `.git/info/exclude`. Disposable: every round is pushed.
- **Main checkout untouched.** The factory never checks out, edits or commits
  in the operator's main checkout. All work happens in worktrees.
- **Reading the repo.** Roles read the target repo's `AGENTS.md`. If there is
  none, they fall back to `CLAUDE.md`, then the README, contributing docs and
  CI config.
- **Adoption.** On the first `/factory run` in a repo, the factory detects the
  base branch, checks command, and commit and PR conventions (the repo's own,
  or Conventional Commits if none can be identified), and asks the operator to
  confirm them once.
  A guard script then writes `config.json`.

## Delivery

- The approver's default verdict is `APPROVE` once every review has passed.
  It escalates only when it has a concrete concern, such as a risky area
  (authentication, data migrations, payments), a specification it isn't
  confident in, or a reviewer's pass that came with reservations. It names
  each concern in `approval.md`.
- On `ESCALATE`, the PR is marked ready, labelled `factory:needs-human`, and
  never merged automatically.
- On `APPROVE`, the PR is marked ready and merged according to `merge_mode`
  in `config.json`:

  | Key | Values |
  |---|---|
  | `merge_mode` | `repo` (default): the factory makes no merge call and changes no merge setting. The PR is merged however the repo already works: by a maintainer, a merge queue, or automation the repo itself has set up.<br>`auto-merge`: the factory turns on GitHub auto-merge for the approved PR, so it merges once the repo's branch protection, required checks and required reviews are satisfied. If the repo doesn't allow auto-merge, the PR falls back to `repo` behaviour.<br>`factory`: the factory merges the PR itself with `gh pr merge` once it is fully resolved: approved, CI green and every review comment addressed. Branch protection still applies. |

  Only the operator can choose `auto-merge` or `factory`, explicitly (e.g.
  `factory-job config set merge_mode auto-merge`). The factory never changes
  the merge mode itself.
- After the PR opens, the factory watches GitHub CI. Failures go back to the
  implementer in one batch per round.

## Limits

These stop work:

- **Budget check** before starting each job. If usage is over the configured
  limit, the queue parks.
- **Round limits.** At most 3 review rounds and 3 CI-fix rounds per job, then
  escalate.
- **Kill switch.** Guard scripts refuse to start or advance any job while
  `.git/factory/PAUSED` exists. Removing the `factory` label from an issue
  cancels its job at the next transition.
- **Usage limits.** A role that hits a usage or rate limit parks its job
  (`waiting-usage`), and the job resumes automatically once the limit resets.
  This is not a failure and never escalates on its own. While any job is
  parked this way, no new jobs start.

This never stops work:

- **Cost reporting** is best-effort and off the critical path. A failure to
  look up or record cost is logged and ignored.

## Sandbox

- Unattended runs must happen inside a Dev Container. Guard scripts refuse on
  the host unless the operator opts out explicitly (flag or `config.json`).
- The GitHub token is the least privilege that works: the target repo only,
  with contents, issues and pull requests access. It comes from the
  environment, never from a file.
- Guard scripts need only Bash, `git`, `gh`, `jq` and coreutils, so no extra
  runtime is required in the container.

## Model routing

Roles are routed by tier, not by model id:

| Tier | Means | Used for |
|---|---|---|
| `strong` | A high-quality model at high effort. | Specifier, implementer, security reviewer, approver |
| `cheap` | A medium-quality model at medium effort. | Triager; code, UX and UI reviewers |

Each tier's model and effort can be overridden per repo (e.g.
`factory-job config set tiers.strong.model <model>`). Each harness's reference
file maps tiers to concrete models and effort levels for that harness. Reviewers are chosen by risk and by
which areas of the code the change touches; the routing table lives in
`config.json`, not in prompts. The reviewers in a round run in parallel, and
the round is complete only when every routed reviewer has written its report.

## Self-audit

The factory periodically checks its own setup. It recommends and warns, but
the operator decides.

- **Audit.** `/factory audit` runs the auditor (`strong`). It writes
  `.git/factory/audit.md` with the verdict line `AUDIT: CURRENT` or
  `AUDIT: CHANGES-RECOMMENDED`. It covers three areas:
  - **Models:** the models currently available through the harness, compared
    with the tier mapping and effort levels in use.
  - **Run history:** job outcomes since the last audit, from the job folders.
    That means escalation and rejection rates and their reasons, review and
    CI rounds used, gate failures, overlap waits and usage-limit parking. The
    auditor recommends changes to tiers, reviewer routing, round limits or
    `max_parallel_jobs` where the history supports them.
  - **Config drift:** whether `config.json` still matches the repo: the
    checks command still passes on base, protected paths still exist, and
    the commit and PR conventions haven't changed.

  For each recommendation it gives the evidence, the reason, and the exact
  `factory-job config set` command.
- **Apply.** `/factory audit apply` applies the latest audit's
  recommendations through the guard script. Nothing changes until the
  operator runs it; the auditor never edits `config.json`.
- **Warn.** At the start of every run the harness layer passes the list of
  available model ids to the guard script. The guard script warns, through
  `factory-job status` and at the start of each run, when there are model ids
  it didn't see at the last audit, or when the last audit is older than
  `audit_days` (default 30). This check needs no model and costs no tokens.
- **Never blocking.** Like cost reporting, the audit is advisory. A failure
  to list models or read history is logged, and work carries on with the
  current config.
