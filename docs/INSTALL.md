# Installing the factory

The factory is a Claude Code plugin, published from this repo as the
`agentic-software-factory` marketplace. Nothing is installed into the repos it
works on.

## What the environment needs

Run the factory inside a Dev Container. The guard script refuses to run jobs
on the host unless you opt out.

| Needed | Why |
|---|---|
| Claude Code, signed in | Runs the orchestrator and agents. |
| `git`, `gh` (authenticated), `jq`, Bash, coreutils | The guard script uses nothing else. |
| `python3`, `node` or `busybox` (optional) | Serves the board on `localhost`. Without one, the board opens from disk, which only works where your browser can see the repo's files (a local clone or a bind mount). |

The GitHub token needs access to the target repo only, with contents, issues
and pull requests. Keep it in the environment, never in a file.

### Dev Containers without VS Code

`devcontainer.json` is an open standard ([containers.dev](https://containers.dev)),
not a VS Code feature. Any of these can start the container from it:

- **The `devcontainer` CLI** (`npm install -g @devcontainers/cli`):

  ```
  devcontainer up --workspace-folder .
  devcontainer exec --workspace-folder . claude --permission-mode auto
  ```

  It bind-mounts the repo, so the board also opens from disk.
- **DevPod** (`devpod up .`) gives the container an SSH host. Tools that can
  run agents over SSH can then run Claude Code inside the container.
- **VS Code or Codespaces**, which read the file directly.

Tools that don't read `devcontainer.json` (for example agent environments
that run agents in local worktrees) can still use the container. Start it
with one of the above, then run Claude Code inside it through
`devcontainer exec` or the SSH host. Don't run the factory's agents directly
on the host: the guard script refuses unless you opt out.

This repo's own `.devcontainer/` has everything needed to work on and
dogfood the factory.

## Install

### Once, interactively

```
/plugin marketplace add ChristopherBull/agentic-software-factory
/plugin install factory@agentic-software-factory
```

### For every container, from your dotfiles

Add the marketplace and enable the plugin in the `~/.claude/settings.json`
your dotfiles install:

```jsonc
{
  "extraKnownMarketplaces": {
    "agentic-software-factory": {
      "source": { "source": "github", "repo": "ChristopherBull/agentic-software-factory" }
    }
  },
  "enabledPlugins": { "factory@agentic-software-factory": true }
}
```

## Enabled everywhere, or per project?

| | Everywhere (user settings) | Per project |
|---|---|---|
| How | `enabledPlugins` in `~/.claude/settings.json`, as above | Install it, leave it disabled at user scope, and set `enabledPlugins` in the project's uncommitted `.claude/settings.local.json` |
| Setup per repo | None: `/factory run` adopts the repo the first time | One line per repo |
| Cost | The plugin's skill and agent descriptions are loaded into every session, and its agents appear in every project's agent list | None outside the projects that use it |

Both work the same once enabled. Choose "everywhere" if you use the factory in
most repos, and "per project" if you use it in a few.

## Updates and pinning

- **Third-party marketplaces don't auto-update by default.** Turn it on under
  **Marketplaces** in `/plugin`, or update by hand.
- **Pinning:** while experimenting, pin a tag or commit with the marketplace
  source's `ref` (e.g. `"ref": "v0.1.0"`). Switch to tracking `main` once it's
  stable.

## Running unattended

Start Claude Code in the container in **auto mode**, where a classifier
reviews each action instead of prompting you:

```
claude --permission-mode auto
```

Auto mode can't be set from a project's settings, so pass the flag, or set
`"permissions": {"defaultMode": "auto"}` in the container's
`~/.claude/settings.json`.

If something interrupts a run (a prompt, or an action auto mode denies, which
usually surfaces as an escalated or parked job), tune the permissions rather
than loosening them wholesale:

1. Find what was blocked: the prompt itself, or the job's history on the
   board.
2. If it's something the factory should always be allowed to do, add a narrow
   rule to `permissions.allow` in the container's `~/.claude/settings.json`,
   e.g. `"Bash(git -C * push *)"`. If it should never happen, add it to
   `permissions.deny`.
3. Run again, and repeat until runs finish without interruptions.

`bypassPermissions` skips all of this, but it removes every check. Keep it as
a last resort for a fully isolated, disposable container, run as a non-root
user. See `skills/factory/references/claude-code.md` for details.

## First run

In the repo you want the factory to work on:

```
/factory run
```

The first run adopts the repo. It detects the base branch, the checks command,
the conventions and a parallel limit for your plan, and asks you to confirm
them once. After that, label issues `factory` (or run `/factory
<description>`), and watch progress with `/factory board`.
