# Fixed per rebuild, so cached as image layers; features (devcontainer.json)
# are layered on after this. Packages aren't pinned, so a rebuild without the
# layer cache picks up Ubuntu's updates. Pinned to a release so the next LTS
# doesn't arrive unannounced.
FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04

# From Ubuntu's signed archive: shellcheck as CI's runner gets it, python3 for
# the board's localhost server, zstd so Claude Code's installer fetches the
# compressed binary (135 MB, not 373 MB).
RUN apt-get update \
  && apt-get install -y --no-install-recommends shellcheck python3 zstd \
  && rm -rf /var/lib/apt/lists/*

# Google's apt repo, so post-create installs Chrome through apt and its
# download cache, instead of Playwright's script curling the .deb every time.
# The same file Chrome's package writes, so its postinst leaves it alone.
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
  && printf '%s\n' \
    'Types: deb' \
    'URIs: https://dl.google.com/linux/chrome-stable/deb/' \
    'Suites: stable' \
    'Components: main' \
    'Architectures: amd64' \
    'Signed-By: /usr/share/keyrings/google-chrome.gpg' \
    > /etc/apt/sources.list.d/google-chrome.sources

# Docker copies an image directory's ownership into a named volume the first
# time it's mounted, so creating the mount points here means the volumes start
# owned by vscode instead of root.
USER vscode
RUN mkdir -p /home/vscode/.claude /home/vscode/.npm
USER root
