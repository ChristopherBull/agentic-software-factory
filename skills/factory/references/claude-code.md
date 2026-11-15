# Claude Code mechanics

How the harness-neutral orchestrator in `../SKILL.md` runs inside Claude
Code. Everything Claude-specific lives here (and in agent frontmatter). This
is the only file in the repo that names models.

## Tiers

| Tier | Model (alias) | Effort |
|---|---|---|
| `strong` | Claude Opus 5.5 (`opus`) | `high` |
| `cheap` | Claude Sonnet 5.5 (`sonnet`) | `medium` |

Claude Fable 5.2 (`fable`) at `high` is the opt-in premium override for
`strong` (`factory-job config set tiers.strong.model fable`). Keep premium
models as overrides, never as the default.

Each agent's frontmatter carries its tier's default `model` and `effort`. When
a `spawn` line from `factory-job plan` includes `model=` or `effort=`, pass
those as the Agent tool's `model` and `effort` parameters; they override the
frontmatter. The Agent tool's `model` takes an alias only (`opus`, `sonnet`,
`haiku`, `fable`).

## Running the guard script

The guard script is `${CLAUDE_PLUGIN_ROOT}/bin/factory-job`. Claude Code
substitutes `${CLAUDE_PLUGIN_ROOT}` in skill and agent bodies, but does not
export it to the Bash tool, so use the absolute path that `SKILL.md` shows.
Run it from the target repo's main checkout.

## Spawning and resuming agents

- Plugin agents are addressed as `factory:<agent>`, e.g.
  `subagent_type: "factory:reviewer-security"`.
- Start every agent with `run_in_background: true`. Its completion arrives as
  a notification that re-invokes you, so you never need to poll.
- Send all independent `spawn` lines from one `plan` in a **single message**
  with several Agent tool calls, so they run in parallel.
- Name each implementer `implementer-<job>` when you spawn it (the Agent tool's
  `name`). For a `resume` line, send that name the round message with
  `SendMessage`. If the session restarted and the name is gone, spawn a fresh
  implementer: the reports in the job folder carry everything it needs.
- An agent's one-line reply is all you need from it; never paste its reports
  into the conversation.

## Staying awake

- While agents run, wait for their completion notifications. Don't end your
  turn while `plan` still lists work you can start.
- **Watch mode** (`/factory run --watch`): when the loop is idle, start
  `sleep 300` with the Bash tool and `run_in_background: true`. Its completion
  wakes you; then `pull` and continue. For an unattended schedule, the
  operator can instead use `/loop 10m /factory run`.
- **Usage limits:** if an agent fails with a usage or rate limit, park the job.
  If the error gives a reset time, sleep until then in the background,
  otherwise sleep 15 minutes; then `unpark` and continue.

## Detecting the billing plan

```
claude auth status --json
```

Read `authMethod` and `subscriptionType`. If `authMethod` isn't `claude.ai`,
the plan is `api`. Otherwise pass `subscriptionType` to `adopt --plan`. The
guard script maps any value containing `ultra` to 4, `max` to 3, and
everything else (including `pro`, team plans and unknown values) to 2.

Confirmed on a Pro login: `{"authMethod": "claude.ai", "subscriptionType":
"pro", "planTier": "pro"}`. The Max and Ultra values couldn't be checked from
a Pro login; the substring match is deliberately loose so that values like
`max_5x` still map correctly.

## Listing available models

No model call is needed. Write the ids, one per line, to a temporary file and
pass it to `factory-job run-start --models <file>`.

1. **With an API key** (`ANTHROPIC_API_KEY` set):

   ```
   curl -fsS https://api.anthropic.com/v1/models \
     -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
     | jq -r '.data[].id'
   ```

2. **On a subscription login** (no API key), use Anthropic's public models
   overview:

   ```
   curl -fsSL https://platform.claude.com/docs/en/about-claude/models/overview.md \
     | grep -oE '\bclaude-(opus|sonnet|haiku|fable|mythos)-[0-9][a-z0-9-]*\b' | sort -u
   ```

   Checked on 2026-11-15: it lists `claude-fable-5-2`, `claude-haiku-5-5`,
   `claude-opus-5-5` and `claude-sonnet-5-5`.

