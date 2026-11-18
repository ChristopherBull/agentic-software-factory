# Only what no first-party feature covers; features (devcontainer.json) are
# layered on after this. Nothing here is pinned, so a rebuild without the
# layer cache picks up Ubuntu's updates.
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# shellcheck from Ubuntu's signed archive, as CI's runner image gets it. The
# only feature for it downloads an unverified binary from GitHub releases.
RUN apt-get update \
  && apt-get install -y --no-install-recommends shellcheck \
  && rm -rf /var/lib/apt/lists/*

# Docker copies an image directory's ownership into a named volume the first
# time it's mounted, so creating the mount points here means the volumes start
# owned by vscode instead of root.
USER vscode
RUN mkdir -p /home/vscode/.claude /home/vscode/.npm
USER root
