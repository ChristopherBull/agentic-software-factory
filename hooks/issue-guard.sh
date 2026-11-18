#!/usr/bin/env bash
# PreToolUse hook: only the specifier may read a job's issue.md. Every agent
# after it works from the specification, so the issue's text (untrusted) never
# reaches them. Exit 2 blocks the tool call and shows the reason to the agent.
#
# Best effort against accidental reads (a recursive grep, a glob over the job
# folder), not a sandbox: a determined shell command can still get round it.
set -euo pipefail

input="$(cat)"
agent="$(jq -r '.agent_type // ""' <<<"$input")"

case $agent in
  factory:specifier | factory:triager) exit 0 ;;
  factory:*) ;;
  *) exit 0 ;; # the orchestrator, the operator and other plugins' agents
esac

block() {
  printf 'Blocked by the factory: %s Work from specification.md; only the specifier reads the issue.\n' "$1" >&2
  exit 2
}

# Only references into the factory folder count: the factory's own code and
# docs mention issue.md, and agents must still be able to work on them.
jq -e '(.tool_input | tostring) as $t | ($t + " " + (.cwd // "")) | test("\\.git/factory")
  and ($t | test("issue\\.md"))' <<<"$input" >/dev/null &&
  block "this would read issue.md."

case "$(jq -r '.tool_name' <<<"$input")" in
  Grep)
    # Searching a folder that holds a job folder would read issue.md too.
    path="$(jq -r '.tool_input.path // ""' <<<"$input")"
    [[ $path == *.git/factory* && $path != *.md && $path != *.json ]] &&
      block "searching the factory folder would read issue.md."
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    [[ $cmd == *.git/factory* && $cmd =~ (grep|rg|ag)[^|\;\&]*\ -[a-zA-Z]*[rR] ]] &&
      block "a recursive search of the factory folder would read issue.md."
    [[ $cmd =~ \.git/factory/jobs/[^[:space:]]*[*?] ]] &&
      block "a wildcard over a job folder would read issue.md."
    ;;
esac
exit 0
