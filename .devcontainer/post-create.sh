#!/usr/bin/env bash
# One-off setup for the factory's Dev Container. Anything that can be is in
# the Dockerfile instead, cached as image layers.
set -euo pipefail

# Claude Code, with Anthropic's native installer. Here, not in a feature or
# the image, so it owns its install under ~/.local and can update itself.
# In the background: it's a download, independent of the apt work below.
claude_pid=""
if ! command -v claude >/dev/null; then
  curl -fsSL https://claude.ai/install.sh | bash &
  claude_pid=$!
fi

# The base image deletes downloaded packages after every apt run; keep them in
# the apt cache volume instead. Removed here rather than in the Dockerfile so
# the features' layers don't keep theirs.
sudo rm -f /etc/apt/apt.conf.d/docker-clean

# Playwright and Google Chrome, to check the board in a real browser. The
# Playwright MCP server defaults to the Chrome channel, not bundled Chromium.
# Playwright needs Node, which the feature adds after the Dockerfile, so it's
# here; the npm cache volume saves the download. Pinned so a rebuild doesn't
# pick up a just-published release.
if ! command -v playwright >/dev/null; then
  npm install -g --silent playwright@1.64.1
fi
# Chrome stays out of the image on purpose: the agent drives it, unsandboxed,
# at pages it chooses, so each new container gets the current release rather
# than one frozen in a cached layer. Through apt, from the repo the Dockerfile
# adds, so the download is cached until Google ships a new one.
# install-deps runs apt-get update before Playwright's own dependencies.
playwright install-deps chrome >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  google-chrome-stable >/dev/null
# Playwright's own ffmpeg, for video, which `playwright install chrome` used
# to bring along.
playwright install ffmpeg >/dev/null

if [ -n "$claude_pid" ]; then
  wait "$claude_pid"
fi

cat <<'MSG'

Factory Dev Container ready.
  - Sign in to Claude Code:  claude
  - GitHub:                  gh auth status   (or set GH_TOKEN on the host)
  - Run the tests:           tests/run.sh
  - Screenshot the board:    playwright screenshot --channel chrome http://127.0.0.1:4173/ board.png
  - Dogfood the factory:     claude --plugin-dir . --permission-mode auto, then /factory run
MSG
