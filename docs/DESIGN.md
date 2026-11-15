# Design

How the factory behaves at runtime. For how to work on this repo, see
[`AGENTS.md`](../AGENTS.md).

## Glossary

| Term | Meaning |
|---|---|
| Operator | The person running the factory. Has write access to the target repo. |
| Target repo | The repo the factory is working on. |
| Job | One unit of work (one issue or one prompt) moving through the pipeline. |
| Role | An agent with one job in the pipeline: triager, intake, spec writer, builder, reviewer, approver. |
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
ingress → intake → spec writer → builder → gate ─fail→ builder
        → reviewers ─changes→ builder        (max 3 rounds)
        → PR → CI ─fail→ builder
        → approver → ESCALATE (default) | merge (if enabled)
```

Each arrow is a transition made by a guard script. The orchestrator decides
what to do next from the guard script's output, never by editing state.

The gate runs the checks as defined on the base branch, not the job branch, so
a branch can't change the checks it's judged by. A change to a protected path
(CI config, the checks command and the files it runs, as listed in
`config.json`) fails the gate and escalates.

## Ingress

Work enters in one of three ways.

1. **Skill prompt.** The operator runs `/factory <description>`. The text is
   trusted operator input. The factory creates a job directly, and opens a
   tracking issue if the repo uses issues.
2. **Labelled issues.** `/factory run` polls for open issues labelled
   `factory` that are not already claimed. Each one is verified (see
   [Trust boundary](#trust-boundary)), claimed, then queued.
3. **Triage (optional).** The triager reads unlabelled open issues and judges
   whether each is a good fit: small, well scoped, testable. For a good fit it
   comments with its reasoning and adds `factory:candidate`. It **never**
   applies `factory`; a maintainer does that.

### Labels

| Label | Set by | Meaning |
|---|---|---|
| `factory` | Maintainer | Build this. |
| `factory:candidate` | Triager | Proposed for the factory; awaiting a maintainer. |
| `factory:in-progress` | Guard script | Claimed by a running factory. |
| `factory:needs-info` | Intake | Question asked on the issue; job parked. |
| `factory:needs-human` | Guard script | Escalated; needs the operator. |
| `factory:speckit` | Maintainer | Lane 2: build from a committed spec-kit spec. |

Guard scripts create missing labels idempotently.

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
- **Spec writer is the boundary.** The spec writer is the last role to read
  the issue. It writes `spec.md` in its own words and has no push access.
- **Builder isolation.** The builder reads `spec.md` and the target repo,
  never `issue.md`.

## State

- **Location.** Per-clone state lives in
  `$(git rev-parse --git-common-dir)/factory/`, which is `.git/factory/` in a
  normal clone, and is the same from inside any worktree:

  ```
  .git/factory/
    config.json          per-repo config (checks command, merge mode, limits)
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

## File contracts

These are the harness-neutral interface. Any harness whose agents can read
and write files can play a role.

- Each role writes exactly **one report** in its job folder (e.g. `intake.md`,
  `spec.md`, `review-code.md`, `approval.md`) and replies to the orchestrator
  with one line. Code changes made by the builder go to the worktree, not the
  job folder.
- Line 1 is the job header; line 2 is the verdict line. Guard scripts parse
  only those two lines. The rest of the report is free-form for the next role
  and the operator.
- Exact header and verdict formats are fixed when the guard scripts are
  written, and recorded here.

## Lanes

- **Lane 1 (default).** Intake → spec writer → build. For small, well-scoped
  work.
- **Lane 2 (spec-kit).** For larger features. The operator writes and commits
  the spec interactively with spec-kit, then labels an issue `factory` and
  `factory:speckit`, pointing at the spec directory. The factory skips intake
  and the spec writer. The approver always escalates in this lane. The factory
  never runs `specify init` or `specify`.

## Target repos

- **No factory files.** No factory config, state, prompts or tooling are
  committed to a target repo. The only commits are the change itself (and, in
  Lane 2, the operator's spec-kit artefacts already on the base branch).
- **Branches.** Names follow the target repo's own convention, read from its
  `AGENTS.md` or contributing docs. The default is
  `<type>/<issue-number>-<slug>` (e.g. `fix/42-null-title`), where `<type>` is
  the Conventional Commits type recorded in `spec.md`. The branch is created
  after the spec is written, so the type is known. A prompt job with no
  tracking issue uses `<type>/<slug>`. Never use a `factory/` prefix or a name
  that matches a release branch pattern.
- **Commits and PR titles.** Both use Conventional Commits. Squash merges use
  the PR title as the commit message, so the PR title must describe the whole
  change in that format. This keeps semantic-release and changelogs working
  unchanged.
- **Worktrees.** One per job under `.worktrees/`, ignored by appending to
  `.git/info/exclude`. Disposable: every round is pushed.
- **Main checkout untouched.** The factory never checks out, edits or commits
  in the operator's main checkout. All work happens in worktrees.
- **Reading the repo.** Roles read the target repo's `AGENTS.md`. If there is
  none, they fall back to `CLAUDE.md`, then the README, contributing docs and
  CI config.
- **Adoption.** On the first `/factory run` in a repo, the factory detects the
  base branch and checks command and asks the operator to confirm them once.
  A guard script then writes `config.json`.

## Delivery

- The approver's default verdict is `ESCALATE`: the PR is marked ready and
  labelled `factory:needs-human`.
- By default the factory never merges. An approved PR is merged through the
  repo's own PR process (a maintainer, a merge queue or GitHub auto-merge), so
  its branch protection and required checks decide.
- The operator can override this by setting the merge mode to `gh`
  (`factory-job config set merge gh`), optionally limited to low-risk changes. The factory then
  merges approved PRs itself with `gh pr merge`, which still respects branch
  protection.
- After the PR opens, the factory watches GitHub CI. Failures go back to the
  builder in one batch per round.

## Limits

These stop work:

- **Budget check** before starting each job. If usage is over the configured
  limit, the queue parks.
- **Round limits.** At most 3 review rounds and 3 CI-fix rounds per job, then
  escalate.
- **Kill switch.** Guard scripts refuse to start or advance any job while
  `.git/factory/PAUSED` exists. Removing the `factory` label from an issue
  cancels its job at the next transition.

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

Roles are routed by tier (`cheap`, `strong`), not by model id. Each harness
reference file maps tiers to its models. Reviewers are chosen by risk and by
which areas of the code the change touches; the routing table lives in
`config.json`, not in prompts.
