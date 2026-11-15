#!/usr/bin/env bash
# Install the factory's statusline wrapper for Claude Code (idempotent).
#
# Records the operator's existing statusLine command, then points statusLine at
# a wrapper that prints that command's output unchanged, followed by the
# factory segment. Changes nothing in settings.json except statusLine.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DIR="$CLAUDE_DIR/factory"
WRAPPER="$DIR/statusline.sh"
RECORD="$DIR/statusline.json"
FJ="$(cd "$HERE/.." && pwd)/bin/factory-job"

mkdir -p "$DIR"
[[ -f $SETTINGS ]] || echo '{}' >"$SETTINGS"
cp "$HERE/factory-statusline.sh" "$WRAPPER"
chmod +x "$WRAPPER"

current="$(jq -c '.statusLine // null' "$SETTINGS")"
if [[ $(jq -r '.command // empty' <<<"$current") == "$WRAPPER" ]]; then
  # Already installed: only refresh the recorded guard-script path.
  jq --arg fj "$FJ" '.factory_job = $fj' "$RECORD" >"$RECORD.tmp" && mv "$RECORD.tmp" "$RECORD"
  echo "STATUSLINE: already installed"
  exit 0
fi

jq -n --argjson original "$current" --arg fj "$FJ" '{original: $original, factory_job: $fj}' >"$RECORD"
tmp="$(mktemp "$SETTINGS.XXXXXX")"
jq --arg cmd "$WRAPPER" '.statusLine = ((.statusLine // {}) + {type: "command", command: $cmd})' "$SETTINGS" >"$tmp"
mv -f "$tmp" "$SETTINGS"
echo "STATUSLINE: installed (your previous statusline still runs first)"