3. If both fail, skip `--models`. The audit warning is advisory and must never
   block a run.

## Running unattended

Inside the Dev Container, start Claude Code so nothing prompts mid-run:

```
claude --permission-mode bypassPermissions
```

`bypassPermissions` (or `--dangerously-skip-permissions`) is meant for
isolated containers only, and must run as a non-root user. It can't be set
from project settings; pass the flag, or set
`"permissions": {"defaultMode": "bypassPermissions"}` in the container's
`~/.claude/settings.json`. Outside a container, the guard script refuses to
run jobs unless the operator opts out (`factory-job config set allow_host
true`). In that case prefer an allowlist over bypassing permissions.

## Statusline

Claude Code shows one `statusLine` command, set in `~/.claude/settings.json`.
A plugin can't add to it, so the factory wraps the operator's command:

- **`/factory statusline on`**: run
  `${CLAUDE_PLUGIN_ROOT}/statusline/install.sh`, then
  `factory-job config set statusline on`. The installer is idempotent. On
  first run it records the existing `statusLine` command in
  `~/.claude/factory/statusline.json`, then points `statusLine` at
  `~/.claude/factory/statusline.sh`. The wrapper runs the original command
  with the same input, prints its output unchanged, then appends
  `factory-job statusline` for the session's directory. It changes nothing in
  `settings.json` except `statusLine`.
- **`/factory statusline off`**: `factory-job config set statusline off`. No
  settings change; the wrapper prints the original statusline alone.

The wrapper finds the guard script through the path the installer recorded,
and falls back to the newest installed copy of the plugin if that path has
gone (plugin updates change the install directory).

## Pre-build checks (results)

| Check | Result |
|---|---|
| Bare `/factory` | **Works.** A throwaway plugin named `factory` with a skill named `factory` answered both `/factory ping` and `/factory:factory ping` (`claude --plugin-dir`, 2026-11-15). The docs only document `/plugin:skill`, so `/factory:factory` is the fallback if another command ever claims `/factory`. |
| Plugin agent frontmatter | Plugin agents **ignore** `hooks`, `mcpServers`, `permissionMode` and `initialPrompt`. `name`, `description`, `tools`, `model`, `effort`, `color` and the rest are supported. |
| Implementer's pre-stop check | Not a hook. `factory-job advance J implementer` refuses a missing or malformed `implementation.md`, and the orchestrator sends the refusal back to the same implementer. That's deterministic and needs no `hooks/hooks.json`. If a hook is ever wanted, it must go in the plugin's `hooks/hooks.json` as a `SubagentStop` hook with the matcher `^factory:implementer$`. |
| Effort per agent | The `effort` frontmatter field (`low`, `medium`, `high`, `xhigh`, `max`), overridable per spawn with the Agent tool's `effort` parameter. `CLAUDE_CODE_EFFORT_LEVEL` overrides both. |
| Listing models | See [Listing available models](#listing-available-models). |
| Billing plan | See [Detecting the billing plan](#detecting-the-billing-plan). |
| Board live updates | **Works**, by re-injecting `<script src="data.js?t=…">`. Checked in headless Chromium (`file://` and served by `python3 -m http.server`) and headless Firefox (`file://`), editing `data.js` mid-run. `fetch` is never used. |
| Board servers | `python3 -m http.server <port> --bind 127.0.0.1 --directory <board>` is checked. The inline `node` server (built-in modules only) and `busybox httpd -f -p 127.0.0.1:<port> -h <board>` are written to their documented interfaces, but couldn't be run here (neither is installed). |
| Port forwarding | VS Code forwards ports that a process inside a Dev Container or Codespace listens on (`remote.autoForwardPorts`, on by default), including ports bound to `127.0.0.1`. This comes from VS Code's documented behaviour, not a test in a container. |
