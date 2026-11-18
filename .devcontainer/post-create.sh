#!/usr/bin/env bash
# One-off setup for the factory's Dev Container.
set -euo pipefail

# The guard script's dependencies, shellcheck for linting, python3 for the
# board's localhost server.
sudo apt-get update -qq
sudo apt-get install -y -qq jq shellcheck python3 >/dev/null

# Playwright and Google Chrome, to check the board in a real browser. The
# Playwright MCP server defaults to the Chrome channel, not bundled Chromium.
# Pinned so a rebuild doesn't pick up a just-published release.
if ! command -v playwright >/dev/null; then
  npm install -g --silent playwright@1.64.1
fi
playwright install --with-deps chrome >/dev/null

# Claude Code, with Anthropic's native installer.
if ! command -v claude >/dev/null; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# The volume mounted at ~/.claude starts out owned by root.
sudo chown -R "$(id -u):$(id -g)" "$HOME/.claude"

cat <<'MSG'

Factory Dev Container ready.
  - Sign in to Claude Code:  claude
  - GitHub:                  gh auth status   (or set GH_TOKEN on the host)
  - Run the tests:           tests/run.sh
  - Screenshot the board:    playwright screenshot --channel chrome http://127.0.0.1:4173/ board.png
  - Dogfood the factory:     claude --plugin-dir . --permission-mode auto, then /factory run
MSG
