# AGENTS.md

An agentic software factory, shipped as a Claude Code plugin. Work comes in
from a skill prompt or from GitHub issues labelled `factory`, and reviewed pull
requests come out. Claude Code first; harness-agnostic where that's cheap.

This file is the source of truth for agents working **on this repo**. How the
factory itself behaves at runtime is specified in
[`docs/DESIGN.md`](docs/DESIGN.md).

## Status

Early design. Nothing is built yet.

## Layout (planned)

```
.claude-plugin/        plugin and marketplace manifests
skills/factory/        orchestrator skill (/factory)
  references/          harness-specific mechanics (claude-code.md)
agents/                one prompt per role
bin/                   guard scripts (Bash)
tests/                 guard script tests, with fake gh/git
docs/DESIGN.md         runtime design: pipeline, contracts, invariants
```

`docs/plans/` is local-only scratch space and deliberately ignored. Never
commit it, link to it or rely on it.

## Portability rules

1. File contracts (job folder layout, verdict lines, job header) are the
   harness-neutral interface.
2. Role prompt bodies are harness-neutral. Only frontmatter is
   Claude-specific.
3. The orchestrator skill describes the pipeline neutrally. Claude Code spawn
   and resume mechanics live in `skills/factory/references/claude-code.md`.
4. Guard scripts use only Bash, `git`, `gh`, `jq` and coreutils: no harness
   calls.
5. Roles use CLIs (`gh`, a browser CLI to be chosen), not MCP servers or
   plugins.
6. Model routing is by role and tier (`cheap`, `strong`), mapped to models per
   harness.

## Conventions

- Conventional Commits.
- A change to runtime behaviour updates `docs/DESIGN.md` in the same commit.
- Guard scripts are Bash: `set -euo pipefail`, `shellcheck`-clean, and no
  runtime dependency beyond those in portability rule 4. Python is out of
  scope until Bash is demonstrably not enough.
- Guard scripts get tests with fake `gh` and `git` on `PATH` before they are
  relied on.
- Commands for setup, lint and tests go here once the code exists.
