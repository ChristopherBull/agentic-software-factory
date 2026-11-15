#!/usr/bin/env bash
# Claude Code statusline wrapper, installed by statusline/install.sh.
#
# Runs the operator's original statusline command with the same input and
# prints its output unchanged, then appends the factory segment. The segment
# is empty unless the repo is adopted and its statusline toggle is on.
set -uo pipefail

input="$(cat)"
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RECORD="$DIR/statusline.json"

original="$(jq -r '.original.command // empty' "$RECORD" 2>/dev/null)"
fj="$(jq -r '.factory_job // empty' "$RECORD" 2>/dev/null)"
if [[ ! -x $fj ]]; then
  # Plugin updates move the install directory; use the newest installed copy.
  # shellcheck disable=SC2012 # ls -t is the simplest way to sort by age here
  fj="$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/factory/*/bin/factory-job 2>/dev/null | head -n1)"
fi

out=""
[[ -n $original ]] && out="$(printf '%s' "$input" | bash -c "$original" 2>/dev/null)"

segment=""
cwd="$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null)"
if [[ -n $fj && -x $fj && -n $cwd && -d $cwd ]]; then
  segment="$(cd "$cwd" && timeout 1 "$fj" statusline 2>/dev/null)"
fi

if [[ -n $out && -n $segment ]]; then
  printf '%s │ %s\n' "$out" "$segment"
elif [[ -n $out ]]; then
  printf '%s\n' "$out"
elif [[ -n $segment ]]; then
  printf '%s\n' "$segment"
fi
