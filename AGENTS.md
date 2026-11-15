# AGENTS.md

An agentic software factory, shipped as a Claude Code plugin. Work comes in
from a skill prompt or from GitHub issues labelled `factory`, and reviewed pull
requests come out. Claude Code first; harness-agnostic where that's cheap.

This file is the source of truth for agents working **on this repo**. How the
factory itself behaves at runtime is specified in
[`docs/DESIGN.md`](docs/DESIGN.md).

## Status

MVP built, shellcheck-clean, and tested against a fake `gh` (see Commands). Not yet run end to
end against a real GitHub repo. Everything under Future in
`docs/DESIGN.md` is not built.

## Layout

```
.claude-plugin/        plugin and marketplace manifests
.devcontainer/         Dev Container for working on and dogfooding the factory
.github/workflows/     CI
skills/factory/        orchestrator skill (/factory)
  references/          harness-specific mechanics (claude-code.md)
agents/                one prompt per role
bin/                   guard scripts (Bash)
board/                 live board page (static, self-contained)
statusline/            harness statusline wiring
tests/                 guard script tests (real git, fake gh)
docs/DESIGN.md         runtime design: pipeline, contracts, settings
docs/INSTALL.md        installing, enabling and running the plugin
```

## Portability rules

1. File contracts (job folder layout, verdict lines, job header) are the
   harness-neutral interface.
2. Agent prompt bodies are harness-neutral: they say "run a shell command" or
   "read the file", never a harness's tool names. Each body states its tier.
   Only frontmatter is Claude-specific, and carries the tier's default model
   and effort. Per-repo tier overrides are applied when the agent is spawned.
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
- Guard scripts get tests before they are relied on. Tests use real `git`
  against a throwaway bare remote, and the fake `gh` in `tests/fake-gh/` on
  `PATH`. When the guard script makes a new kind of `gh` call, extend the
  fake to match; it fails loudly on calls it doesn't know.
- Never edit files under `.git/factory/` by hand, in tests or otherwise;
  go through `bin/factory-job`.

## Commands

Requirements: Bash, `git`, `jq`, `shellcheck`. No `gh` login is needed for
the tests.

```
tests/run.sh                 # all guard-script tests
tests/run.sh <pattern>       # tests whose names contain <pattern>
shellcheck bin/factory-job tests/run.sh tests/fake-gh/gh statusline/*.sh .devcontainer/*.sh
```

CI (`.github/workflows/ci.yml`) runs shellcheck, checks the plugin manifests
and agent frontmatter, and runs the tests, on every pull request and push to
`main`. `.shellcheckrc` disables SC2016 only: jq programs are single-quoted on
purpose.

To try the plugin without installing it: `claude --plugin-dir <this repo>`.
