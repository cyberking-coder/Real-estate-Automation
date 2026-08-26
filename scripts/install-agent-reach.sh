#!/usr/bin/env bash
# Install Agent Reach (https://github.com/Panniantong/Agent-Reach) for this project's agent.
#
# Agent Reach is a capability layer, not a library: it installs and health-checks
# the upstream tools an AI agent uses to read the web (yt-dlp, mcporter/Exa,
# Jina Reader, feedparser, gh CLI ...). Nothing here is imported by the n8n
# workflows - it is agent tooling, so it installs into $HOME, never into the repo.
#
#     bash scripts/install-agent-reach.sh
#     agent-reach doctor          # what is reachable right now
#
# Re-running is safe; every step is idempotent.
set -euo pipefail

# Installed straight from git rather than the /archive/main.zip tarball: pip, pipx and uv
# all shell out to git for this form, so it works behind a proxy that only whitelists git.
SRC="git+https://github.com/Panniantong/Agent-Reach.git@main"
export PATH="$HOME/.local/bin:$PATH"

say() { printf '\n==> %s\n' "$1"; }

say "Installing the agent-reach CLI"
if command -v uv >/dev/null 2>&1; then
    uv tool install --force "$SRC"
    uv tool install --force "yt-dlp[default]"
elif command -v pipx >/dev/null 2>&1; then
    pipx install --force "$SRC"
    pipx install --force "yt-dlp[default]"
else
    # PEP 668 makes a bare `pip install` fail on most distro Pythons, so use a venv.
    python3 -m venv "$HOME/.agent-reach-venv"
    "$HOME/.agent-reach-venv/bin/pip" install --quiet --upgrade "$SRC" "yt-dlp[default]"
    ln -sf "$HOME/.agent-reach-venv/bin/agent-reach" "$HOME/.local/bin/agent-reach"
    ln -sf "$HOME/.agent-reach-venv/bin/yt-dlp" "$HOME/.local/bin/yt-dlp"
fi

# yt-dlp needs a JS runtime for YouTube's player challenges; Node is already a
# dependency of n8n, so point yt-dlp at it.
if command -v node >/dev/null 2>&1; then
    say "Pointing yt-dlp at Node for YouTube player JS"
    mkdir -p "$HOME/.config/yt-dlp"
    grep -qxF -- '--js-runtimes node' "$HOME/.config/yt-dlp/config" 2>/dev/null \
        || printf '%s\n' '--js-runtimes node' >> "$HOME/.config/yt-dlp/config"
fi

if command -v npm >/dev/null 2>&1; then
    say "Installing mcporter and registering Exa web search"
    npm install -g mcporter
    # Exa is an MCP server, so the entry is config only - it still needs a
    # one-time OAuth approval in a browser before the first search works.
    mcporter config add exa https://mcp.exa.ai/mcp --scope home 2>/dev/null \
        || echo "    exa already registered with mcporter"
else
    echo "    npm not found - skipping mcporter/Exa (web search stays unavailable)"
fi

say "Registering SKILL.md with the agent"
agent-reach skill --install

say "Health check"
agent-reach doctor
